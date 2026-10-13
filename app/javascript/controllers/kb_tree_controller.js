import { Controller } from "@hotwired/stimulus"

const MENU_VISIBILITY = {
  newFile: (node) => node.type !== "file",
  newFolder: (node) => node.type !== "file",
  newProject: (node) => node.type !== "file",
  convertProject: (node) => node.type === "dir" && !node.project,
  newTest: (node) => node.type === "dir" && (node.project || node.testsDir),
  download: (node) => node.type !== "file",
  edit: (node) => node.type === "file" && node.editable,
  rename: (node) => node.type !== "root",
  extract: (node) => node.type === "file" && node.extractable && !node.private,
  job: (node) => (node.type === "file" || node.type === "dir") && !node.private,
  divider: (node) => node.type !== "root",
  delete: (node) => node.type !== "root",
  finderDivider: () => true,
  openFinder: () => true
}

const TREEITEM = '[role="treeitem"]'

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
    projectConvertUrl: String,
    projectTestUrl: String,
    editUrl: String
  }

  connect() {
    this._onDocMousedown = (event) => {
      if (this.hasMenuTarget && !this.menuTarget.contains(event.target)) this._hide()
    }
    this._onDocKeydown = (event) => this._menuKeydown(event)
    this._onTreeKeydown = (event) => this._treeKeydown(event)
    this._onTreeFocusin = (event) => {
      const row = event.target.closest?.(TREEITEM)
      if (row) this._setRoving(row)
    }
    this.element.addEventListener("keydown", this._onTreeKeydown)
    this.element.addEventListener("focusin", this._onTreeFocusin)
    // Turbo broadcasts and folder toggles change the tree under us; keep ARIA state and the roving tab stop in step.
    this._observer = new MutationObserver(() => this._queueSync())
    this._observer.observe(this.element, { subtree: true, childList: true, attributes: true, attributeFilter: ["class"] })
    this._syncTree()
    this._onBeforeStreamRender = (event) => this._preserveSelectionAcrossStream(event)
    document.addEventListener("turbo:before-stream-render", this._onBeforeStreamRender)
    // After the folder controllers inside restore their saved collapsed state.
    this._revealTimer = window.setTimeout(() => this._revealFromUrl())
  }

  // ?src=&folder= (e.g. a folder linked from an idea): folders have no pane
  // view, so open the way down to the folder, expand it and bring it into view.
  _revealFromUrl() {
    const params = new URLSearchParams(window.location.search)
    const rel = params.get("folder")
    const row = rel && this._rowFor(params.get("src") ?? "0", rel)
    if (!row) return

    this._expandTo(row)
    row.scrollIntoView({ block: "center" })
    row.classList.add("is-revealed")
    row.addEventListener("animationend", () => row.classList.remove("is-revealed"), { once: true })
  }

  disconnect() {
    window.clearTimeout(this._revealTimer)
    this._observer?.disconnect()
    this.element.removeEventListener("keydown", this._onTreeKeydown)
    this.element.removeEventListener("focusin", this._onTreeFocusin)
    this._unbindDocListeners()
    document.removeEventListener("turbo:before-stream-render", this._onBeforeStreamRender)
  }

  // Optimistically drop the "new download" dot; the server clears opened_at on open.
  markSeen(event) {
    event.currentTarget.closest(".kb-file-row")?.classList.remove("is-new")
  }

  show(event) {
    event.preventDefault()
    event.stopPropagation()
    this._open(event.params, event.clientX, event.clientY, event.currentTarget?.closest?.(TREEITEM))
  }

  _open(params, clientX, clientY, invoker) {
    this._invoker = invoker || null
    this._node = {
      type: params.type,
      rel: params.rel ?? "",
      src: params.src,
      extractable: !!params.extractable,
      editable: !!params.editable,
      favorite: !!params.favorite,
      private: !!params.private,
      project: !!params.project,
      testsDir: !!params.testsDir
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
    const x = Math.min(clientX, window.innerWidth - menu.offsetWidth - 8)
    const y = Math.min(clientY, window.innerHeight - menu.offsetHeight - 8)
    menu.style.left = `${x - origin.left}px`
    menu.style.top = `${y - origin.top}px`

    document.addEventListener("mousedown", this._onDocMousedown)
    document.addEventListener("keydown", this._onDocKeydown)
    this._menuItems()[0]?.focus()
  }

  _menuItems() {
    return this.itemTargets.filter((el) => el.matches?.('[role="menuitem"]') && !el.hidden)
  }

  _menuKeydown(event) {
    if (event.key === "Escape") {
      const invoker = this._invoker
      this._hide()
      invoker?.focus?.()
      return
    }
    if (event.key === "Tab") return this._hide()

    const items = this._menuItems()
    if (!items.length || !["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return
    event.preventDefault()
    const at = items.indexOf(document.activeElement)
    const next = event.key === "Home" ? 0
      : event.key === "End" ? items.length - 1
      : event.key === "ArrowDown" ? (at + 1) % items.length
      : (at <= 0 ? items.length - 1 : at - 1)
    items[next].focus()
  }

  // ── Tree keyboard / ARIA ─────────────────────────────────────────────
  _treeKeydown(event) {
    const row = event.target
    if (!row?.matches?.(TREEITEM)) return // keys inside inputs/buttons stay theirs

    if (event.key === "ContextMenu" || (event.key === "F10" && event.shiftKey)) {
      event.preventDefault()
      const box = row.getBoundingClientRect()
      this._open(this._paramsFor(row), box.left + 16, box.bottom, row)
      return
    }
    if (event.altKey || event.ctrlKey || event.metaKey) return

    const items = this._items()
    const at = items.indexOf(row)
    let target
    switch (event.key) {
      case "ArrowDown": target = items[at + 1]; break
      case "ArrowUp": target = items[at - 1]; break
      case "Home": target = items[0]; break
      case "End": target = items[items.length - 1]; break
      case "ArrowRight":
        if (this._collapsed(row)) this._toggle(row)
        else if (this._isDir(row)) target = this._parentItem(items[at + 1]) === row ? items[at + 1] : null
        break
      case "ArrowLeft":
        if (this._isDir(row) && this._collapsed(row) === false && row.matches(".kb-dir-header")) this._toggle(row)
        else target = this._parentItem(row)
        break
      case "Enter": this._activate(row); break
      default: return
    }
    event.preventDefault()
    if (target) this._focusItem(target)
  }

  _items() {
    return Array.from(this.element.querySelectorAll(TREEITEM)).filter((row) => {
      if (row.hidden) return false
      const start = row.matches(".kb-dir-header, .kb-folder-header") ? row.parentElement.parentElement : row.parentElement
      return !start?.closest(".kb-dir-group.is-collapsed")
    })
  }

  _isDir(row) { return row.matches(".kb-dir-header, .kb-folder-header") }

  // true/false for collapsible folders, null otherwise.
  _collapsed(row) {
    return row.matches(".kb-dir-header") ? row.parentElement.classList.contains("is-collapsed") : null
  }

  _toggle(row) { row.querySelector(".kb-dir-toggle")?.click() }

  _parentItem(row) {
    if (!row) return null
    const start = this._isDir(row) ? row.parentElement.parentElement : row.parentElement
    return start?.closest(".kb-dir-group, .kb-folder-group")?.querySelector(":scope > .kb-node") ?? null
  }

  _activate(row) {
    const link = row.querySelector(".kb-file-link, .kb-project-link")
    if (link) link.click()
    else if (row.matches(".kb-dir-header")) this._toggle(row)
  }

  _paramsFor(row) {
    // Same typecasting Stimulus applies to data-kb-tree-*-param attributes.
    const cast = (v) => { try { return JSON.parse(v) } catch { return v } }
    const params = {}
    for (const [key, value] of Object.entries(row.dataset)) {
      const m = key.match(/^kbTree(.+)Param$/)
      if (m) params[m[1][0].toLowerCase() + m[1].slice(1)] = cast(value)
    }
    return params
  }

  _focusItem(row) {
    this._setRoving(row)
    row.focus()
  }

  _setRoving(row) {
    this.element.querySelectorAll(`${TREEITEM}[tabindex="0"]`).forEach((el) => { if (el !== row) el.setAttribute("tabindex", "-1") })
    row.setAttribute("tabindex", "0")
    this._rovingKey = this._keyOf(row)
  }

  _keyOf(row) {
    return { src: row.dataset.kbTreeSrcParam, rel: row.dataset.kbTreeRelParam ?? "" }
  }

  _queueSync() {
    if (this._syncQueued) return
    this._syncQueued = true
    queueMicrotask(() => { this._syncQueued = false; this._syncTree() })
  }

  _syncTree() {
    this.element.querySelectorAll(".kb-dir-header").forEach((row) => {
      row.setAttribute("aria-expanded", String(!row.parentElement.classList.contains("is-collapsed")))
    })
    this.element.querySelectorAll(".kb-file-row").forEach((row) => {
      const on = row.classList.contains("is-active")
      row.setAttribute("aria-selected", String(on))
      if (on) row.setAttribute("aria-current", "page"); else row.removeAttribute("aria-current")
    })

    const items = this._items()
    if (!items.length) return
    const current = items.find((el) => el.getAttribute("tabindex") === "0" && el.matches(TREEITEM))
    // A re-render replaces nodes (all server-rendered at tabindex -1): recover by key, then active, then first.
    const key = this._rovingKey
    const pick = current
      || (key && items.find((el) => el.dataset.kbTreeSrcParam === key.src && (el.dataset.kbTreeRelParam ?? "") === key.rel))
      || items.find((el) => el.classList.contains("is-active"))
      || items[0]
    items.forEach((el) => el.setAttribute("tabindex", el === pick ? "0" : "-1"))
    this.element.querySelectorAll(`${TREEITEM}[tabindex="0"]`).forEach((el) => { if (el !== pick) el.setAttribute("tabindex", "-1") })
  }

  // New nodes are created straight away with a placeholder name; the server
  // flags the new row and we drop into inline naming on it, so people type
  // the name where the name is going to live.
  newFile(event) {
    event.stopPropagation()
    this._create("file")
  }

  newFolder(event) {
    event.stopPropagation()
    this._create("folder")
  }

  newProject(event) {
    event.stopPropagation()
    this._create("project")
  }

  // Marks an existing folder as a project in place; nothing moves.
  convertProject(event) {
    event.stopPropagation()
    this._submitForm(this.projectConvertUrlValue, "post", { src: this._node.src, path: this._node.rel })
  }

  // Server answers with a placeholder test folder, then inline naming kicks in.
  newTest(event) {
    event.stopPropagation()
    this._submitForm(this.projectTestUrlValue, "post", { src: this._node.src, dir: this._node.rel })
  }

  download(event) {
    event.stopPropagation()
    this._promptFor("download")
  }

  rename(event) {
    event.stopPropagation()
    const row = this._rowFor(this._node.src, this._node.rel)
    this._hide()
    if (row) this._startNaming(row)
  }

  _create(kind) {
    const node = this._node
    this._submitForm(this.createUrlValue, "post", {
      src: node.src,
      dir: this._targetDir(node),
      kind
    })
  }

  // ── Inline naming ────────────────────────────────────────────────────
  _startNaming(row) {
    const input = row.querySelector(".kb-node-name-input")
    if (!input) return

    row.classList.add("is-naming")
    row.draggable = false
    input.hidden = false
    input.dataset.original = input.value
    row.querySelectorAll(".kb-file-link, .kb-dir-label").forEach((element) => { element.hidden = true })

    input.focus()
    // Select the stem only, so the extension survives a straight retype.
    const stem = input.value.lastIndexOf(".")
    input.setSelectionRange(0, stem > 0 ? stem : input.value.length)
  }

  _stopNaming(row) {
    const input = row.querySelector(".kb-node-name-input")
    row.classList.remove("is-naming")
    row.draggable = true
    if (input) {
      input.hidden = true
      delete input.dataset.kbAutofocus
    }
    row.querySelectorAll(".kb-file-link, .kb-dir-label").forEach((element) => { element.hidden = false })
  }

  nameKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      event.target.blur()
      return
    }
    if (event.key !== "Escape") return

    event.preventDefault()
    event.stopPropagation()
    const input = event.target
    input.value = input.dataset.original ?? input.value
    const row = input.closest(".kb-node")
    if (row) this._stopNaming(row)
  }

  async nameCommit(event) {
    const input = event.target
    const row = input.closest(".kb-node")
    if (this._rerendering || !row || !row.classList.contains("is-naming")) return

    const name = input.value.trim()
    const original = input.dataset.original ?? ""
    this._stopNaming(row)
    if (!name || name === original) {
      input.value = original
      return
    }

    const result = await this._postJson(this.renameUrlValue, "patch", {
      src: row.dataset.kbTreeSrcParam,
      path: row.dataset.kbTreeRelParam,
      name
    })

    // Renaming touches one row, so patch that row rather than re-rendering
    // the whole tree — the pane, scroll, and collapse state all stay put.
    if (result?.rel) {
      this._applyRename(row, result.rel, result.name)
    } else {
      input.value = original
      if (result?.error) this._alert(result.error)
    }
  }

  _applyRename(row, rel, name) {
    const previous = row.dataset.kbTreeRelParam
    row.dataset.kbTreeRelParam = rel
    row.querySelectorAll("[data-kb-tree-rel-param], [data-kb-icon-picker-rel-param]").forEach((element) => {
      if (element.dataset.kbTreeRelParam === previous) element.dataset.kbTreeRelParam = rel
      if (element.dataset.kbIconPickerRelParam === previous) element.dataset.kbIconPickerRelParam = rel
    })

    const input = row.querySelector(".kb-node-name-input")
    if (input) input.value = name

    const link = row.querySelector(".kb-file-link")
    if (link) {
      link.textContent = name
      const url = new URL(link.href, window.location.origin)
      url.searchParams.set("file", rel)
      link.href = `${url.pathname}${url.search}`
      link.dataset.kbNotesFileParam = rel
      // A renamed file may now render differently (or be the open one), so
      // refresh the pane when it is the active row.
      if (row.classList.contains("is-active")) {
        const frame = document.getElementById("kb-content")
        if (frame) frame.src = link.href
      }
      return
    }

    const label = row.querySelector(".kb-dir-label")
    if (label) {
      label.textContent = name
      // Descendant rels moved with the folder; reload the tree for those.
      this._refreshTree()
    }
  }

  promptInputChanged() {
    if (!this.hasFormatTarget) return
    this.formatTarget.hidden = !/^https?:\/\/\S+$/i.test(this.promptInputTarget.value.trim())
  }

  promptSubmit(event) {
    event.preventDefault()
    const name = this.promptInputTarget.value.trim()
    if (!name) return

    const node = this._node
    const fields = { src: node.src, dir: this._targetDir(node), name, kind: "file" }
    if (this.hasFormatTarget && !this.formatTarget.hidden) fields.format = this.formatTarget.value
    this._submitForm(this.createUrlValue, "post", fields)
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

  // Favouriting is a one-bit change to one row: flip it locally and tell the
  // server in the background. No stream, no tree re-render, no banner.
  async toggleFavorite(event) {
    event.preventDefault()
    event.stopPropagation()
    const button = event.currentTarget
    const params = event.params
    const next = !params.favorite
    this._paintFavorite(button, next)

    const result = await this._postJson(this.preferenceUrlValue, "patch", {
      src: params.src,
      path: params.rel ?? "",
      entry_type: params.type,
      favorite: next ? "1" : "0"
    })
    if (result?.error) {
      this._paintFavorite(button, !next)
      this._alert(result.error)
    }
  }

  _paintFavorite(button, favorite) {
    const label = favorite ? "Remove from favourites" : "Add to favourites"
    button.classList.toggle("is-favorite", favorite)
    button.dataset.kbTreeFavoriteParam = favorite
    button.setAttribute("aria-pressed", favorite ? "true" : "false")
    button.setAttribute("aria-label", label)
    button.title = label

    const row = button.closest(".kb-node")
    if (row) row.dataset.kbTreeFavoriteParam = favorite
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
      this._uploadFiles(event.dataTransfer.files, destination, event.currentTarget)
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

  async _uploadFiles(fileList, destination, header) {
    const files = Array.from(fileList || [])
    if (!files.length) return
    const pending = this._pendingRows(files, header)

    const data = new FormData()
    data.append("src", destination.src)
    data.append("dir", destination.type === "root" ? "" : destination.rel)
    files.forEach((file) => data.append("files[]", file, file.name))
    this._appendSelection(data)

    let html = ""
    try {
      const response = await fetch(this.uploadUrlValue, {
        method: "POST",
        headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": this._csrfToken() },
        body: data
      })
      html = await response.text()
    } finally {
      pending.forEach((row) => row.remove())
    }
    if (html) window.Turbo?.renderStreamMessage(html)
  }

  // Spinner rows in the drop target until the upload finishes (same look as async downloads).
  _pendingRows(files, header) {
    const children = header?.parentElement?.querySelector(":scope > .kb-node-children")
    if (!children) return []

    children.querySelector(":scope > .kb-no-files")?.remove()
    return files.map((file) => {
      const row = document.createElement("div")
      row.className = "kb-async-row kb-download-row kb-download-row--pending"
      row.innerHTML = '<span class="kb-download-pending"><svg class="kb-download-spinner" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg><span></span></span>'
      row.querySelector("span span").textContent = file.name
      children.prepend(row)
      return row
    })
  }

  _promptFor() {
    this.itemsTarget.hidden = true
    this.promptTarget.hidden = false
    if (this.hasFormatTarget) this.formatTarget.hidden = true

    const input = this.promptInputTarget
    input.value = ""
    input.placeholder = "Paste a link to download"
    input.focus()
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
    const selected = active && {
      src: active.dataset.kbTreeSrcParam,
      rel: active.dataset.kbTreeRelParam
    }
    const naming = this._namingSnapshot()
    const focused = document.activeElement?.matches?.(TREEITEM) ? this._keyOf(document.activeElement) : null
    const scroller = this.element.querySelector(".kb-sidebar-inner")
    const scrollTop = scroller?.scrollTop ?? 0
    const originalRender = event.detail.render
    event.detail.render = async (streamElement) => {
      // Polls and broadcasts replace the tree at any moment; the old input
      // losing focus on the way out must not commit a half-typed name.
      this._rerendering = true
      try {
        await originalRender(streamElement)
      } finally {
        this._rerendering = false
      }
      const replacement = selected && Array.from(this.element.querySelectorAll(".kb-file-row")).find((row) =>
        row.dataset.kbTreeSrcParam === selected.src && row.dataset.kbTreeRelParam === selected.rel
      )
      replacement?.classList.add("is-active")
      replacement?.querySelector(".kb-file-link")?.classList.add("is-active")
      if (scroller) scroller.scrollTop = scrollTop
      if (focused) {
        const again = this._rowFor(focused.src, focused.rel)
        if (again) this._focusItem(again)
      }
      if (!this._resumeNaming() && naming) this._restoreNaming(naming)
    }
  }

  _namingSnapshot() {
    const row = this.element.querySelector(".kb-node.is-naming")
    const input = row?.querySelector(".kb-node-name-input")
    if (!input) return null
    return {
      src: row.dataset.kbTreeSrcParam,
      rel: row.dataset.kbTreeRelParam,
      value: input.value,
      original: input.dataset.original,
      start: input.selectionStart,
      end: input.selectionEnd
    }
  }

  _restoreNaming(naming) {
    const row = this._rowFor(naming.src, naming.rel)
    const input = row?.querySelector(".kb-node-name-input")
    if (!input) return
    this._startNaming(row)
    input.value = naming.value
    input.dataset.original = naming.original ?? input.dataset.original
    input.setSelectionRange(naming.start, naming.end)
  }

  // The server marks a just-created node; drop straight into naming it. It
  // may have landed in a collapsed folder, so open the way down to it first.
  _resumeNaming() {
    const input = this.element.querySelector(".kb-node-name-input[data-kb-autofocus]")
    const row = input?.closest(".kb-node")
    if (!row) return false

    this._expandTo(row)
    this._startNaming(row)
    return true
  }

  // Opens every collapsed folder from the row up (the row's own folder included).
  _expandTo(row) {
    let group = row.closest(".kb-dir-group")
    while (group) {
      if (group.classList.contains("is-collapsed")) group.querySelector(":scope > .kb-dir-header .kb-dir-toggle")?.click()
      group = group.parentElement?.closest(".kb-dir-group")
    }
  }

  // Small JSON round trip for the in-place operations (rename, favourite).
  // Returns the parsed body, or null when the request itself failed.
  async _postJson(url, method, fields) {
    try {
      const response = await fetch(url, {
        method: method.toUpperCase(),
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": this._csrfToken()
        },
        body: JSON.stringify(fields)
      })
      return await response.json().catch(() => (response.ok ? {} : null))
    } catch {
      return null
    }
  }

  _rowFor(src, rel) {
    return this.element.querySelector(
      `.kb-node[data-kb-tree-src-param="${src}"][data-kb-tree-rel-param="${CSS.escape(rel)}"]`
    )
  }

  async _refreshTree() {
    const url = this.element.querySelector("#kb-sidebar-tree")?.dataset.kbTreeSyncUrlValue
    if (!url) return

    const response = await fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" } })
    if (response.ok) window.Turbo?.renderStreamMessage(await response.text())
  }

  _alert(message) {
    window.AppDialog?.alert(message, { title: "That didn’t work", confirmLabel: "Got it" })
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
