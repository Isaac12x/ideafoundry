import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="idea-context-menu"
export default class extends Controller {
  static values = {
    addUrlTemplate: String,
    kanbanBoards: Array,
    namedLists: Array,
  };

  connect() {
    this.closeOnClick = this.closeOnClick.bind(this);
    this.closeOnKeydown = this.closeOnKeydown.bind(this);

    document.addEventListener("click", this.closeOnClick);
    document.addEventListener("keydown", this.closeOnKeydown);
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnClick);
    document.removeEventListener("keydown", this.closeOnKeydown);
    this.menu?.remove();
  }

  open(event) {
    const card = event.currentTarget.closest("[data-idea-id]");
    if (!card) return;

    event.preventDefault();
    event.stopPropagation();

    this.currentCard = card;
    this.currentListIds = this.listIdsFor(card);
    this.ensureMenu();
    this.renderMenu(card);
    this.positionMenu(event.clientX, event.clientY);
  }

  closeOnClick(event) {
    if (this.menu?.contains(event.target)) return;

    this.close();
  }

  closeOnKeydown(event) {
    if (event.key === "Escape") this.close();
  }

  close() {
    if (!this.menu) return;

    this.menu.hidden = true;
    this.currentCard = null;
    this.currentListIds = null;
  }

  ensureMenu() {
    if (this.menu) return;

    this.menu = document.createElement("div");
    this.menu.className = "idea-context-menu";
    this.menu.hidden = true;
    this.menu.setAttribute("role", "menu");
    document.body.appendChild(this.menu);
  }

  renderMenu(card) {
    const title = card.dataset.ideaTitle || "Idea";
    const fragment = document.createDocumentFragment();

    const header = document.createElement("div");
    header.className = "idea-context-menu__header";
    header.textContent = title;
    fragment.appendChild(header);

    fragment.appendChild(this.sectionTitle("Kanban boards"));
    const kanbanBoards = this.hasKanbanBoardsValue ? this.kanbanBoardsValue : [];
    if (kanbanBoards.length === 0) {
      fragment.appendChild(this.emptyItem("No kanban boards"));
    } else {
      kanbanBoards.forEach((board) => {
        if (!board.lists || board.lists.length === 0) {
          fragment.appendChild(this.emptyItem(`${board.name}: no columns`));
          return;
        }

        board.lists.forEach((list) => {
          const current = this.currentListIds.has(String(list.id));
          fragment.appendChild(
            this.menuItem(`${board.name} / ${list.name}`, {
              detail: current ? "Current" : "Add to board",
              disabled: current,
              onSelect: () => this.addToList(list.id),
            })
          );
        });
      });
    }

    fragment.appendChild(this.sectionTitle("Named lists"));
    const namedLists = this.hasNamedListsValue ? this.namedListsValue : [];
    if (namedLists.length === 0) {
      fragment.appendChild(this.emptyItem("No named lists"));
    } else {
      namedLists.forEach((list) => {
        const added = this.currentListIds.has(String(list.id));
        fragment.appendChild(
          this.menuItem(list.name, {
            detail: added ? "Added" : "Add to list",
            disabled: added,
            onSelect: () => this.addToList(list.id),
          })
        );
      });
    }

    this.menu.replaceChildren(fragment);
  }

  sectionTitle(label) {
    const element = document.createElement("div");
    element.className = "idea-context-menu__section";
    element.textContent = label;
    return element;
  }

  emptyItem(label) {
    const element = document.createElement("div");
    element.className = "idea-context-menu__empty";
    element.textContent = label;
    return element;
  }

  menuItem(label, { detail, disabled, onSelect }) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "idea-context-menu__item";
    button.disabled = disabled;
    button.dataset.disabled = disabled ? "true" : "false";
    button.setAttribute("role", "menuitem");

    const labelElement = document.createElement("span");
    labelElement.textContent = label;
    button.appendChild(labelElement);

    if (detail) {
      const detailElement = document.createElement("small");
      detailElement.textContent = detail;
      button.appendChild(detailElement);
    }

    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      if (!button.disabled) onSelect();
    });

    return button;
  }

  positionMenu(clientX, clientY) {
    this.menu.hidden = false;
    this.menu.style.left = "0px";
    this.menu.style.top = "0px";

    const margin = 12;
    const rect = this.menu.getBoundingClientRect();
    const left = Math.min(clientX, window.innerWidth - rect.width - margin);
    const top = Math.min(clientY, window.innerHeight - rect.height - margin);

    this.menu.style.left = `${Math.max(margin, left)}px`;
    this.menu.style.top = `${Math.max(margin, top)}px`;
  }

  async addToList(listId) {
    if (!this.currentCard || !this.hasAddUrlTemplateValue) return;

    const url = this.addUrlTemplateValue.replace(
      "__IDEA_ID__",
      encodeURIComponent(this.currentCard.dataset.ideaId)
    );

    this.setLoading(true);

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
        },
        body: JSON.stringify({ list_id: listId }),
      });

      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "Failed to update idea.");

      this.applyMembership(payload);
      this.showMessage(payload.message || "Idea updated.");
      this.close();
    } catch (error) {
      this.showMessage(error.message, "error");
    } finally {
      this.setLoading(false);
    }
  }

  applyMembership(payload) {
    const listIds = this.listIdsFor(this.currentCard);
    if (payload.removed_list_id) listIds.delete(String(payload.removed_list_id));
    listIds.add(String(payload.list.id));
    this.currentCard.dataset.ideaListIds = Array.from(listIds).join(",");

    if (payload.list.kind === "kanban") {
      this.syncVisibleKanbanCard(payload);
    }
  }

  syncVisibleKanbanCard(payload) {
    if (!payload.removed_list_id) return;

    const sourceZone = this.currentCard.closest(".drop-zone");
    if (sourceZone?.dataset.kanbanBoardId !== String(payload.list.kanban_board_id)) return;

    const targetZone = document.getElementById(`list_${payload.list.id}_ideas`);
    if (!targetZone) return;

    targetZone.querySelector(".empty-drop-zone")?.remove();
    targetZone.appendChild(this.currentCard);
    this.currentCard.dataset.listId = String(payload.list.id);
    this.currentCard.dataset.kanbanBoardId = String(payload.list.kanban_board_id);
    this.currentCard.dataset.position = String(payload.membership.position);

    if (sourceZone.querySelectorAll(".idea-card").length === 0) {
      const empty = document.createElement("div");
      empty.className = "empty-drop-zone";
      empty.innerHTML = "<p>No ideas in this list yet.</p>";
      sourceZone.appendChild(empty);
    }
  }

  setLoading(isLoading) {
    this.menu?.querySelectorAll("button").forEach((button) => {
      button.disabled = isLoading || button.dataset.disabled === "true";
    });
  }

  listIdsFor(card) {
    return new Set(
      (card?.dataset.ideaListIds || "")
        .split(",")
        .map((id) => id.trim())
        .filter(Boolean)
    );
  }

  showMessage(message, kind = "success") {
    this.toast?.remove();

    this.toast = document.createElement("div");
    this.toast.className = `alert ${kind === "error" ? "alert-error" : "alert-success"} idea-context-menu-toast`;
    this.toast.textContent = message;
    document.body.appendChild(this.toast);

    setTimeout(() => {
      this.toast?.remove();
      this.toast = null;
    }, 2500);
  }
}
