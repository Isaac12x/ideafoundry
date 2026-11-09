import test from "node:test"
import assert from "node:assert/strict"
import { collect, labelOf } from "../../app/javascript/lib/context_menu.mjs"

// Tiny DOM stand-in: el(tag, {cls, text, attrs, parent, ...}). Selectors supported: tag, .class, [attr], comma lists, descendant " ".
function el(tag, { cls = "", text = "", attrs = {}, kids = [], dataset = {}, disabled = false } = {}) {
  const node = { tag, cls: cls.split(" ").filter(Boolean), attrs, dataset, disabled, parent: null, kids, _text: text }
  kids.forEach((k) => (k.parent = node))
  Object.assign(node, {
    get textContent() { return node._text + node.kids.map((k) => k.textContent).join("") },
    get value() { return attrs.value || "" },
    getAttribute: (k) => attrs[k] ?? null,
    matches: (sel) => sel.split(",").some((s) => one(node, s.trim())),
    closest(sel) { for (let n = node; n; n = n.parent) if (n.matches(sel)) return n; return null },
    querySelectorAll(sel) {
      const out = []
      const walk = (n) => n.kids.forEach((k) => { if (sel.split(",").some((s) => desc(k, s.trim(), node))) out.push(k); walk(k) })
      walk(node)
      return out
    },
    querySelector(sel) { return node.querySelectorAll(sel)[0] || null }
  })
  return node
}
function one(n, s) {
  const m = s.match(/^([a-z0-9]*)((?:\.[\w-]+)*)(\[[^\]]+\])?$/)
  if (!m) return false
  const [, tag, cls, attr] = m
  if (tag && n.tag !== tag) return false
  if (cls && !cls.split(".").filter(Boolean).every((c) => n.cls.includes(c))) return false
  if (attr) { const k = attr.slice(1, -1).split("=")[0]; if (!(k in n.attrs)) return false }
  return true
}
function desc(n, s, root) {
  const parts = s.split(" ")
  if (!one(n, parts.at(-1))) return false
  let a = n.parent
  for (const p of parts.slice(0, -1).reverse()) { while (a && a !== root.parent && !one(a, p)) a = a.parent; if (!a) return false; a = a.parent }
  return true
}
const link = (text, href = "/x", cls = "btn") => el("a", { cls, text, attrs: { href } })
const doc = (...top) => { const root = el("body", { kids: top }); return root }

test("labelOf prefers text, falls back to aria-label then title", () => {
  assert.equal(labelOf(el("a", { text: "  New \n idea " })), "New idea")
  assert.equal(labelOf(el("a", { attrs: { "aria-label": "Zoom in", title: "t" } })), "Zoom in")
  assert.equal(labelOf(el("button", { attrs: { title: "Pin" } })), "Pin")
})

test("row actions come first, destructive ones flagged, page actions grouped under the heading", () => {
  const del = el("a", { cls: "btn btn-danger", text: "Delete", attrs: { href: "/planning/1", "data-turbo-confirm": "x" } })
  const card = el("div", { cls: "named-list-card", kids: [el("h3", { text: "Shortlist" }), el("div", { cls: "list-actions", kids: [link("Open"), del] })] })
  const header = el("div", { cls: "page-header", kids: [el("h2", { text: "Planning" }), el("div", { cls: "header-actions", kids: [link("New idea", "/ideas/new")] })] })
  const main = el("main", { kids: [header, card] })
  const d = doc(main)
  const groups = collect(card.kids[0], { path: "/planning", doc: d, palette: true })
  assert.deepEqual(groups.map((g) => g.title), ["Shortlist", "Planning", "App"])
  assert.deepEqual(groups[0].items.map((i) => [i.label, i.danger]), [["Open", false], ["Delete", true]])
  assert.deepEqual(groups[1].items.map((i) => i.label), ["New idea"])
  assert.deepEqual(groups[2].items.map((i) => i.label), ["Search and jump to...", "Back", "Reload"])
})

test("page background gets only page + app groups; hidden and disabled actions are dropped", () => {
  const hidden = el("div", { cls: "hidden", kids: [el("div", { cls: "form-actions", kids: [link("Ghost")] })] })
  const actions = el("div", { cls: "header-actions", kids: [link("Real"), el("button", { text: "Off", disabled: true }), el("button", { text: "" })] })
  const d = doc(el("main", { kids: [el("div", { cls: "page-header", kids: [actions] }), hidden] }))
  const groups = collect(d, { path: "/ideas", doc: d })
  assert.deepEqual(groups.map((g) => g.title), ["This page", "App"])
  assert.deepEqual(groups[0].items.map((i) => i.label), ["Real"])
  assert.deepEqual(groups[1].items.map((i) => i.label), ["Back", "Reload"])
})

test("a right-clicked link offers Open / Open in new tab; javascript: and # links are ignored", () => {
  const a = link("Row", "/ideas/3", "crm-card")
  const d = doc(el("main", { kids: [a] }))
  const g = collect(a, { path: "/licensing/crm", doc: d })
  assert.deepEqual(g[0].items.map((i) => i.label), ["Open", "Open in new tab"])
  const dead = link("x", "#", "crm-card")
  assert.equal(collect(dead, { path: "/", doc: doc(el("main", { kids: [dead] })) })[0].title, "App")
})

test("topology rows add a child via parent_id; new/edit forms offer Save once", () => {
  const row = el("div", { cls: "topology-node-content", dataset: { topologyId: "7" }, kids: [el("span", { cls: "topology-node-name", text: "Core" }), el("div", { cls: "topology-node-actions", kids: [link("Edit", "/topologies/7/edit")] })] })
  const g = collect(row, { path: "/topologies", doc: doc(el("main", { kids: [row] })) })
  assert.equal(g[0].title, "Core")
  assert.deepEqual(g[0].items.map((i) => i.href || i.label), ["Edit", "/topologies/new?parent_id=7"])

  const save = (v) => el("input", { attrs: { type: "submit", value: v } })
  const form = el("form", { kids: [save("Create"), save("Other")] })
  const fg = collect(form, { path: "/topologies/new", doc: doc(el("main", { kids: [el("h2", { text: "New topology" }), form] })) })
  assert.deepEqual(fg[0].items.map((i) => i.label), ["Create"])
})

test("KB project page: section actions, stage moves, status via select, private toggle", () => {
  const btn = (cls, text, attrs = {}) => el("button", { cls, text, attrs })
  const toggle = btn("kbp-sec-toggle", "Tests", { "aria-expanded": "true" })
  const sec = el("section", { cls: "kbp-sec", kids: [
    el("h2", { kids: [el("span", { cls: "kbp-sec-name", text: "Tests" }), toggle] }),
    el("div", { cls: "kbp-sec-body", kids: [el("summary", { text: "+ New test" })] })] })
  const stages = el("ol", { cls: "kbp-stages", kids: [
    btn("kbp-stage-btn", "", { "aria-current": "step" }), el("button", { cls: "kbp-stage-btn", kids: [el("span", { cls: "kbp-stage-name", text: "Build" })] })] })
  let changed = 0
  const opts = [{ value: "active", textContent: "Active" }, { value: "concluded", textContent: "Concluded" }]
  const select = el("select", { cls: "kbp-status" })
  Object.assign(select, { value: "active", options: opts, dispatchEvent: () => changed++ })
  const priv = btn("kbp-private", "Not private", { "data-next": "1" })
  const head = el("header", { cls: "kbp-head", kids: [priv, stages, select] })
  const d = doc(el("main", { kids: [el("h1", { text: "Proj" }), head, sec] }))

  const sg = collect(sec.kids[1].kids[0], { path: "/knowledge-base/projects", doc: d })
  assert.equal(sg[0].title, "Tests")
  assert.deepEqual(sg[0].items.map((i) => i.label), ["+ New test", "Collapse section"])
  const page = sg.find((g) => g.title === "Proj").items
  assert.deepEqual(page.map((i) => i.label), ["Make private", "Move to stage Build", "Mark concluded"])
  page.at(-1).run()
  assert.equal(select.value, "concluded")
  assert.equal(changed, 1)
})

test("notes bar tab closes via its x; maxim/fact cards offer their delete", () => {
  const x = el("button", { cls: "kb-notes-tab-close", text: "x" })
  const tab = el("div", { cls: "kb-notes-tab-group", kids: [el("span", { cls: "kb-notes-tab", text: "Todo" }), x] })
  const bar = el("div", { cls: "kb-notes-bar", kids: [tab, el("button", { cls: "kb-notes-add-btn", text: "+", attrs: { title: "Add note tab" } })] })
  const g = collect(tab.kids[0], { path: "/", doc: doc(bar) })
  assert.deepEqual(g[0].items.map((i) => i.label), ["Close note tab"])
  assert.deepEqual([g[1].title, g[1].items[0].label], ["Notes", "Add note tab"])

  const del = el("button", { text: "", attrs: { "aria-label": "Delete maxim", "data-turbo-confirm": "?" } })
  const card = el("div", { cls: "kb-maxim-card", kids: [el("p", { text: "Be kind" }), del] })
  const mg = collect(card, { path: "/knowledge-base", doc: doc(el("main", { kids: [card] })) })
  assert.deepEqual([mg[0].title, mg[0].items[0].label, mg[0].items[0].danger], ["Be kind", "Delete maxim", true])
})

test("KB file view: viewer bar buttons and file meta toggles are listed", () => {
  const dl = link("Download a.zip", "/serve", "btn")
  const bar = el("div", { cls: "kb-media-action-bar", kids: [dl] })
  const meta = el("header", { cls: "kb-file-meta", kids: [el("button", { cls: "kb-meta-toggle kb-note__toggle", attrs: { title: "Why I saved this" } })] })
  const d = doc(el("main", { kids: [el("h2", { text: "a.zip" }), meta, bar] }))
  const g = collect(d, { path: "/knowledge-base/file", doc: d })
  assert.deepEqual(g.find((x) => x.title === "a.zip").items.map((i) => i.label), ["Download a.zip", "Why I saved this"])
})

test("method/confirm/download links are not offered in a new tab", () => {
  for (const attr of ["data-turbo-method", "data-turbo-confirm", "download"]) {
    const a = el("a", { cls: "btn", text: "Delete", attrs: { href: "/x/1", [attr]: "delete" } })
    const g = collect(a, { path: "/", doc: doc(el("main", { kids: [a] })) })
    assert.deepEqual(g[0].items.map((i) => i.label), ["Open"], attr)
  }
})

test("settings pages list siblings (not the current one); idea tabs are labelled; planning show links back", () => {
  const d = doc(el("main", { kids: [el("h2", { text: "Themes" })] }))
  const g = collect(d, { path: "/settings/themes", doc: d })
  const nav = g.find((x) => x.title === "Settings sections").items
  assert.equal(nav[0].href, "/settings")
  assert.ok(nav.some((i) => i.href === "/settings/display"))
  assert.ok(!nav.some((i) => i.href === "/settings/themes"))

  const tab = el("button", { cls: "tab-button", text: "Scores" })
  const td = doc(el("main", { kids: [el("h2", { text: "Idea" }), tab] }))
  assert.deepEqual(collect(td, { path: "/ideas/1", doc: td })[0].items.map((i) => i.label), ["Go to Scores tab"])
  assert.equal(collect(td, { path: "/planning/4", doc: td }).some((x) => x.title === "Planning"), true)
})
