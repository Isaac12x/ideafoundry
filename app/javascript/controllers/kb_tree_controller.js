import { Controller } from "@hotwired/stimulus"

const MENU_VISIBILITY = {
  newFile: (node) => node.type !== "file",
  newFolder: (node) => node.type !== "file",
  edit: (node) => node.type === "file" && node.editable,
  rename: (node) => node.type !== "root",
  extract: (node) => node.type === "file" && node.extractable,
  job: (node) => node.type === "file" || node.type === "dir",
  divider: (node) => node.type !== "root",
  delete: (node) => node.type !== "root",
  finderDivider: () => true,
  openFinder: () => true
}

export default class extends Controller {
  static targets = ["menu", "items", "item", "prompt", "promptInput", "format"]
  static values = {
    extractUrl: String,
    createUrl: String,
    uploadUrl: String,
    renameUrl: String,
    moveUrl: String,
    preferenceUrl: String,
    openUrl: String,
    deleteUrl: String,
    editUrl: String
  }

  connect() {
    this._onDocMousedown = (event) => {
      if (this.hasMenuTarget && !this.menuTarget.contains(event.target)) this._hide()
    }
    this._onDocKeydown = (event) => { if (event.key === "Escape") this._hide() }
    this._onBeforeStreamRender = (event) => this._preserveSelectionAcrossStream(event)
    document.addEventListener("turbo:before-stream-render", this._onBeforeStreamRender)
  }

  disconnect() {
    this._unbindDocListeners()
    document.removeEventListener("turbo:before-stream-render", this._onBeforeStreamRender)
  }

  show(event) {
    event.preventDefault()
    event.stopPropagation()

    const params = event.params
    this._node = {
      type: params.type,
      rel: params.rel ?? "",
      src: params.src,
      extractable: !!params.extractable,
      editable: !!params.editable,
      favorite: !!params.favorite
    }

    this.itemsTarget.hidden = false
    this.promptTarget.hidden = true
    this.itemTargets.forEach((element) => {
      const visible = MENU_VISIBILITY[element.dataset.menuItem]
      element.hidden = visible ? !visible(this._node) : false
    })

    const menu = this.menuTarget
    menu.classList.add("is-visible")
    menu.style.left = "0px"
    menu.style.top = "0px"
    const origin = menu.getBoundingClientRect()
    const x = Math.min(event.clientX, window.innerWidth - menu.offsetWidth - 8)
    const y = Math.min(event.clientY, window.innerHeight - menu.offsetHeight - 8)
    menu.style.left = `${x - origin.left}px`
    menu.style.top = `${y - origin.top}px`

    document.addEventListener("mousedown", this._onDocMousedown)
    document.addEventListener("keydown", this._onDocKeydown)
  }

  newFile(event) {
    event.stopPropagation()
    this._promptFor("file")
  }

  newFolder(event) {
    event.stopPropagation()
    this._promptFor("folder")
  }

  rename(event) {
    event.stopPropagation()
    this._promptFor("rename")
  }

  promptInputChanged() {
    if (!this.hasFormatTarget) return
    const isUrl = /^https?:\/\/\S+$/i.test(this.promptInputTarget.value.trim())
    this.formatTarget.hidden = !(this._promptMode === "file" && isUrl)
  }

  promptSubmit(event) {
    event.preventDefault()
    const name = this.promptInputTarget.value.trim()
    if (!name) return

    const node = this._node
    if (this._promptMode === "rename") {
      this._submitForm(this.renameUrlValue, "patch", { src: node.src, path: node.rel, name })
    } else {
      const fields = { src: node.src, dir: this._targetDir(node), name, kind: this._promptMode }
      if (this.hasFormatTarget && !this.formatTarget.hidden) fields.format = this.formatTarget.value
      this._submitForm(this.createUrlValue, "post", fields)
    }
  }

  edit(event) {
    event.stopPropagation()
    const frame = document.getElementById("kb-content")
    frame.src = `${this.editUrlValue}?src=${encodeURIComponent(this._node.src)}&file=${encodeURIComponent(this._node.rel)}`
    this._hide()
  }

  extract(event) {
    event.stopPropagation()
    this._submitForm(this.extractUrlValue, "post", { src: this._node.src, file: this._node.rel })
  }

  job(event) {
    event.stopPropagation()
    const node = this._node
    const trigger = event.currentTarget
    this._hide()
    trigger.dispatchEvent(new CustomEvent("kb-job:open", {
      bubbles: true,
      detail: {
        src: node.src,
        path: node.rel,
        contextKind: node.type === "dir" ? "folder" : "file",
        label: node.rel.split("/").pop()
      }
    }))
  }

  async openFinder(event) {
    event.stopPropagation()
    const node = this._node
    this._hide()
    const response = await fetch(this.openUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this._csrfToken() },
      body: JSON.stringify({ src: node.src, path: node.rel })
    })
    if (!response.ok) {
      const result = await response.json().catch(() => ({}))
      await window.AppDialog?.alert(result.error || "Finder could not open this entry.", {
        title: "Couldn’t open Finder",
        confirmLabel: "Got it",
      })
    }
  }

  toggleFavorite(event) {
    event.preventDefault()
    event.stopPropagation()
    const params = event.params
    const nextFavorite = !params.favorite
    event.currentTarget.classList.toggle("is-favorite", nextFavorite)
    this._submitForm(this.preferenceUrlValue, "patch", {
      src: params.src,
      path: params.rel ?? "",
      entry_type: params.type,
      favorite: nextFavorite ? "1" : "0"
    })
  }

  async destroy(event) {
    event.stopPropagation()
    const node = this._node
    const name = node.rel.split("/").pop()
    const message = node.type === "dir"
      ? `Delete folder "${name}" and everything inside it?`
      : `Delete "${name}"?`
    this._hide()
    const confirmed = await window.AppDialog?.confirm(message, {
      title: node.type === "dir" ? "Delete folder?" : "Delete file?",
      confirmLabel: "Delete",
      variant: "danger",
    })
    if (!confirmed) return
    this._submitForm(this.deleteUrlValue, "delete", { src: node.src, path: node.rel })
  }

  dragStart(event) {
    const params = event.params
    this._drag = { type: params.type, rel: params.rel, src: params.src }
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", params.rel)
    event.currentTarget.classList.add("is-dragging")
  }

  dragEnd(event) {
    this._drag = null
    event.currentTarget.classList.remove("is-dragging")
    this.element.querySelectorAll(".is-drop-target").forEach((element) => element.classList.remove("is-drop-target"))
  }

  dragOver(event) {
    const externalFiles = this._hasExternalFiles(event)
    if (!externalFiles && !this._canDrop(event.params)) return

    event.preventDefault()
    event.dataTransfer.dropEffect = externalFiles ? "copy" : "move"
    event.currentTarget.classList.add("is-drop-target")
  }

  dragLeave(event) {
    event.currentTarget.classList.remove("is-drop-target")
  }

  drop(event) {
    const destination = event.params
    event.currentTarget.classList.remove("is-drop-target")

    if (this._hasExternalFiles(event)) {
      event.preventDefault()
      this._uploadFiles(event.dataTransfer.files, destination)
      return
    }

    if (!this._canDrop(destination)) return
    event.preventDefault()
    const drag = this._drag
    this._drag = null
    this._submitForm(this.moveUrlValue, "patch", {
      src: drag.src,
      path: drag.rel,
      dest_src: destination.src,
      dest_dir: destination.type === "root" ? "" : destination.rel
    })
  }

  _canDrop(destination) {
    const drag = this._drag
    if (!drag) return false

    const destinationRelative = destination.type === "root" ? "" : destination.rel
    if (drag.src === destination.src) {
      if (drag.type === "dir" && (destinationRelative === drag.rel || destinationRelative.startsWith(`${drag.rel}/`))) return false
      const parent = drag.rel.split("/").slice(0, -1).join("/")
      if (parent === destinationRelative) return false
    }
    return true
  }

  _hasExternalFiles(event) {
    return !this._drag && Array.from(event.dataTransfer?.types || []).includes("Files")
  }

  async _uploadFiles(fileList, destination) {
    const files = Array.from(fileList || [])
    if (!files.length) return

    const data = new FormData()
    data.append("src", destination.src)
    data.append("dir", destination.type === "root" ? "" : destination.rel)
    files.forEach((file) => data.append("files[]", file, file.name))
    this._appendSelection(data)

    const response = await fetch(this.uploadUrlValue, {
      method: "POST",
      headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": this._csrfToken() },
      body: data
    })
    const html = await response.text()
    if (html) window.Turbo?.renderStreamMessage(html)
  }

  _promptFor(mode) {
    this._promptMode = mode
    this.itemsTarget.hidden = true
    this.promptTarget.hidden = false
    if (this.hasFormatTarget) this.formatTarget.hidden = true

    const input = this.promptInputTarget
    if (mode === "rename") {
      input.value = this._node.rel.split("/").pop()
      input.placeholder = "New name"
    } else {
      input.value = ""
      input.placeholder = mode === "folder" ? "Folder name" : "File name or download URL"
    }
    input.focus()
    input.select()
  }

  _targetDir(node) {
    if (node.type === "dir") return node.rel
    if (node.type === "root") return ""
    return node.rel.split("/").slice(0, -1).join("/")
  }

  _submitForm(url, method, fields) {
    const form = document.createElement("form")
    form.method = "post"
    form.action = url
    const csrf = this._csrfToken()
    if (csrf) this._appendHidden(form, "authenticity_token", csrf)
    if (method !== "post") this._appendHidden(form, "_method", method)
    this._appendSelection(form)
    Object.entries(fields).forEach(([name, value]) => this._appendHidden(form, name, value))

    document.body.appendChild(form)
    form.addEventListener("turbo:submit-end", () => form.remove())
    form.requestSubmit()
    this._hide()
  }

  _appendSelection(container) {
    const active = this.element.querySelector(".kb-file-row.is-active")
    if (!active) return

    const values = {
      sel_src: active.dataset.kbTreeSrcParam ?? "",
      sel_file: active.dataset.kbTreeRelParam ?? ""
    }
    Object.entries(values).forEach(([name, value]) => {
      if (container instanceof FormData) container.append(name, value)
      else this._appendHidden(container, name, value)
    })
  }

  _appendHidden(form, name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    form.appendChild(input)
  }

  _preserveSelectionAcrossStream(event) {
    const stream = event.target
    if (stream?.getAttribute?.("target") !== "kb-sidebar-tree") return

    const active = this.element.querySelector(".kb-file-row.is-active")
    if (!active) return
    const selected = {
      src: active.dataset.kbTreeSrcParam,
      rel: active.dataset.kbTreeRelParam
    }
    const originalRender = event.detail.render
    event.detail.render = async (streamElement) => {
      await originalRender(streamElement)
      const rows = this.element.querySelectorAll(".kb-file-row")
      const replacement = Array.from(rows).find((row) =>
        row.dataset.kbTreeSrcParam === selected.src && row.dataset.kbTreeRelParam === selected.rel
      )
      replacement?.classList.add("is-active")
      replacement?.querySelector(".kb-file-link")?.classList.add("is-active")
    }
  }

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content ?? ""
  }

  _hide() {
    if (this.hasMenuTarget) this.menuTarget.classList.remove("is-visible")
    this._unbindDocListeners()
  }

  _unbindDocListeners() {
    document.removeEventListener("mousedown", this._onDocMousedown)
    document.removeEventListener("keydown", this._onDocKeydown)
  }
}
