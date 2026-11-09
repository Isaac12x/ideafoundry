// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails";
import "controllers";
import { collect as collectMenu } from "lib/context_menu";
import { nextIndex } from "lib/kb_selection_menu";

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

// ---------------------------------------------------------------------------
// Right-click anywhere: the app's menu for THIS screen (lib/context_menu.mjs: row actions, page actions, link, app) instead of the browser's. Area menus (KB tree, idea cards, KB selection)
// preventDefault first and win. Text fields, editors and selected text keep the native menu (copy/paste/spellcheck).
// ---------------------------------------------------------------------------
let appMenu = null;
let menuOpener = null;
// restore: give focus back to what had it before the menu opened (keyboard close), not after a click elsewhere.
const closeAppMenu = (restore = false) => {
  appMenu?.remove(); appMenu = null;
  if (restore === true && menuOpener?.isConnected) menuOpener.focus({ preventScroll: true });
  menuOpener = null;
};

document.addEventListener("contextmenu", (event) => {
  closeAppMenu();
  // An open modal <dialog> sits in the top layer above the menu: leave the browser's menu there.
  if (event.defaultPrevented || document.querySelector("dialog[open]") || event.target.closest?.("input, textarea, select, [contenteditable], [contenteditable] *, video, audio, canvas")) return;
  if (!window.getSelection()?.isCollapsed) return;

  event.preventDefault();
  const groups = collectMenu(event.target, {
    path: location.pathname,
    doc: document,
    visible: (el) => el.getClientRects().length > 0,
    palette: !!document.querySelector("dialog.command-palette")
  });
  const actions = {
    search: () => document.dispatchEvent(new Event("command-palette:open")),
    back: () => history.back(),
    reload: () => location.reload()
  };
  const run = (item) => {
    if (item.run) item.run();
    else if (item.el) item.el.click();
    else if (item.focusEl) { item.focusEl.scrollIntoView?.({ block: "center" }); item.focusEl.focus(); }
    else if (item.newTab) window.open(item.href, "_blank", "noopener");
    else if (item.href) Turbo.visit(item.href);
    else actions[item.action]?.();
  };
  menuOpener = document.activeElement;
  appMenu = document.createElement("div");
  appMenu.className = "idea-context-menu";
  appMenu.setAttribute("role", "menu");
  appMenu.setAttribute("aria-label", "Page actions");
  groups.forEach(({ title, items }) => {
    const heading = document.createElement("div");
    heading.className = "idea-context-menu__section";
    heading.setAttribute("role", "presentation");
    heading.textContent = title;
    appMenu.appendChild(heading);
    items.forEach((entry) => {
      const item = document.createElement("button");
      item.type = "button";
      item.className = "idea-context-menu__item";
      item.setAttribute("role", "menuitem");
      item.innerHTML = "<span></span>";
      item.firstChild.textContent = entry.label;
      if (entry.danger) item.classList.add("idea-context-menu__item--danger");
      item.addEventListener("click", () => { closeAppMenu(); run(entry); });
      appMenu.appendChild(item);
    });
  });
  document.body.appendChild(appMenu);
  const { width, height } = appMenu.getBoundingClientRect();
  appMenu.style.left = `${Math.max(8, Math.min(event.clientX, innerWidth - width - 8))}px`;
  appMenu.style.top = `${Math.max(8, Math.min(event.clientY, innerHeight - height - 8))}px`;
  appMenu.querySelector("button").focus({ preventScroll: true });
});

// Arrow keys / Home / End move focus; Tab closes; Enter/Space activate the focused item (native button).
document.addEventListener("keydown", (event) => {
  if (!appMenu || !appMenu.contains(document.activeElement)) return;
  if (event.key === "Tab") return closeAppMenu(true);
  if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
  event.preventDefault();
  const buttons = [...appMenu.querySelectorAll("button")];
  buttons[nextIndex(event.key, buttons.indexOf(document.activeElement), buttons.length)].focus();
}, true);

document.addEventListener("pointerdown", (event) => { if (appMenu && !appMenu.contains(event.target)) closeAppMenu(); }, true);
document.addEventListener("keydown", (event) => {
  if (!appMenu || event.key !== "Escape") return;
  event.stopPropagation(); // don't also close a dialog underneath
  closeAppMenu(true);
}, true);
document.addEventListener("scroll", (event) => { if (appMenu && !appMenu.contains(event.target)) closeAppMenu(); }, true);
document.addEventListener("turbo:before-visit", () => closeAppMenu());
