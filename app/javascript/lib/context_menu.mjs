// Per-screen right-click menu: items are collected from the page's EXISTING buttons/links (clicking them reuses
// their forms, Turbo methods and data-turbo-confirm -> AppDialog), never from new endpoints.
// Pure over a DOM-like API (closest/matches/querySelector(All)/getAttribute) so it runs under node:test.

const ACTION = "a[href], button, input[type=submit]"
const clean = (s) => (s || "").replace(/\s+/g, " ").trim()

// Text, unless it is a lone glyph (+, x): then aria-label/title name it.
export const labelOf = (el) => {
  const text = clean(el.matches("input") ? el.value : el.textContent)
  return text.length > 1 ? text : clean(el.getAttribute("aria-label")) || clean(el.getAttribute("title")) || text
}

// Status <select>: one item per other option, changed through the select so the form's own handler submits it.
const statusItems = (root) => {
  const select = root.matches("select") ? root : root.querySelector("select")
  return select ? [...select.options].filter((o) => o.value !== select.value).map((o) => ({
    label: `Mark ${o.textContent.trim().toLowerCase()}`,
    run: () => { select.value = o.value; select.dispatchEvent(new Event("change", { bubbles: true })) }
  })) : []
}

// Rows/cards: right-clicking inside one lists that row's own buttons. Innermost first; each is a group.
export const AREAS = [
  { sel: ".topology-node-content", title: ".topology-node-name", actions: ".topology-node-actions a",
    extra: (el) => el.dataset?.topologyId && [{ label: "Add child topology", href: `/topologies/new?parent_id=${el.dataset.topologyId}` }] },
  { sel: ".named-list-card, .list-container", title: "h3", actions: ".list-actions a, .list-actions button" },
  { sel: ".kanban-board", title: "h3", actions: ".kanban-board-header-actions a, .kanban-board-header-actions button" },
  { sel: ".backlog-item", title: ".backlog-title", actions: ".backlog-actions button" },
  { sel: ".template-card", title: ".template-card__name", actions: ".template-card__actions a" },
  { sel: ".kb-maxim-card, .kb-fact-card", title: "p", actions: "button" },
  { sel: ".mood-tile", titleText: "Image", actions: ".mood-tile__del" },
  { sel: ".licensor-row", title: ".licensor-row__company", actions: ".licensor-row__manage summary, .licensor-row__manage .btn-danger", hidden: true },
  { sel: ".kbp-mat", title: ".kbp-mat-name", actions: ".kbp-triage-btn, .kbp-icon-btn, .kbp-link" },
  // KB project page: per-section actions (+ New test, Write the conclusion, Save ...), collapse toggle.
  { sel: ".kbp-sec", title: ".kbp-sec-name", actions: ".kbp-sec-body summary, .kbp-sec-body .kbp-actions .kbp-btn",
    extra: (el) => { const t = el.querySelector(".kbp-sec-toggle"); return t ? [{ label: t.getAttribute("aria-expanded") === "true" ? "Collapse section" : "Expand section", el: t }] : [] } },
  // Notes bar tabs.
  { sel: ".kb-notes-tab-group", title: ".kb-notes-tab", actions: ".kb-notes-tab-close", label: () => "Close note tab" },
  { sel: ".kb-notes-bar", title: ".kb-notes-tab", actions: ".kb-notes-add-btn", titleText: "Notes" }
]

// Screen-level actions, from whatever of these the current page actually has. Group title = the page heading.
export const PAGE_SCOPES = [
  { sel: ".page-header .header-actions" },
  { sel: ".idea-actions-menu__dropdown", actions: "a.idea-actions-menu__item, form button.idea-actions-menu__item", hidden: true },
  { sel: ".crm-viewtoggle" },
  { sel: ".topology-graph-controls", actions: "button" },
  { sel: ".named-lists-footer" },
  { sel: ".form-actions" },
  // KB file view: viewer bars (download, extracted knowledge, OCR, shots), file meta (note, description, source, references, edit), transcript.
  { sel: ".kb-media-action-bar, .kb-image-text-bar, .kb-video-shot-bar, .kb-viewer-bar", actions: "a[href], button" },
  { sel: ".kb-file-meta", actions: "a[href], .kb-note__toggle, .kb-meta-toggle, .kb-media-copy-btn, form button" },
  { sel: ".kb-transcript", actions: "button.btn" },
  // KB project page header: private/lock, copy/print, stages, edit stages, status.
  { sel: ".kbp-head .kbp-tools", actions: "button" },
  { sel: ".kbp-head", actions: ".kbp-private", label: (el) =>
      el.getAttribute("title")?.startsWith("Encrypt") ? "Lock with password" : el.getAttribute("data-next") === "0" ? "Make not private" : "Make private" },
  { sel: ".kbp-stages", actions: ".kbp-stage-btn", label: (el) => `Move to stage ${el.querySelector(".kbp-stage-name")?.textContent.trim()}` },
  { sel: ".kbp-rail-edit", actions: "summary", label: () => "Edit stages", hidden: true },
  { sel: ".kbp-status", items: statusItems },
  // Tab switches (idea show sections etc.).
  { sel: "main", actions: ".tab-button", label: (el) => `Go to ${labelOf(el)} tab` },
  { sel: ".submission-status-tabs", actions: "a" },
  { sel: ".kb-sidebar", actions: ".kb-add-folder-link" },
  { sel: ".mood-board__tools", actions: "button" },
  // Settings pages: the page's own save/action buttons.
  { sel: "main", actions: "form [type=submit], a.btn", limit: 8, path: /^\/settings\/./ },
  { sel: ".drawing-canvas-toolbar, .submission-header-top, .version-actions, .compare-actions" },
  { sel: "main form", actions: "[type=submit]", limit: 1, path: /\/(new|edit)\/?$/ }
]

// Sibling navigation for screens whose DOM carries none.
const SETTINGS = [["Features", "features"], ["Display", "display"], ["Keyboard shortcuts", "shortcuts"], ["Topologies", "topologies"], ["Lists", "lists"],
  ["Themes", "themes"], ["Scoring", "scoring"], ["Templates", "templates"], ["AI agents", "ai-agents"], ["Idea work tokens", "idea-work-tokens"],
  ["Email", "email"], ["Security", "security"], ["Knowledge base", "kb"], ["Export & backup", "exports"], ["API keys", "api_keys"], ["Capture", "capture"], ["Activity", "activity"]]
export const NAV = [
  { path: /^\/settings\/./, title: "Settings sections",
    items: (path) => [{ label: "All settings", href: "/settings" }, ...SETTINGS.filter(([, slug]) => !path.startsWith(`/settings/${slug}`)).map(([label, slug]) => ({ label, href: `/settings/${slug}` }))] },
  { path: /^\/planning\/\d+/, title: "Planning", items: () => [{ label: "All lists", href: "/planning" }] },
  { path: /^\/knowledge-base\/(edit|archive|book)/, title: "Knowledge base", items: () => [{ label: "Knowledge base home", href: "/knowledge-base" }] }
]

// Fields with no button of their own on the page.
export const FOCUS_ITEMS = [
  { path: /^\/backlog\/?$/, label: "Add backlog item", sel: ".backlog-form textarea, .backlog-form input[type=text]" },
  { path: /^\/planning\/?$/, label: "New kanban board", sel: ".kanban-board-form input" }
]

const defaultVisible = (el) => !el.closest("[hidden], .hidden")

function fromElements(els, { seen, visible, hidden, label: nameOf = labelOf }) {
  const items = []
  const labels = new Set()
  for (const el of els) {
    const label = clean(nameOf(el))
    if (!label || seen.has(el) || labels.has(label) || el.disabled || el.getAttribute("aria-current") || el.closest("[data-context-skip]")) continue
    if (!(hidden || visible(el))) continue
    if (el.matches("a") && /^(javascript:|#)/.test(el.getAttribute("href") || "")) continue
    seen.add(el)
    labels.add(label)
    items.push({ label, el, danger: el.matches(".btn-danger, [class*='--danger']") || !!el.closest("[data-turbo-confirm]") })
  }
  return items
}

export function collect(target, { path = "/", doc, visible = defaultVisible, palette = false } = {}) {
  const groups = []
  const seen = new Set()
  const add = (title, items) => items.length && groups.push({ title, items })

  for (const area of AREAS) {
    const row = target.closest?.(area.sel)
    if (!row) continue
    const items = fromElements([...row.querySelectorAll(area.actions)], { seen, visible, hidden: area.hidden, label: area.label })
    items.push(...(area.extra?.(row) || []))
    add(area.titleText || clean(row.querySelector(area.title)?.textContent) || "This item", items)
  }

  const link = target.closest?.("a[href]")
  if (link && !seen.has(link) && !/^(javascript:|#)/.test(link.getAttribute("href"))) {
    // A Turbo-method, confirmed or download link is an action, not a page: opening it in a tab would be a bare GET.
    const plain = !["data-turbo-method", "data-turbo-confirm", "download", "data-method"].some((a) => link.getAttribute(a) != null)
    add("Link", [{ label: "Open", el: link }, ...(plain ? [{ label: "Open in new tab", href: link.getAttribute("href"), newTab: true }] : [])])
  }

  const page = []
  for (const scope of PAGE_SCOPES) {
    if (scope.path && !scope.path.test(path)) continue
    for (const root of doc.querySelectorAll(scope.sel)) {
      if (!scope.hidden && !visible(root)) continue
      const els = scope.items ? [] : [...root.querySelectorAll(scope.actions || ACTION)]
      page.push(...fromElements(scope.limit ? els.slice(0, scope.limit) : els, { seen, visible, hidden: scope.hidden, label: scope.label }))
      if (scope.items) page.push(...scope.items(root))
    }
  }
  for (const f of FOCUS_ITEMS) {
    const field = f.path.test(path) && doc.querySelector(f.sel)
    if (field && visible(field)) page.push({ label: f.label, focusEl: field })
  }
  add(clean(doc.querySelector("main h1, main h2")?.textContent) || "This page", page)

  for (const n of NAV) if (n.path.test(path)) add(n.title, n.items(path))
  const app = []
  if (palette) app.push({ label: "Search and jump to...", action: "search" })
  app.push({ label: "Back", action: "back" }, { label: "Reload", action: "reload" })
  add("App", app)
  return groups
}
