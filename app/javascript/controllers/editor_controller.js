import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import Document from "@tiptap/extension-document"
import Paragraph from "@tiptap/extension-paragraph"
import Text from "@tiptap/extension-text"
import Bold from "@tiptap/extension-bold"
import Italic from "@tiptap/extension-italic"
import Underline from "@tiptap/extension-underline"
import Strike from "@tiptap/extension-strike"
import Heading from "@tiptap/extension-heading"
import Blockquote from "@tiptap/extension-blockquote"
import Code from "@tiptap/extension-code"
import CodeBlock from "@tiptap/extension-code-block"
import BulletList from "@tiptap/extension-bullet-list"
import OrderedList from "@tiptap/extension-ordered-list"
import ListItem from "@tiptap/extension-list-item"
import Link from "@tiptap/extension-link"
import Image from "@tiptap/extension-image"
import Placeholder from "@tiptap/extension-placeholder"
import History from "@tiptap/extension-history"
import HardBreak from "@tiptap/extension-hard-break"
import Dropcursor from "@tiptap/extension-dropcursor"
import Gapcursor from "@tiptap/extension-gapcursor"
import HorizontalRule from "@tiptap/extension-horizontal-rule"

export default class extends Controller {
  static targets = ["editor", "input", "toolbar"]
  static values = {
    content: { type: String, default: "" },
    uploadUrl: { type: String, default: "/uploads" }
  }

  connect() {
    this._initEditor()
    this._initToolbar()
    this._initDragDrop()
  }

  disconnect() {
    if (this._editor) this._editor.destroy()
  }

  // — Editor init —

  _initEditor() {
    this._editor = new Editor({
      element: this.editorTarget,
      content: this.contentValue || "",
      extensions: [
        Document,
        Paragraph,
        Text,
        Bold,
        Italic,
        Underline,
        Strike,
        Heading.configure({ levels: [1, 2, 3] }),
        Blockquote,
        Code,
        CodeBlock,
        BulletList,
        OrderedList,
        ListItem,
        Link.configure({ openOnClick: false }),
        Image,
        Placeholder.configure({ placeholder: "Describe your idea..." }),
        History,
        HardBreak,
        Dropcursor,
        Gapcursor,
        HorizontalRule,
      ],
      onUpdate: () => this._syncToHidden(),
      onSelectionUpdate: () => this._updateToolbarState(),
    })

    this._syncToHidden()
  }

  _syncToHidden() {
    if (!this._editor || !this.hasInputTarget) return
    this.inputTarget.value = this._editor.getHTML()
  }

  // — Toolbar —

  _initToolbar() {
    if (!this.hasToolbarTarget) return
    this.toolbarTarget.querySelectorAll("[data-cmd]").forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.preventDefault()
        this._execCommand(btn.dataset.cmd, btn.dataset)
      })
    })
  }

  _execCommand(cmd, data) {
    const e = this._editor
    if (!e) return

    const chain = e.chain().focus()
    switch (cmd) {
      case "bold":           chain.toggleBold().run(); break
      case "italic":         chain.toggleItalic().run(); break
      case "underline":      chain.toggleUnderline().run(); break
      case "strike":         chain.toggleStrike().run(); break
      case "heading":        chain.toggleHeading({ level: parseInt(data.level) }).run(); break
      case "bulletList":     chain.toggleBulletList().run(); break
      case "orderedList":    chain.toggleOrderedList().run(); break
      case "blockquote":     chain.toggleBlockquote().run(); break
      case "code":           chain.toggleCode().run(); break
      case "codeBlock":      chain.toggleCodeBlock().run(); break
      case "horizontalRule": chain.setHorizontalRule().run(); break
      case "undo":           chain.undo().run(); break
      case "redo":           chain.redo().run(); break
      case "link":           this._insertLink(); break
      case "image":          this._pickImage(); break
    }
    this._updateToolbarState()
  }

  _updateToolbarState() {
    if (!this._editor || !this.hasToolbarTarget) return
    this.toolbarTarget.querySelectorAll("[data-cmd]").forEach(btn => {
      const cmd = btn.dataset.cmd
      let active = false
      switch (cmd) {
        case "bold":       active = this._editor.isActive("bold"); break
        case "italic":     active = this._editor.isActive("italic"); break
        case "underline":  active = this._editor.isActive("underline"); break
        case "strike":     active = this._editor.isActive("strike"); break
        case "heading":    active = this._editor.isActive("heading", { level: parseInt(btn.dataset.level) }); break
        case "bulletList": active = this._editor.isActive("bulletList"); break
        case "orderedList":active = this._editor.isActive("orderedList"); break
        case "blockquote": active = this._editor.isActive("blockquote"); break
        case "code":       active = this._editor.isActive("code"); break
        case "codeBlock":  active = this._editor.isActive("codeBlock"); break
        case "link":       active = this._editor.isActive("link"); break
      }
      btn.classList.toggle("active", active)
    })
  }

  _insertLink() {
    const prev = this._editor.getAttributes("link").href || ""
    const url = prompt("URL:", prev)
    if (url === null) return
    if (url === "") {
      this._editor.chain().focus().extendMarkRange("link").unsetLink().run()
    } else {
      this._editor.chain().focus().extendMarkRange("link").setLink({ href: url }).run()
    }
  }

  _pickImage() {
    const input = document.createElement("input")
    input.type = "file"
    input.accept = "image/*"
    input.onchange = () => {
      if (input.files.length) this._uploadAndInsertImage(input.files[0])
    }
    input.click()
  }

  async _uploadAndInsertImage(file) {
    const form = new FormData()
    form.append("file", file)
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const res = await fetch(this.uploadUrlValue, {
      method: "POST",
      headers: csrfToken ? { "X-CSRF-Token": csrfToken } : {},
      body: form,
    })
    if (!res.ok) return
    const { url } = await res.json()
    this._editor.chain().focus().setImage({ src: url }).run()
  }

  // — Drag/drop images —

  _initDragDrop() {
    this.editorTarget.addEventListener("drop", async (e) => {
      const files = [...(e.dataTransfer?.files || [])]
      const images = files.filter(f => f.type.startsWith("image/"))
      if (!images.length) return
      e.preventDefault()
      for (const img of images) {
        await this._uploadAndInsertImage(img)
      }
    })
  }
}
