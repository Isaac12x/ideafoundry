// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";

// ---------------------------------------------------------------------------
// Auto-grow every <textarea> site-wide: size to its content plus a bit more
// (one extra line of breathing room) so fields never need an inner scrollbar.
// ---------------------------------------------------------------------------
function autosize(el) {
  if (!(el instanceof HTMLTextAreaElement)) return;
  const buffer = parseFloat(getComputedStyle(el).lineHeight) || 20; // "a bit more"
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
  el.style.height = `${content + buffer}px`;
}

function autosizeAll(root) {
  const scope = root && root.querySelectorAll ? root : document;
  scope.querySelectorAll("textarea").forEach(autosize);
}

// Grow as the user types.
document.addEventListener("input", (event) => {
  if (event.target instanceof HTMLTextAreaElement) autosize(event.target);
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
