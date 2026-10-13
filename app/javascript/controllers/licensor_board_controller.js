import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="licensor-board"
// Drag licensor cards between stage columns; PATCHes the card and re-renders
// the board from the returned Turbo Stream.
export default class extends Controller {
  static targets = ["card", "column"];

  connect() {
    this.cardTargets.forEach((c) => this.wireCard(c));
    this.columnTargets.forEach((col) => this.wireColumn(col));
  }

  cardTargetConnected(card) {
    this.wireCard(card);
  }

  columnTargetConnected(column) {
    this.wireColumn(column);
  }

  wireCard(card) {
    card.addEventListener("dragstart", (e) => {
      this.dragging = card;
      card.classList.add("is-dragging");
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", card.dataset.id);
    });
    card.addEventListener("dragend", () => {
      card.classList.remove("is-dragging");
      this.dragging = null;
      this.columnTargets.forEach((c) => c.classList.remove("is-over"));
    });
  }

  wireColumn(column) {
    column.addEventListener("dragover", (e) => {
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      column.classList.add("is-over");
    });
    column.addEventListener("dragleave", () => column.classList.remove("is-over"));
    column.addEventListener("drop", (e) => {
      e.preventDefault();
      column.classList.remove("is-over");
      if (!this.dragging) return;
      const id = this.dragging.dataset.id;
      const stage = column.dataset.stage;
      const position = this.positionFor(column, e.clientY);
      this.move(id, stage, position);
    });
  }

  positionFor(column, clientY) {
    const cards = Array.from(column.querySelectorAll(".crm-card")).filter(
      (c) => c !== this.dragging
    );
    for (let i = 0; i < cards.length; i++) {
      const rect = cards[i].getBoundingClientRect();
      if (clientY < rect.top + rect.height / 2) return i + 1;
    }
    return cards.length + 1;
  }

  async move(id, stage, position) {
    try {
      const res = await fetch(`/licensors/${id}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        },
        body: JSON.stringify({ context: "board", licensor: { stage, position } }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const text = await res.text();
      if (text.trim()) Turbo.renderStreamMessage(text);
    } catch (err) {
      console.error("Failed to move licensor:", err);
    }
  }
}
