import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async start(event) {
    event.preventDefault()
    const id = event.currentTarget.dataset.buildItemId
    const response = await fetch(`/backlog/${id}/edit`, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      }
    })
    if (!response.ok) return

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

    const response = await fetch(`/backlog/${id}/cancel_edit`, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      }
    })
    if (!response.ok) return

    const html = await response.text()
    Turbo.renderStreamMessage(html)

    requestAnimationFrame(() => {
      document.getElementById(`build_item_${id}`)?.scrollIntoView({ block: "nearest" })
    })
  }
}
