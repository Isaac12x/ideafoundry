import test from "node:test"
import assert from "node:assert/strict"
import { locate, rootText, wrap } from "../../app/javascript/lib/kb_anchor.mjs"

const mark = (text, quote, nth = 0, ctx = 8) => {
  let start = -1
  for (let i = 0; i <= nth; i++) start = text.indexOf(quote, start + 1)
  const end = start + quote.length
  return { start_offset: start, end_offset: end, quote,
    prefix: text.slice(Math.max(0, start - ctx), start), suffix: text.slice(end, end + ctx) }
}

test("stored offsets win when the text is unchanged", () => {
  const text = "alpha beta gamma beta"
  assert.deepEqual(locate(text, mark(text, "beta", 1)), { start: 17, end: 21 })
})

test("after an edit the quote is re-found by its surrounding context", () => {
  const before = "one cat sat. two cat ran. three cat hid."
  const saved = mark(before, "cat", 1)
  const after = "PREAMBLE ADDED. " + before.replace("one cat sat.", "one cat sat down.")
  const spot = locate(after, saved)
  assert.equal(after.slice(spot.start - 4, spot.end + 4), "two cat ran")
})

test("a quote that no longer exists is not painted", () => {
  assert.equal(locate("nothing here", { start_offset: 0, end_offset: 4, quote: "gone", prefix: "", suffix: "" }), null)
})

test("wrap paints inline spaces but leaves whitespace between table rows alone", () => {
  const { root, doc } = fakeTree()
  const made = wrap(root, 0, 7, () => doc.createElement("mark"))
  assert.equal(made.map((el) => el.firstChild.data).join("|"), "ab| |cd")
})

test("rendered diagram chrome is not document text, so marks never land in the svg", () => {
  const { root, doc, el, Text } = fakeTree()
  root.appendChild(Object.assign(el("DIV", el("TEXT", new Text("label"))), { className: "kb-diagram-out" }))
  assert.equal(rootText(root), "ab \ncd")
  assert.deepEqual(wrap(root, 0, 99, () => doc.createElement("mark")).map((el) => el.firstChild.data), ["ab", " ", "cd"])
})

// Minimal DOM: <div><span>ab</span><span> </span><tbody>\n</tbody><span>cd</span></div>
function fakeTree() {
  class Node {
    constructor(nodeName) { this.nodeName = nodeName; this.childNodes = []; this.parentNode = null }
    get firstChild() { return this.childNodes[0] }
    closest(sel) { return sel.split(", ").includes(`.${this.className}`) ? this : this.parentNode?.closest?.(sel) ?? null }
    appendChild(child) { child.parentNode?.removeChild(child); child.parentNode = this; this.childNodes.push(child); return child }
    insertBefore(child, ref) { child.parentNode?.removeChild(child); child.parentNode = this; this.childNodes.splice(this.childNodes.indexOf(ref), 0, child); return child }
    removeChild(child) { this.childNodes.splice(this.childNodes.indexOf(child), 1); child.parentNode = null }
  }
  class Text extends Node {
    constructor(data) { super("#text"); this.data = data }
    splitText(at) { const rest = new Text(this.data.slice(at)); this.data = this.data.slice(0, at); const p = this.parentNode; p.childNodes.splice(p.childNodes.indexOf(this) + 1, 0, rest); rest.parentNode = p; return rest }
  }
  const doc = {
    createElement: (name) => new Node(name.toUpperCase()),
    createTreeWalker: (root) => {
      const texts = []
      const visit = (n) => n.childNodes.forEach((c) => (c instanceof Text ? texts.push(c) : visit(c)))
      visit(root)
      let i = -1
      return { nextNode: () => (++i < texts.length), get currentNode() { return texts[i] } }
    }
  }
  const el = (name, ...kids) => { const n = new Node(name); n.ownerDocument = doc; kids.forEach((k) => n.appendChild(k)); return n }
  const root = el("DIV", el("SPAN", new Text("ab")), el("SPAN", new Text(" ")), el("TBODY", new Text("\n")), el("SPAN", new Text("cd")))
  return { root, doc, el, Text }
}
