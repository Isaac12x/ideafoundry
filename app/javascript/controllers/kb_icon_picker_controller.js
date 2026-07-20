import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "form", "src", "path", "entryType", "kind", "emoji", "title", "emojiTab", "imageTab", "emojiPanel", "imagePanel", "image"]
  static values = { updateUrl: String }

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    const params = event.params
    this.srcTarget.value = params.src
    this.pathTarget.value = params.rel ?? ""
    this.entryTypeTarget.value = params.type
    this.titleTarget.textContent = `Personalise ${params.label}`
    this.kindTarget.value = "emoji"
    this.emojiTarget.value = "📁"
    this.imageTarget.value = ""
    this.showEmoji()
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  showEmoji(event) {
    event?.preventDefault()
    this.kindTarget.value = "emoji"
    this.emojiPanelTarget.hidden = false
    this.imagePanelTarget.hidden = true
    this.emojiTabTarget.classList.add("is-active")
    this.imageTabTarget.classList.remove("is-active")
  }

  showImage(event) {
    event?.preventDefault()
    this.kindTarget.value = "image"
    this.emojiPanelTarget.hidden = true
    this.imagePanelTarget.hidden = false
    this.emojiTabTarget.classList.remove("is-active")
    this.imageTabTarget.classList.add("is-active")
  }

  chooseEmoji(event) {
    event.preventDefault()
    this.kindTarget.value = "emoji"
    this.emojiTarget.value = event.currentTarget.dataset.emoji
    this.element.querySelectorAll(".kb-icon-dialog .kb-emoji-choice").forEach((button) => {
      button.classList.toggle("is-selected", button === event.currentTarget)
    })
  }

  imageChanged() {
    if (this.imageTarget.files?.length) this.kindTarget.value = "image"
  }

  useDefault(event) {
    event.preventDefault()
    this.kindTarget.value = "default"
    this.formTarget.requestSubmit()
  }

  submitted(event) {
    if (event.detail.success) this.close()
  }
}
