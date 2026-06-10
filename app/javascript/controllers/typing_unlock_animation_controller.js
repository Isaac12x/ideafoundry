import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas"]

  static values = {
    url: String,
    result: String
  }

  async connect() {
    if (!this.hasCanvasTarget || !this.hasUrlValue) return

    try {
      const { TypingUnlockAnimation } = await import(/* webpackIgnore: true */ this.urlValue)

      this.animation = new TypingUnlockAnimation(this.canvasTarget, {
        result: this.resultValue || "matched",
        onComplete: () => this.dispatch("complete", { bubbles: true })
      })
    } catch (error) {
      console.error("Unable to load typing unlock animation", error)
      this.element.classList.add("typing-lock-animation--fallback")
      this.completeTimer = setTimeout(() => {
        this.dispatch("complete", { bubbles: true })
      }, 700)
    }
  }

  disconnect() {
    if (this.completeTimer) clearTimeout(this.completeTimer)
    this.animation?.destroy()
  }
}
