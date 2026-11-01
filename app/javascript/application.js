// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails";
import "controllers";

// Broadcast by KbTreeSeenJob: drop the "new download" dot on the matching tree rows without re-rendering the tree.
// A folder keeps its dot only while a file inside it is still new.
Turbo.StreamActions.kb_seen = function () {
  this.targetElements.forEach((row) => {
    row.classList.remove("is-new");
    row.querySelectorAll(".kb-new-dot, .kb-new-dot + .sr-only").forEach((dot) => dot.remove());
    for (let group = row.closest(".kb-dir-group"); group; group = group.parentElement?.closest(".kb-dir-group")) {
      if (group.querySelector(".kb-file-row.is-new")) continue;
      group.querySelectorAll(":scope > .kb-dir-header .kb-new-dot--dir, :scope > .kb-dir-header .kb-new-dot--dir + .sr-only").forEach((dot) => dot.remove());
    }
  });
};

// ---------------------------------------------------------------------------
// Auto-grow every <textarea> site-wide: size to its content plus a bit more
// (one extra line of breathing room) so fields never need an inner scrollbar.
// ---------------------------------------------------------------------------
// Editors that own their sizing (full-height file editors, typing-lock input) opt out; so does [data-autosize="off"].
const AUTOSIZE_OFF = '[data-autosize="off"], .kb-editor-textarea, .kb-media-editor__source, .typing-lock-input';

// A textarea measured while hidden (closed <details>, collapsed section, hidden editor) would stay ~1 line tall.
// Re-measure when its width changes, which includes becoming visible.
const widths = new WeakMap();
const resizeObserver = new ResizeObserver((entries) => {
  for (const { target, contentRect } of entries) {
    if (widths.get(target) === contentRect.width) continue;
    widths.set(target, contentRect.width);
    autosize(target);
  }
});

function autosize(el) {
  if (!(el instanceof HTMLTextAreaElement) || el.matches(AUTOSIZE_OFF)) return;
  if (!widths.has(el)) { widths.set(el, -1); resizeObserver.observe(el); }
  if (el.getClientRects().length === 0) return; // hidden: the observer sizes it once shown
  // "a bit more"; single-line fields (data-enter-submit) only need their border, not a spare line.
  const buffer = el.hasAttribute("data-enter-submit") ? el.offsetHeight - el.clientHeight : parseFloat(getComputedStyle(el).lineHeight) || 20;
  el.style.overflowY = "hidden";
  el.style.resize = "none";
  el.style.height = "auto";
  let content = el.scrollHeight;
  // scrollHeight ignores placeholder text, so an empty field collapses and clips
  // a multi-line placeholder. When empty, reserve room for the full placeholder.
  if (el.value === "" && el.placeholder) {
    el.value = el.placeholder;
    content = Math.max(content, el.scrollHeight);
    el.value = "";
    el.style.height = "auto";
  }
  // Honour max-height (long text scrolls inside the field instead of pushing the page forever).
  const max = parseFloat(getComputedStyle(el).maxHeight);
  const wanted = content + buffer;
  el.style.overflowY = max && wanted > max ? "auto" : "hidden";
  el.style.height = `${max ? Math.min(wanted, max) : wanted}px`;
}

function autosizeAll(root) {
  const scope = root && root.querySelectorAll ? root : document;
  scope.querySelectorAll("textarea").forEach(autosize);
}

// Grow as the user types.
document.addEventListener("input", (event) => {
  if (event.target instanceof HTMLTextAreaElement) autosize(event.target);
});

// One-row auto-growing textareas stand in for single-line text inputs: Enter submits (Shift+Enter breaks the line).
document.addEventListener("keydown", (event) => {
  const field = event.target;
  if (event.key !== "Enter" || event.shiftKey || event.isComposing || !field.matches?.("textarea[data-enter-submit]")) return;
  event.preventDefault();
  field.form?.requestSubmit();
});

// Size existing textareas on initial render and Turbo navigations.
document.addEventListener("turbo:load", () => autosizeAll());
document.addEventListener("turbo:render", () => autosizeAll());
document.addEventListener("turbo:frame-load", (event) => autosizeAll(event.target));
document.addEventListener("DOMContentLoaded", () => autosizeAll());

// Size textareas inserted dynamically (Turbo Streams, inline edit forms, etc.).
new MutationObserver((mutations) => {
  for (const mutation of mutations) {
    for (const node of mutation.addedNodes) {
      if (node.nodeType !== Node.ELEMENT_NODE) continue;
      if (node.matches && node.matches("textarea")) autosize(node);
      autosizeAll(node);
    }
  }
}).observe(document.documentElement, { childList: true, subtree: true });
