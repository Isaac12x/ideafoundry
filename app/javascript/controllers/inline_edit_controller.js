import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async start(event) {
    const id = event.currentTarget.dataset.buildItemId
    const response = await fetch(`/backlog/${id}/edit`, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      }
    })
    const html = await response.text()
    Turbo.renderStreamMessage(html)
  }

  cancel() {
    Turbo.visit(window.location.href)
  }
}
