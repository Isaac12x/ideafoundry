import { Controller } from "@hotwired/stimulus"

// Pause/play for animated GIFs (Space or click on the image, or the button). A GIF can't be paused
// natively, so pausing paints the current frame onto a canvas laid over the image. Starts paused when
// the OS asks for reduced motion.
export default class extends Controller {
  static targets = ["image", "toggle"]

  connect() {
    this.toggleTarget.hidden = false
    this.sync()
    if (!matchMedia("(prefers-reduced-motion: reduce)").matches) return
    if (this.imageTarget.complete) this.pause()
    else this.imageTarget.addEventListener("load", () => this.pause(), { once: true })
  }

  disconnect() {
    this.canvas?.remove()
  }

  toggle(event) {
    event.preventDefault()
    if (this.canvas) this.play()
    else this.pause()
  }

  pause() {
    const image = this.imageTarget
    if (this.canvas || !image.naturalWidth) return
    this.canvas = Object.assign(document.createElement("canvas"), { width: image.naturalWidth, height: image.naturalHeight, className: "kb-gif-frame" })
    this.canvas.setAttribute("aria-hidden", "true")
    this.canvas.getContext("2d").drawImage(image, 0, 0)
    image.after(this.canvas)
    this.sync()
  }

  play() {
    this.canvas?.remove()
    this.canvas = null
    this.sync()
  }

  sync() {
    this.toggleTarget.textContent = this.canvas ? "Play" : "Pause"
  }
}
