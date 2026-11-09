import { Controller } from "@hotwired/stimulus";

// "Add to list" on a named list: Enter submits the text as a note/link; a match button submits that idea or KB entry instead.
export default class extends Controller {
  static values = { url: String, ideasUrl: String, listId: Number };
  static targets = ["input", "results"];

  disconnect() {
    clearTimeout(this.timer);
  }

  search() {
    clearTimeout(this.timer);
    const q = this.inputTarget.value.trim();
    if (q.length < 2 || /^https?:\/\//i.test(q)) return this.clear();
    this.timer = setTimeout(() => this.load(q), 220);
  }

  async fetchResults(base, q) {
    const url = new URL(base, window.location.origin);
    url.searchParams.set("q", q);
    const resp = await fetch(url, { headers: { Accept: "application/json" } });
    if (!resp.ok) return [];
    return (await resp.json()).results || [];
  }

  async load(q) {
    try {
      const [ideas, kb] = await Promise.all([
        this.fetchResults(this.ideasUrlValue, q).catch(() => []),
        this.fetchResults(this.urlValue, q).catch(() => []),
      ]);
      if (this.inputTarget.value.trim() !== q) return; // stale
      this.render([
        ...ideas.slice(0, 5).map((i) => ({
          name: i.title,
          meta: `idea · ${i.state}`,
          value: `idea:${i.id}`,
          disabled: (i.list_ids || []).includes(this.listIdValue),
        })),
        ...kb.slice(0, 8).map((e) => ({
          name: e.name,
          meta: `${e.type === "dir" ? "folder" : e.type} · ${e.path}`,
          value: `kb:${e.src}:${e.type}:${e.path}`,
        })),
      ]);
    } catch {
      /* picker is optional; Enter still adds the text */
    }
  }

  render(entries) {
    if (!entries.length) return this.clear();
    this.resultsTarget.replaceChildren(...entries.map((entry) => {
      const li = document.createElement("li");
      const button = document.createElement("button");
      button.type = "submit";
      button.name = "pick";
      button.value = entry.value;
      button.disabled = !!entry.disabled;
      button.className = "list-anything__match";
      const name = document.createElement("span");
      name.textContent = entry.name;
      const meta = document.createElement("small");
      meta.textContent = entry.disabled ? `${entry.meta} · already in list` : entry.meta;
      button.append(name, meta);
      li.append(button);
      return li;
    }));
    this.resultsTarget.hidden = false;
  }

  clear() {
    this.resultsTarget.hidden = true;
    this.resultsTarget.replaceChildren();
  }
}
