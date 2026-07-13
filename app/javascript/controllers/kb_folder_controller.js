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
    if (collapsedSet().has(this.#key())) this.element.classList.add("is-collapsed");
  }

  toggle() {
    const collapsed = this.element.classList.toggle("is-collapsed");
    const set = collapsedSet();
    collapsed ? set.add(this.#key()) : set.delete(this.#key());
    persist(set);
  }

  #key() {
    const h = this.element.querySelector(":scope > .kb-dir-header");
    return `${h?.dataset.kbTreeSrcParam}:${h?.dataset.kbTreeRelParam}`;
  }
}
