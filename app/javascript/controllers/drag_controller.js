import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="drag"
export default class extends Controller {
  static targets = ["item", "container"];
  static values = {
    url: String,
    listId: Number,
  };

  connect() {
    this.setupDragAndDrop();
  }

  setupDragAndDrop() {
    // Make all items draggable
    this.itemTargets.forEach((item) => {
      item.draggable = true;
      item.addEventListener("dragstart", this.handleDragStart.bind(this));
      item.addEventListener("dragend", this.handleDragEnd.bind(this));
    });

    // Setup drop zones
    this.containerTargets.forEach((container) => {
      container.addEventListener("dragover", this.handleDragOver.bind(this));
      container.addEventListener("drop", this.handleDrop.bind(this));
      container.addEventListener("dragenter", this.handleDragEnter.bind(this));
      container.addEventListener("dragleave", this.handleDragLeave.bind(this));
    });
  }

  handleDragStart(event) {
    this.draggedElement = event.target;
    event.target.classList.add("dragging");

    // Store the data we need for the drop
    const ideaId = event.target.dataset.ideaId;
    const currentListId = event.target.dataset.listId;
    const currentPosition = event.target.dataset.position;

    event.dataTransfer.setData(
      "text/plain",
      JSON.stringify({
        ideaId: ideaId,
        currentListId: currentListId,
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
      const newPosition = this.calculateNewPosition(dropZone, event.clientY);

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

  // Called when new items are added dynamically
  itemTargetConnected(element) {
    element.draggable = true;
    element.addEventListener("dragstart", this.handleDragStart.bind(this));
    element.addEventListener("dragend", this.handleDragEnd.bind(this));
  }

  // Called when new containers are added dynamically
  containerTargetConnected(element) {
    element.addEventListener("dragover", this.handleDragOver.bind(this));
    element.addEventListener("drop", this.handleDrop.bind(this));
    element.addEventListener("dragenter", this.handleDragEnter.bind(this));
    element.addEventListener("dragleave", this.handleDragLeave.bind(this));
  }
}
