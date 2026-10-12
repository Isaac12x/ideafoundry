import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="drag"
export default class extends Controller {
  static targets = ["item", "container"];
  static values = {
    url: String,
    listId: Number,
  };

  // Stimulus fires *TargetConnected for targets present at connect, so listeners
  // are bound there only (stable refs below -> addEventListener dedupes).
  initialize() {
    this.handleDragStart = this.handleDragStart.bind(this);
    this.handleDragEnd = this.handleDragEnd.bind(this);
    this.handleDragOver = this.handleDragOver.bind(this);
    this.handleDrop = this.handleDrop.bind(this);
    this.handleDragEnter = this.handleDragEnter.bind(this);
    this.handleDragLeave = this.handleDragLeave.bind(this);
  }

  disconnect() {
    this.itemTargets.forEach((el) => this.itemTargetDisconnected(el));
    this.containerTargets.forEach((el) => this.containerTargetDisconnected(el));
  }

  handleDragStart(event) {
    this.draggedElement = event.target;
    event.target.classList.add("dragging");

    // Store the data we need for the drop
    const ideaId = event.target.dataset.ideaId;
    const currentListId = event.target.dataset.listId;
    const currentBoardId = event.target.dataset.kanbanBoardId;
    const currentPosition = event.target.dataset.position;

    event.dataTransfer.setData(
      "text/plain",
      JSON.stringify({
        ideaId: ideaId,
        currentListId: currentListId,
        currentBoardId: currentBoardId,
        currentPosition: currentPosition,
      })
    );

    event.dataTransfer.effectAllowed = "move";
  }

  handleDragEnd(event) {
    event.target.classList.remove("dragging");
    this.draggedElement = null;

    // Remove all drop zone highlights
    this.containerTargets.forEach((container) => {
      container.classList.remove("drag-over");
    });
  }

  handleDragOver(event) {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
  }

  handleDragEnter(event) {
    event.preventDefault();
    if (event.target.classList.contains("drop-zone")) {
      event.target.classList.add("drag-over");
    }
  }

  handleDragLeave(event) {
    if (event.target.classList.contains("drop-zone")) {
      event.target.classList.remove("drag-over");
    }
  }

  handleDrop(event) {
    event.preventDefault();

    const dropZone = event.target.closest(".drop-zone");
    if (!dropZone) return;

    dropZone.classList.remove("drag-over");

    try {
      const dragData = JSON.parse(event.dataTransfer.getData("text/plain"));
      const newListId = dropZone.dataset.listId;
      const newBoardId = dropZone.dataset.kanbanBoardId;
      const newPosition = this.calculateNewPosition(dropZone, event.clientY);

      if (dragData.currentBoardId && newBoardId && dragData.currentBoardId !== newBoardId) {
        this.showError("Move ideas within the same board.");
        return;
      }

      // Don't do anything if dropped in the same position
      if (
        dragData.currentListId === newListId &&
        Math.abs(dragData.currentPosition - newPosition) <= 1
      ) {
        return;
      }

      this.updatePosition(dragData.ideaId, newListId, newPosition);
    } catch (error) {
      console.error("Error handling drop:", error);
    }
  }

  calculateNewPosition(dropZone, clientY) {
    const items = Array.from(dropZone.querySelectorAll("[data-position]"));

    if (items.length === 0) return 1;

    // Find the item we're dropping above/below
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      const rect = item.getBoundingClientRect();
      const itemMiddle = rect.top + rect.height / 2;

      if (clientY < itemMiddle) {
        return parseInt(item.dataset.position);
      }
    }

    // If we're here, we're dropping at the end
    const lastItem = items[items.length - 1];
    return parseInt(lastItem.dataset.position) + 1;
  }

  async updatePosition(ideaId, newListId, newPosition) {
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        },
        body: JSON.stringify({
          idea_id: ideaId,
          list_id: newListId,
          position: newPosition,
        }),
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      // The response should contain Turbo Stream updates
      const responseText = await response.text();
      if (responseText.trim()) {
        // Let Turbo handle the stream response
        Turbo.renderStreamMessage(responseText);
      }
    } catch (error) {
      console.error("Error updating position:", error);
      // Optionally show user feedback
      this.showError("Failed to update position. Please try again.");
    }
  }

  showError(message) {
    // Simple error display - could be enhanced with a proper notification system
    const errorDiv = document.createElement("div");
    errorDiv.className = "alert alert-error";
    errorDiv.textContent = message;
    document.body.appendChild(errorDiv);

    setTimeout(() => {
      errorDiv.remove();
    }, 3000);
  }

  itemTargetConnected(element) {
    element.draggable = true;
    element.addEventListener("dragstart", this.handleDragStart);
    element.addEventListener("dragend", this.handleDragEnd);
  }

  itemTargetDisconnected(element) {
    element.removeEventListener("dragstart", this.handleDragStart);
    element.removeEventListener("dragend", this.handleDragEnd);
  }

  containerTargetConnected(element) {
    element.addEventListener("dragover", this.handleDragOver);
    element.addEventListener("drop", this.handleDrop);
    element.addEventListener("dragenter", this.handleDragEnter);
    element.addEventListener("dragleave", this.handleDragLeave);
  }

  containerTargetDisconnected(element) {
    element.removeEventListener("dragover", this.handleDragOver);
    element.removeEventListener("drop", this.handleDrop);
    element.removeEventListener("dragenter", this.handleDragEnter);
    element.removeEventListener("dragleave", this.handleDragLeave);
  }
}
