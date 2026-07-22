import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import Document from "@tiptap/extension-document"
import Paragraph from "@tiptap/extension-paragraph"
import Text from "@tiptap/extension-text"
import Bold from "@tiptap/extension-bold"
import Italic from "@tiptap/extension-italic"
import Heading from "@tiptap/extension-heading"
import BulletList from "@tiptap/extension-bullet-list"
import OrderedList from "@tiptap/extension-ordered-list"
import ListItem from "@tiptap/extension-list-item"
import History from "@tiptap/extension-history"
import HardBreak from "@tiptap/extension-hard-break"
import Placeholder from "@tiptap/extension-placeholder"

const STORAGE_PREFIX = "kb_note_"
const CUSTOM_TABS_KEY = "kb_notes_custom_tabs"

export default class extends Controller {
  static targets = ["tabList", "panel", "editorEl"]
  static values = {
    fileKey: { type: String, default: "" },
    fileLabel: { type: String, default: "" },
  }

  connect() {
    this._expanded = false
    this._activeKey = "general"
    this._fileKey = this.fileKeyValue || null
    this._fileLabel = this.fileLabelValue || null
    this._customTabs = this._loadCustomTabs()
    this._renderTabs()
    this._initEditor()
    this._watchKbPanel()
  }

  disconnect() {
    this._saveContent()
    if (this._observer) this._observer.disconnect()
    if (this._editor) {
      this._editor.destroy()
      this._editor = null
    }
  }

  trackFile({ params }) {
    const file = params.file
    const src = params.src
    const key = `file_${src}_${encodeURIComponent(file)}`
    const label = file.split("/").pop()

    if (this._fileKey !== key) {
      this._fileKey = key
      this._fileLabel = label
      this._renderTabs()
      if (this._activeKey === key) this._loadContent()
    }
  }

  tabClick(event) {
    event.stopPropagation()
    const key = event.currentTarget.dataset.tabKey

    if (this._expanded && this._activeKey === key) {
      this._collapse()
      return
    }

    if (this._activeKey !== key) {
      this._saveContent()
      this._activeKey = key
      this._loadContent()
    }

    this._expand()
    this._renderTabs()
  }

  barClick(event) {
    if (event.target.closest(".kb-notes-tab, .kb-notes-tab-close, .kb-notes-add-btn")) return
    if (this._expanded) this._collapse()
  }

  async addTab(event) {
    event.stopPropagation()
    const name = await window.AppDialog?.prompt("Create a focused space for notes you want to keep close at hand.", {
      title: "Add note tab",
      inputLabel: "Tab name",
      placeholder: "Research, decisions, questions…",
      confirmLabel: "Add tab",
      required: true,
    })
    if (!name || !name.trim()) return

    const id = `custom_${Date.now()}`
    this._saveContent()
    this._customTabs.push({ id, label: name.trim() })
    this._saveCustomTabs()
    this._activeKey = id
    this._expand()
    this._renderTabs()
    this._loadContent()
  }

  async closeTab(event) {
    event.stopPropagation()
    const key = event.currentTarget.dataset.closeKey
    const tab = this._customTabs.find(t => t.id === key)
    const confirmed = await window.AppDialog?.confirm(
      `Delete “${tab?.label || "this tab"}” and its saved notes? This cannot be undone.`,
      { title: "Delete note tab?", confirmLabel: "Delete tab", variant: "danger" }
    )
    if (!confirmed) return

    this._customTabs = this._customTabs.filter(t => t.id !== key)
    this._saveCustomTabs()
    localStorage.removeItem(`${STORAGE_PREFIX}${key}`)

    if (this._activeKey === key) {
      this._activeKey = "general"
      this._loadContent()
    }
    this._renderTabs()
  }

  // ── Private ────────────────────────────────────────────────────────

  _expand() {
    this._expanded = true
    this.element.classList.add("kb-notes-expanded")
    if (this._editor) {
      requestAnimationFrame(() => this._editor?.commands.focus("end"))
    }
  }

  _collapse() {
    this._saveContent()
    this._expanded = false
    this.element.classList.remove("kb-notes-expanded")
  }

  _renderTabs() {
    if (!this.hasTabListTarget) return
    this.tabListTarget.innerHTML = this._buildTabs().map(({ key, label, fullLabel, closeable }) => {
      const isActive = key === this._activeKey
      const title = this._esc(fullLabel || label)
      const tab = `<button class="kb-notes-tab${isActive ? " is-active" : ""}" data-action="click->kb-notes#tabClick" data-tab-key="${key}" title="${title}">${this._esc(label)}</button>`
      if (!closeable) return tab

      return `<div class="kb-notes-tab-group${isActive ? " is-active" : ""}">${tab}<button class="kb-notes-tab-close" data-action="click->kb-notes#closeTab" data-close-key="${key}" title="Delete tab" aria-label="Delete ${title} note tab">×</button></div>`
    }).join("")
  }

  _buildTabs() {
    const tabs = [{ key: "general", label: "General", closeable: false }]

    if (this._fileKey) {
      tabs.push({
        key: this._fileKey,
        label: this._ellipsis(this._fileLabel || this._fileKey, 22),
        fullLabel: this._fileKey,
        closeable: false,
      })
    }

    this._customTabs.forEach(t => {
      tabs.push({ key: t.id, label: this._ellipsis(t.label, 18), fullLabel: t.label, closeable: true })
    })

    return tabs
  }

  _initEditor() {
    if (!this.hasEditorElTarget) return
    this._editor = new Editor({
      element: this.editorElTarget,
      extensions: [
        Document, Paragraph, Text,
        Bold, Italic,
        Heading.configure({ levels: [1, 2, 3] }),
        BulletList, OrderedList, ListItem,
        History, HardBreak,
        Placeholder.configure({ placeholder: "Start writing…" }),
      ],
      onUpdate: () => this._saveContent(),
    })
    this._loadContent()
  }

  _loadContent() {
    if (!this._editor) return
    const html = localStorage.getItem(`${STORAGE_PREFIX}${this._activeKey}`) || ""
    this._editor.commands.setContent(html || "<p></p>", false)
  }

  _saveContent() {
    if (!this._editor) return
    const html = this._editor.getHTML()
    if (html === "<p></p>" || html === "") {
      localStorage.removeItem(`${STORAGE_PREFIX}${this._activeKey}`)
    } else {
      localStorage.setItem(`${STORAGE_PREFIX}${this._activeKey}`, html)
    }
  }

  _loadCustomTabs() {
    try { return JSON.parse(localStorage.getItem(CUSTOM_TABS_KEY) || "[]") }
    catch { return [] }
  }

  _saveCustomTabs() {
    localStorage.setItem(CUSTOM_TABS_KEY, JSON.stringify(this._customTabs))
  }

  // Collapse notes overlay when KB tab panel is hidden (user switched to facts/maxims)
  _watchKbPanel() {
    const panel = this.element.querySelector('[data-tab-panel="kb"]')
    if (!panel) return
    this._observer = new MutationObserver(() => {
      if (panel.classList.contains("hidden") && this._expanded) {
        this._expanded = false
        this.element.classList.remove("kb-notes-expanded")
      }
    })
    this._observer.observe(panel, { attributes: true, attributeFilter: ["class"] })
  }

  _ellipsis(str, max) {
    return str && str.length > max ? str.slice(0, max - 1) + "…" : (str || "")
  }

  _esc(str) {
    return (str || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }
}
