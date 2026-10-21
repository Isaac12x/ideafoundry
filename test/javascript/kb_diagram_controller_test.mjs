import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const source = (await readFile(new URL("../../app/javascript/controllers/kb_diagram_controller.js", import.meta.url), "utf8"))
  .replace(/import \{ Controller \} from "@hotwired\/stimulus"\n/, "")
  .replace("export default class extends Controller", "return class KbDiagramController extends Controller")
const Diagram = new Function("Controller", source)(class {})

const mermaidSource = (keywordValue, src) => Object.assign(new Diagram(), { keywordValue, source: src }).mermaidSource()

test("alias fences get their keyword unless the body already opens with one", () => {
  assert.equal(mermaidSource("flowchart", "A --> B"), "flowchart TD\nA --> B")
  assert.equal(mermaidSource("flowchart", "LR\nA --> B"), "flowchart LR\nA --> B")
  assert.equal(mermaidSource("flowchart", "graph LR\nA --> B"), "graph LR\nA --> B")
  assert.equal(mermaidSource("stateDiagram-v2", "stateDiagram\n[*] --> A"), "stateDiagram\n[*] --> A")
  assert.equal(mermaidSource("sequenceDiagram", "Alice->>Bob: hi"), "sequenceDiagram\nAlice->>Bob: hi")
  assert.equal(mermaidSource("", "graph TD\nA"), "graph TD\nA")
})

test("fail() shows the full multi-line parse error in a <pre> via textContent", () => {
  const made = []
  globalThis.document = { createElement: (tag) => { const el = { tag, remove() {}, setAttribute() {}, append(...k) { this.kids = k } }; made.push(el); return el } }
  const ctl = Object.assign(new Diagram(), { element: { prepend() {} }, pre: {}, toggle: {} })
  ctl.fail(new Error("Parse error on line 2:\nA-->>\n---^\nExpecting X"), { remove() {} })
  delete globalThis.document
  const detail = made.find((el) => el.tag === "pre")
  assert.equal(detail.textContent, "Parse error on line 2:\nA-->>\n---^\nExpecting X")
})
