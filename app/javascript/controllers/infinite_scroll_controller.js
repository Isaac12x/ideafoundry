import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sentinel"]

  // Built in initialize(), not connect(): for sentinels already in the DOM,
  // Stimulus fires sentinelTargetConnected() before connect(), so the observer
  // must exist first. (root cause of "Cannot read properties of undefined (observe)")
  initialize() {
    this.observer = new IntersectionObserver(this.#onIntersect.bind(this), {
      rootMargin: "400px"
    })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  sentinelTargetConnected(sentinel) {
    if (sentinel.dataset.url) this.observer.observe(sentinel)
  }

  sentinelTargetDisconnected(sentinel) {
    this.observer.unobserve(sentinel)
  }

  async #onIntersect(entries) {
    const entry = entries.find(e => e.isIntersecting)
    if (!entry) return

    const sentinel = entry.target
    const url = sentinel.dataset.url
    if (!url) return

    this.observer.unobserve(sentinel)
    sentinel.classList.add("is-loading")

    try {
      const resp = await fetch(url, {
        headers: { Accept: "text/vnd.turbo-stream.html" },
        credentials: "same-origin"
      })
      if (!resp.ok) throw new Error(resp.status)
      Turbo.renderStreamMessage(await resp.text())
    } catch {
      sentinel.classList.remove("is-loading")
      if (sentinel.dataset.url) this.observer.observe(sentinel)
    }
  }
}
