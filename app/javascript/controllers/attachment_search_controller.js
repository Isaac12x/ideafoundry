import { Controller } from "@hotwired/stimulus";

// Debounced search over an idea's extracted attachment / knowledge text.
// Mirrors idea_search_controller's fetch/render pattern but scoped to a single
// idea's attachments and their OCR/knowledge content.
export default class extends Controller {
  static values = { searchUrl: String };
  static targets = ["input", "results"];

  connect() {
    this._timer = null;
  }

  disconnect() {
    clearTimeout(this._timer);
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
      this.resultsTarget.innerHTML = `<div class="attachment-search-empty">No matches for <strong>${this._esc(q)}</strong></div>`;
      this.resultsTarget.hidden = false;
      return;
    }

    this.resultsTarget.innerHTML = results
      .map(
        (r) => `
        <a class="attachment-search-result" href="${this._esc(r.url)}" target="_blank" rel="noopener">
          <span class="asr-file">${this._esc(r.filename)}</span>
          <span class="asr-snippet">${this._highlight(r.snippet, q)}</span>
        </a>`
      )
      .join("");
    this.resultsTarget.hidden = false;
  }

  _highlight(text, q) {
    const esc = this._esc(text);
    const needle = this._esc(q);
    if (!needle) return esc;
    const re = new RegExp(`(${needle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "ig");
    return esc.replace(re, "<mark>$1</mark>");
  }

  _esc(str) {
    return String(str ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }
}
