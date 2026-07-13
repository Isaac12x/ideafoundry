import { Controller } from "@hotwired/stimulus";

// Collapse state persists in localStorage, keyed by "src:rel", so folders stay
// how the user left them across reloads and tree re-renders. Only collapsed
// folders are stored; anything absent (new folders, wiped storage) is expanded.
const STORE_KEY = "kb-tree-collapsed";

function collapsedSet() {
  try {
    return new Set(JSON.parse(localStorage.getItem(STORE_KEY)) || []);
  } catch {
    return new Set();
  }
}

function persist(set) {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify([...set]));
  } catch {
    // ponytail: storage disabled/full — collapse just won't survive reload.
  }
}

export default class extends Controller {
  static targets = ["files"];

  connect() {
    const key = this.#keyFor(this.element);
    if (key && collapsedSet().has(key)) this.element.classList.add("is-collapsed");
  }

  toggle() {
    const collapsed = this.element.classList.toggle("is-collapsed");
    const set = collapsedSet();
    const key = this.#keyFor(this.element);
    if (!key) return;

    collapsed ? set.add(key) : set.delete(key);
    persist(set);
  }

  collapseAll(event) {
    event?.stopPropagation();
    this.#setAll(true);
  }

  expandAll(event) {
    event?.stopPropagation();
    this.#setAll(false);
  }

  #setAll(collapsed) {
    const set = collapsedSet();
    this.element.querySelectorAll(".kb-dir-group").forEach((group) => {
      const key = this.#keyFor(group);
      if (!key) return;

      group.classList.toggle("is-collapsed", collapsed);
      collapsed ? set.add(key) : set.delete(key);
    });
    persist(set);
  }

  #keyFor(group) {
    const header = group.querySelector(":scope > .kb-dir-header");
    const src = header?.dataset.kbTreeSrcParam;
    const rel = header?.dataset.kbTreeRelParam;
    return src != null && rel ? `${src}:${rel}` : null;
  }
}
