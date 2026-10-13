import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    addUrl: String,
    kanbanBoards: Array,
    namedLists: Array,
    currentListIds: String,
  };

  static targets = ["button", "dropdown"];

  connect() {
    this._outsideClick = (e) => {
      if (!this.element.contains(e.target)) this.close();
    };
  }

  disconnect() {
    document.removeEventListener("click", this._outsideClick);
  }

  toggle(event) {
    event.stopPropagation();
    if (this.dropdownTarget.hidden) {
      this._build();
      this.dropdownTarget.hidden = false;
      document.addEventListener("click", this._outsideClick);
    } else {
      this.close();
    }
  }

  close() {
    this.dropdownTarget.hidden = true;
    document.removeEventListener("click", this._outsideClick);
  }

  _build() {
    const currentIds = new Set(
      (this.currentListIdsValue || "").split(",").map((s) => s.trim()).filter(Boolean)
    );
    const frag = document.createDocumentFragment();

    const boards = this.hasKanbanBoardsValue ? this.kanbanBoardsValue : [];
    if (boards.length) {
      frag.appendChild(this._section("Kanban boards"));
      boards.forEach((board) => {
        if (!board.lists?.length) {
          frag.appendChild(this._empty(`${board.name}: no columns`));
          return;
        }
        board.lists.forEach((list) => {
          frag.appendChild(
            this._item(`${board.name} / ${list.name}`, list.id, currentIds.has(String(list.id)))
          );
        });
      });
    }

    const named = this.hasNamedListsValue ? this.namedListsValue : [];
    if (named.length) {
      frag.appendChild(this._section("Named lists"));
      named.forEach((list) => {
        frag.appendChild(this._item(list.name, list.id, currentIds.has(String(list.id))));
      });
    }

    if (!boards.length && !named.length) {
      frag.appendChild(this._empty("No lists available"));
    }

    this.dropdownTarget.replaceChildren(frag);
  }

  _section(label) {
    const el = document.createElement("div");
    el.className = "atl-section";
    el.textContent = label;
    return el;
  }

  _empty(label) {
    const el = document.createElement("div");
    el.className = "atl-empty";
    el.textContent = label;
    return el;
  }

  _item(label, listId, inList) {
    const row = document.createElement("div");
    row.className = "atl-item";

    const name = document.createElement("span");
    name.className = "atl-item-name";
    name.textContent = label;

    const btn = document.createElement("button");
    btn.type          = "button";
    btn.className     = inList ? "btn btn-xs" : "btn btn-xs btn-primary";
    btn.textContent   = inList ? "In list" : "Add";
    btn.disabled      = inList;
    btn.dataset.listId = String(listId);
    btn.addEventListener("click", (e) => this._handleAdd(e, btn, listId));

    row.appendChild(name);
    row.appendChild(btn);
    return row;
  }

  async _handleAdd(event, btn, listId) {
    event.stopPropagation();
    btn.disabled    = true;
    btn.textContent = "Adding…";

    try {
      const resp = await fetch(this.addUrlValue, {
        method: "POST",
        headers: {
          "Accept":       "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
        },
        body: JSON.stringify({ list_id: String(listId) }),
      });
      const payload = await resp.json();
      if (!resp.ok) throw new Error(payload.error || "Failed");

      btn.textContent = "Added";
      const ids = new Set((this.currentListIdsValue || "").split(",").filter(Boolean));
      ids.add(String(payload.list.id));
      this.currentListIdsValue = Array.from(ids).join(",");
      this._showToast(payload.message || "Added to list");
      setTimeout(() => this.close(), 700);
    } catch (err) {
      btn.textContent = "Add";
      btn.disabled    = false;
      this._showToast(err.message, "error");
    }
  }

  _showToast(msg, kind = "success") {
    const toast = document.createElement("div");
    toast.className = `alert ${kind === "error" ? "alert-error" : "alert-success"} idea-context-menu-toast`;
    toast.textContent = msg;
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 2500);
  }
}
