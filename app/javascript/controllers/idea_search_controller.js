import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    searchUrl:      String,
    addUrlTemplate: String,
    listId:         String,
  };

  static targets = ["input", "results", "panel"];

  connect() {
    this._timer = null;
  }

  disconnect() {
    clearTimeout(this._timer);
  }

  toggleSearch(event) {
    event.stopPropagation();
    if (!this.hasPanelTarget) return;
    const open = this.panelTarget.hidden;
    this.panelTarget.hidden = !open;
    if (open) this.inputTarget.focus();
  }

  search() {
    clearTimeout(this._timer);
    const q = this.inputTarget.value.trim();
    if (!q) {
      this.resultsTarget.hidden = true;
      this.resultsTarget.innerHTML = "";
      return;
    }
    this._timer = setTimeout(() => this._fetch(q), 220);
  }

  async _fetch(q) {
    try {
      const url = new URL(this.searchUrlValue, window.location.origin);
      url.searchParams.set("q", q);
      const resp = await fetch(url, { headers: { Accept: "application/json" } });
      if (!resp.ok) return;
      const { results } = await resp.json();
      if (this.inputTarget.value.trim() !== q) return; // stale response
      this._render(results, q);
    } catch {
      /* silently fail */
    }
  }

  _render(results, q) {
    if (!results.length) {
      this.resultsTarget.innerHTML = `<div class="idea-search-empty">No results for <strong>${this._esc(q)}</strong></div>`;
      this.resultsTarget.hidden = false;
      return;
    }

    const listIdNum = Number(this.listIdValue) || this.listIdValue;
    const frag = document.createDocumentFragment();

    results.forEach((idea) => {
      const alreadyAdded = (idea.list_ids || []).map(Number).includes(Number(listIdNum));
      const item = document.createElement("div");
      item.className = "idea-search-result";

      const badges = (idea.matches || [])
        .map((m) => `<span class="isrb isrb--${this._esc(m.field)}">${this._esc(m.field)}</span>`)
        .join("");

      const snippets = (idea.matches || [])
        .map((m) => `<div class="isr-snippet"><span class="isr-field">${this._esc(m.field)}</span><span class="isr-text">${this._esc(m.snippet)}</span></div>`)
        .join("");

      const stateLabel = (idea.state || "").replace(/_/g, " ");
      const score      = idea.score != null ? `<span class="idea-search-score">${Number(idea.score).toFixed(1)}</span>` : "";

      item.innerHTML = `
        <div class="isr-header">
          <span class="isr-title">${this._esc(idea.title)}</span>
          <div class="isr-meta">
            <span class="idea-state ${this._esc(idea.state)}">${this._esc(stateLabel)}</span>
            ${score}
            <div class="isr-badges">${badges}</div>
          </div>
        </div>
        ${snippets ? `<div class="isr-snippets">${snippets}</div>` : ""}
        <div class="isr-actions">
          <button type="button"
                  class="btn btn-sm${alreadyAdded ? "" : " btn-primary"}"
                  data-idea-id="${this._esc(String(idea.id))}"
                  ${alreadyAdded ? "disabled" : ""}>
            ${alreadyAdded ? "Already added" : "Add to list"}
          </button>
          <a href="${this._esc(idea.url)}" class="btn btn-sm" target="_blank" rel="noopener">View</a>
        </div>
      `;

      const addBtn = item.querySelector("[data-idea-id]");
      if (addBtn && !alreadyAdded) {
        addBtn.addEventListener("click", () => this._addToList(idea.id, addBtn));
      }

      frag.appendChild(item);
    });

    this.resultsTarget.replaceChildren(frag);
    this.resultsTarget.hidden = false;
  }

  async _addToList(ideaId, btn) {
    btn.disabled    = true;
    btn.textContent = "Adding…";

    const url = this.addUrlTemplateValue.replace("__IDEA_ID__", encodeURIComponent(ideaId));

    try {
      const resp = await fetch(url, {
        method: "POST",
        headers: {
          "Accept":       "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
        },
        body: JSON.stringify({ list_id: this.listIdValue }),
      });
      const payload = await resp.json();
      if (!resp.ok) throw new Error(payload.error || "Failed");

      btn.textContent = "Added";
      this._showToast(payload.message || "Idea added to list");
    } catch (err) {
      btn.textContent = "Add to list";
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

  _esc(str) {
    return String(str ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }
}
