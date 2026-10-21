import { Controller } from "@hotwired/stimulus"
import { confirmDialog, alertDialog } from "lib/app_dialog"
import { dropZone, insertNear, shift } from "lib/kb_order"
import { embeddedUrl, clipFromUrl, formatClip } from "lib/kb_clip_time"

const MENU_VISIBILITY = {
  newFile: (node) => node.type !== "file",
  newFolder: (node) => node.type !== "file" || node.multi,
  newProject: (node) => node.type !== "file",
  convertProject: (node) => node.type === "dir" && !node.project,
  newBuildPlan: (node) => node.type !== "file",
  convertBuildPlan: (node) => node.type === "dir" && !node.project,
  newTest: (node) => node.type === "dir" && ((node.project && !node.build) || node.testsDir),
  download: (node) => node.type !== "file",
  edit: (node) => node.type === "file" && node.editable,
  rename: (node) => node.type !== "root",
  extract: (node) => node.type === "file" && node.extractable && !node.private,
  job: (node) => (node.type === "file" || node.type === "dir") && !node.private,
  divider: (node) => node.type !== "root",
  delete: (node) => node.type !== "root",
  aliasStart: (node) => node.type === "file",
  aliasOpen: (node) => node.type === "alias" && !node.broken,
  aliasReveal: (node) => node.type === "alias" && !node.broken,
  aliasRemove: (node) => node.type === "alias",
  aliasHere: (node) => node.aliasPending && (node.type === "dir" || node.type === "root"),
  sortDivider: (node) => node.type === "dir" || node.type === "root",
  sortFolder: (node) => node.type === "dir" || node.type === "root",
  finderDivider: () => true,
  openFinder: () => true
}

const TREEITEM = '[role="treeitem"]'

export default class extends Controller {
  static targets = ["menu", "items", "item", "prompt", "promptInput", "format", "clip", "clipStart", "clipEnd", "note", "noteInput"]
  static values = {
    extractUrl: String,
    createUrl: String,
    uploadUrl: String,
    renameUrl: String,
    moveUrl: String,
    orderUrl: String,
    aliasUrl: String,
    sortUrl: String,
    preferenceUrl: String,
    openUrl: String,
    deleteUrl: String,
    projectConvertUrl: String,
    projectTestUrl: String,
    projectMaterialsUrl: String,
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
    this._onFrameLoad = (event) => this._highlightFrameFile(event)
    document.addEventListener("turbo:frame-load", this._onFrameLoad)
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
    document.removeEventListener("turbo:frame-load", this._onFrameLoad)
  }

  // Optimistically drop the "new download" dot; the server clears opened_at on open.
  markSeen(event) {
    event.currentTarget.closest(".kb-file-row")?.classList.remove("is-new")
  }

  // The tree is not re-rendered when the pane changes, so is-active would stay on
  // the file selected at page load. Whatever opens a file in kb-content (tree,
  // project pages, downloads) lands here and moves the highlight.
  _highlightFrameFile(event) {
    if (event.target?.id !== "kb-content") return
    let params
    try { params = new URL(event.target.src).searchParams } catch (_error) { return }
    const src = params.get("src")
    const file = params.get("file")
    if (src === null || !file) return
    const row = Array.from(this.element.querySelectorAll(".kb-file-row")).find((el) =>
      String(el.dataset.kbTreeSrcParam) === src && String(el.dataset.kbTreeRelParam) === file
    )
    if (!row) return
    this.element.querySelectorAll(".kb-file-row.is-active, .kb-file-link.is-active").forEach((el) => el.classList.remove("is-active"))
    row.classList.add("is-active")
    row.querySelector(".kb-file-link")?.classList.add("is-active")
    this._queueSync()
  }

  show(event) {
    event.preventDefault()
    event.stopPropagation()
    this._open(event.params, event.clientX, event.clientY, event.currentTarget?.closest?.(TREEITEM))
  }

  _open(params, clientX, clientY, invoker) {
    this._invoker = invoker || null
    const multi = !!invoker?.classList?.contains("is-multi") && this._multiRows().length > 1
    this._node = {
      multi,
      type: params.type,
      rel: String(params.rel ?? ""), // Stimulus casts "2024" to a Number
      src: params.src,
      extractable: !!params.extractable,
      editable: !!params.editable,
      favorite: !!params.favorite,
      private: !!params.private,
      project: !!params.project,
      testsDir: !!params.testsDir,
      build: !!params.build,
      sort: params.sort ? String(params.sort) : "",
      linkId: params.linkId,
      broken: !!params.broken,
      targetSrc: params.targetSrc,
      targetRel: String(params.targetRel ?? ""),
      aliasPending: !!this._aliasSource
    }

    this.itemsTarget.hidden = false
    this.promptTarget.hidden = true
    this._markSort(this.menuTarget.querySelector("[data-sort-menu]"), this._node.sort)
    this.menuTarget.querySelector("[data-sort-panel]").hidden = true
    this.menuTarget.querySelector('[data-menu-item="sortFolder"]').setAttribute("aria-expanded", "false")
    this.itemTargets.forEach((element) => {
      const visible = MENU_VISIBILITY[element.dataset.menuItem]
      // With several files picked, only "New folder" (wraps them) applies.
      element.hidden = this._node.multi ? element.dataset.menuItem !== "newFolder"
        : this._node.type === "alias" ? !visible?.(this._node) || !element.dataset.menuItem.startsWith("alias")
        : visible ? !visible(this._node) : false
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
    return [...this.menuTarget.querySelectorAll('[role^="menuitem"]')].filter((el) => !el.closest("[hidden]") && !el.disabled)
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
      if (row.matches(".kb-role-header")) return // virtual project group: no menu
      const box = row.getBoundingClientRect()
      this._open(this._paramsFor(row), box.left + 16, box.bottom, row)
      return
    }
    if (event.altKey && !event.ctrlKey && !event.metaKey && (event.key === "ArrowUp" || event.key === "ArrowDown")) {
      event.preventDefault()
      this._moveSibling(row, event.key === "ArrowUp" ? -1 : 1)
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

  // Ctrl/Cmd-click picks files to act on together; a plain click clears the pick.
  toggleMulti(event) {
    const row = event.currentTarget.closest(".kb-file-row")
    if (!row) return
    if (!(event.ctrlKey || event.metaKey)) {
      this._multiRows().forEach((el) => el.classList.remove("is-multi"))
      return
    }
    event.preventDefault()
    event.stopImmediatePropagation()
    row.classList.toggle("is-multi")
  }

  _multiRows() {
    return Array.from(this.element.querySelectorAll(".kb-file-row.is-multi"))
  }

  newProject(event) {
    event.stopPropagation()
    this._create("project")
  }

  // A build plan: goal + checklist of methods to learn, no tests.
  newBuildPlan(event) {
    event.stopPropagation()
    this._create("project", { project_kind: "build" })
  }

  // Marks an existing folder as a project in place; nothing moves.
  convertProject(event) {
    event.stopPropagation()
    this._submitForm(this.projectConvertUrlValue, "post", { src: this._node.src, path: this._node.rel })
  }

  convertBuildPlan(event) {
    event.stopPropagation()
    this._submitForm(this.projectConvertUrlValue, "post", { src: this._node.src, path: this._node.rel, project_kind: "build" })
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

  _create(kind, extra = {}) {
    const node = this._node
    const fields = { src: node.src, dir: this._targetDir(node), kind, ...extra }
    if (node.multi) {
      // Wrap the picked files in a new folder next to them (same source only).
      const rows = this._multiRows().filter((el) => String(el.dataset.kbTreeSrcParam) === String(node.src))
      const parents = new Set(rows.map((el) => String(el.dataset.kbTreeRelParam).split("/").slice(0, -1).join("/")))
      if (parents.size !== 1) return this._alert("Select files from the same folder.")
      fields.dir = [...parents][0]
      fields["move[]"] = rows.map((el) => String(el.dataset.kbTreeRelParam))
    }
    this._submitForm(this.createUrlValue, "post", fields)
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
    const url = embeddedUrl(this.promptInputTarget.value)
    this.formatTarget.hidden = !url
    if (this.hasNoteTarget) this.noteTarget.hidden = !url
    if (this.hasClipTarget) {
      this.clipTarget.hidden = !url
      // Show what the server will lift from the link (t=/start=/end=); typing in the chips overrides it.
      if (url && this.hasClipStartTarget) {
        const [from, to] = clipFromUrl(url)
        this.clipStartTarget.value = from == null ? "" : formatClip(from)
        this.clipEndTarget.value = to == null ? "" : formatClip(to)
      }
    }
    this._keepMenuOnScreen()
  }

  promptSubmit(event) {
    event.preventDefault()
    const name = this.promptInputTarget.value.trim()
    if (!name) return

    const node = this._node
    const fields = { src: node.src, dir: this._targetDir(node), name, kind: "file" }
    if (this.hasFormatTarget && !this.formatTarget.hidden) {
      fields.format = this.formatTarget.querySelector("input:checked")?.value || "auto"
      if (this.hasClipStartTarget) {
        fields.clip_start = this.clipStartTarget.value.trim()
        fields.clip_end = this.clipEndTarget.value.trim()
      }
      if (this.hasNoteInputTarget) {
        fields.note = this.noteInputTarget.value.trim()
        this.noteInputTarget.value = ""
      }
    }
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
      await alertDialog(result.error || "Finder could not open this entry.", {
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
    const confirmed = await confirmDialog(message, {
      title: node.type === "dir" ? "Delete folder?" : "Delete file?",
      confirmLabel: "Delete",
      variant: "danger",
    })
    if (!confirmed) return
    this._submitForm(this.deleteUrlValue, "delete", { src: node.src, path: node.rel })
  }

  dragStart(event) {
    const params = event.params
    this._drag = { type: params.type, rel: String(params.rel), src: params.src }
    event.dataTransfer.effectAllowed = "all" // Alt-drop = alias ("link")
    event.dataTransfer.setData("text/plain", params.rel)
    event.currentTarget.classList.add("is-dragging")
    // Empty role shelves appear as drop targets (next tick, so the drag image is already captured).
    setTimeout(() => { if (this._drag) this.element.classList.add("is-role-dragging") }, 0)
  }

  dragEnd(event) {
    this._drag = null
    event.currentTarget.classList.remove("is-dragging")
    this.element.classList.remove("is-role-dragging")
    this.element.querySelectorAll(".is-drop-target, .is-drop-before, .is-drop-after").forEach((element) => element.classList.remove("is-drop-target", "is-drop-before", "is-drop-after"))
  }

  dragOver(event) {
    const externalFiles = this._hasExternalFiles(event)
    const zone = externalFiles ? "into" : this._zone(event)
    if (externalFiles ? event.params.type === "file" : !this._canDrop(event.params, zone)) return

    event.preventDefault()
    event.dataTransfer.dropEffect = externalFiles ? "copy" : this._aliasDrop(event) ? "link" : "move"
    this._paintZone(event.currentTarget, zone)
  }

  dragLeave(event) {
    this._paintZone(event.currentTarget, null)
  }

  drop(event) {
    const destination = event.params
    const zone = this._hasExternalFiles(event) ? "into" : this._zone(event)
    const siblings = zone === "into" ? [] : this._siblingNames(event.currentTarget)
    this._paintZone(event.currentTarget, null)

    if (this._hasExternalFiles(event)) {
      event.preventDefault()
      this._uploadFiles(event.dataTransfer.files, destination, event.currentTarget)
      return
    }

    if (!this._canDrop(destination, zone)) return
    event.preventDefault()
    const drag = this._drag
    this._drag = null
    if (this._aliasDrop(event, drag)) {
      const holder = zone === "into" ? (destination.type === "root" ? "" : String(destination.rel)) : this._parentRel(String(destination.rel))
      this._submitForm(this.aliasUrlValue, "post", { src: drag.src, path: drag.rel, dest_src: destination.src, dest_dir: holder })
      return
    }
    if (zone === "into") {
      this._submitForm(this.moveUrlValue, "patch", {
        src: drag.src,
        path: drag.rel,
        dest_src: destination.src,
        dest_dir: destination.type === "root" ? "" : destination.rel
      })
      return
    }

    const dir = this._parentRel(String(destination.rel))
    const names = insertNear(siblings, this._base(drag.rel), this._base(String(destination.rel)), zone)
    if (String(drag.src) === String(destination.src) && this._parentRel(drag.rel) === dir) {
      this._submitForm(this.orderUrlValue, "patch", { src: drag.src, dir, names })
    } else {
      this._submitForm(this.moveUrlValue, "patch", { src: drag.src, path: drag.rel, dest_src: destination.src, dest_dir: dir, names })
    }
  }

  // Alt/Option-drag of a file places an alias ("also in") instead of moving it.
  _aliasDrop(event, drag = this._drag) {
    return !!event.altKey && drag?.type === "file"
  }

  // Menu path to the same thing: mark a file, then "Place alias here" on a folder.
  aliasStart(event) {
    event.stopPropagation()
    this._aliasSource = { src: this._node.src, rel: this._node.rel }
    this._hide()
  }

  aliasHere(event) {
    event.stopPropagation()
    const source = this._aliasSource
    const node = this._node
    this._aliasSource = null
    if (!source) return
    this._submitForm(this.aliasUrlValue, "post", {
      src: source.src, path: source.rel, dest_src: node.src, dest_dir: node.type === "root" ? "" : node.rel
    })
  }

  aliasOpen(event) {
    event.stopPropagation()
    const { targetSrc, targetRel } = this._node
    const frame = document.getElementById("kb-content")
    if (frame) frame.src = `/knowledge-base/file?${new URLSearchParams({ src: targetSrc, file: targetRel })}`
    this._hide()
  }

  // Expands the original's folders, scrolls to it and flashes the row.
  aliasReveal(event) {
    event.stopPropagation()
    const { targetSrc, targetRel } = this._node
    this._hide()
    const row = [...this.element.querySelectorAll('.kb-file-row[data-kb-tree-type-param="file"]')]
      .find((el) => String(el.dataset.kbTreeSrcParam) === String(targetSrc) && el.dataset.kbTreeRelParam === targetRel)
    if (!row) return
    for (let parent = this._parentItem(row); parent; parent = this._parentItem(parent)) {
      if (this._collapsed(parent)) this._toggle(parent)
    }
    row.scrollIntoView({ block: "center" })
    this._focusItem(row)
    row.classList.add("is-revealed")
    setTimeout(() => row.classList.remove("is-revealed"), 1800)
  }

  aliasRemove(event) {
    event.stopPropagation()
    this._submitForm(`${this.aliasUrlValue}/${this._node.linkId}`, "delete", {})
  }

  _base(rel) { return rel.split("/").pop() }
  _parentRel(rel) { return rel.split("/").slice(0, -1).join("/") }

  // before/after/into for the pointer over a row; roots only accept "into".
  _zone(event) {
    const type = event.params.type
    if (type === "root") return "into"
    const box = event.currentTarget.getBoundingClientRect()
    return dropZone(event.clientY - box.top, box.height, type === "dir")
  }

  _paintZone(row, zone) {
    row.classList.remove("is-drop-before", "is-drop-after", "is-drop-target")
    if (zone === "into") row.classList.add("is-drop-target")
    else if (zone) row.classList.add(`is-drop-${zone}`)
  }

  // Names of a row's siblings in displayed order (files and folders only).
  _siblingNames(row) {
    const container = row.matches(".kb-dir-header, .kb-folder-header") ? row.parentElement.parentElement : row.parentElement
    return Array.from(container?.children ?? [])
      .map((child) => child.matches(".kb-dir-group") ? child.querySelector(":scope > .kb-dir-header") : child)
      .filter((el) => el?.matches?.(".kb-dir-header:not(.kb-role-header), .kb-file-row"))
      .map((el) => this._base(String(el.dataset.kbTreeRelParam)))
  }

  // Alt+↑/↓: move the focused row one step among its siblings (switches the folder to manual order).
  _moveSibling(row, delta) {
    if (row.matches(".kb-folder-header, .kb-role-header")) return
    const rel = String(row.dataset.kbTreeRelParam)
    const names = shift(this._siblingNames(row), this._base(rel), delta)
    if (!names) return
    this._submitForm(this.orderUrlValue, "patch", { src: row.dataset.kbTreeSrcParam, dir: this._parentRel(rel), names })
  }

  _markSort(menu, sort) {
    const [field, dir] = String(sort ?? "").split("_")
    menu.dataset.sort = sort ?? ""
    menu.querySelectorAll("[data-sort-field]").forEach((el) => {
      const on = !!field && el.dataset.sortField === field
      el.classList.toggle("is-active", on)
      if (el.dataset.sortField) el.setAttribute("aria-checked", String(on))
      const mark = el.querySelector("[data-sort-mark]")
      if (mark) mark.textContent = on ? "✓" : ""
    })
    const flip = menu.querySelector("[data-sort-flip]")
    flip.disabled = !field
    flip.querySelector("[data-sort-dir]").textContent = dir === "desc" ? "↓ Descending" : "↑ Ascending"
  }

  toggleSort(event) {
    event.stopPropagation()
    const panel = this.menuTarget.querySelector("[data-sort-panel]")
    panel.hidden = !panel.hidden
    event.currentTarget.setAttribute("aria-expanded", String(!panel.hidden))
    if (!panel.hidden) this._menuItems().find((el) => panel.contains(el))?.focus()
  }

  // Shared by the header popover (global default) and the context menu (one folder).
  // A field keeps the current direction; the direction row flips it; blank field = back to default.
  sortPick(event) {
    event.stopPropagation()
    const button = event.currentTarget
    const menu = button.closest("[data-sort-menu]")
    const folder = menu.dataset.sortMenu === "folder"
    let [field, dir] = String(menu.dataset.sort ?? "").split("_")
    if ("sortFlip" in button.dataset) dir = dir === "asc" ? "desc" : "asc"
    else field = button.dataset.sortField
    const mode = field ? `${field}_${dir || "asc"}` : ""
    const scope = folder ? { src: this._node.src, path: this._node.type === "root" ? "" : this._node.rel } : {}
    this._submitForm(this.sortUrlValue, "patch", { ...scope, mode })
  }

  // Dropping a project's direct child on a role shelf header re-roles it
  // (Inbox = no role). Only the same project's own children qualify.
  roleOver(event) {
    if (!this._canRole(event.params)) return

    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    event.currentTarget.classList.add("is-drop-target")
  }

  roleDrop(event) {
    const destination = event.params
    event.currentTarget.classList.remove("is-drop-target")
    if (!this._canRole(destination)) return

    event.preventDefault()
    const drag = this._drag
    this._drag = null
    this.element.classList.remove("is-role-dragging")
    this._submitForm(this.projectMaterialsUrlValue, "patch", {
      src: drag.src,
      path: destination.projectRel,
      name: drag.rel.split("/").pop(),
      role: destination.role,
      tree_only: "1"
    })
  }

  _canRole(destination) {
    const drag = this._drag
    if (!drag || String(drag.src) !== String(destination.src)) return false

    const parts = drag.rel.split("/")
    return parts.slice(0, -1).join("/") === destination.projectRel && parts.at(-1) !== "Tests"
  }

  _canDrop(destination, zone = "into") {
    const drag = this._drag
    if (!drag) return false

    const sameSource = String(drag.src) === String(destination.src)
    const destinationRelative = destination.type === "root" ? "" : String(destination.rel)
    if (zone !== "into") {
      // Between siblings: the folder that would hold the drop is the target's parent.
      const holder = this._parentRel(destinationRelative)
      if (!sameSource) return true
      if (destinationRelative === drag.rel) return false
      return !(drag.type === "dir" && (holder === drag.rel || holder.startsWith(`${drag.rel}/`)))
    }
    if (sameSource) {
      if (drag.type === "dir" && (destinationRelative === drag.rel || destinationRelative.startsWith(`${drag.rel}/`))) return false
      if (this._parentRel(drag.rel) === destinationRelative) return false
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
    if (this.hasFormatTarget) {
      this.formatTarget.hidden = true
      this.formatTarget.querySelector('input[value="auto"]').checked = true
    }

    const input = this.promptInputTarget
    input.value = ""
    input.placeholder = "Paste a link to download"
    this._keepMenuOnScreen()
    input.focus()
  }

  // The prompt is wider than the item list the menu was positioned for.
  _keepMenuOnScreen() {
    const menu = this.menuTarget
    const rect = menu.getBoundingClientRect()
    const dx = Math.max(0, rect.right - (window.innerWidth - 8))
    const dy = Math.max(0, rect.bottom - (window.innerHeight - 8))
    menu.style.left = `${parseFloat(menu.style.left) - dx}px`
    menu.style.top = `${parseFloat(menu.style.top) - dy}px`
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
    Object.entries(fields).forEach(([name, value]) => {
      if (Array.isArray(value)) value.forEach((item) => this._appendHidden(form, name.endsWith("[]") ? name : `${name}[]`, item))
      else this._appendHidden(form, name, value)
    })

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
    alertDialog(message, { title: "That didn’t work", confirmLabel: "Got it" })
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
