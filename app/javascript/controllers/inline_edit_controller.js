import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async #get(url) {
    try {
      return await fetch(url, {
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        }
      })
    } catch {
      return null
    }
  }

  async start(event) {
    event.preventDefault()
    const id = event.currentTarget.dataset.buildItemId
    const response = await this.#get(`/backlog/${id}/edit`)
    if (!response?.ok) return

    const html = await response.text()
    Turbo.renderStreamMessage(html)

    requestAnimationFrame(() => {
      const item = document.getElementById(`build_item_${id}`)
      const input = item?.querySelector("input[name='build_item[title]']")
      item?.scrollIntoView({ block: "nearest" })
      input?.focus({ preventScroll: true })
    })
  }

  async cancel(event) {
    event.preventDefault()
    const id = event.currentTarget.dataset.buildItemId || event.currentTarget.closest(".backlog-item")?.dataset.itemId
    if (!id) return

    const response = await this.#get(`/backlog/${id}/cancel_edit`)
    if (!response?.ok) return

    const html = await response.text()
    Turbo.renderStreamMessage(html)

    requestAnimationFrame(() => {
      document.getElementById(`build_item_${id}`)?.scrollIntoView({ block: "nearest" })
    })
  }
}
