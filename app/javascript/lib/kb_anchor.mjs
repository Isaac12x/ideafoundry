// Text anchoring for KB highlights. A mark is stored as character offsets
// into a root element's text (all descendant text nodes, in order) plus the
// quoted text and a little context either side. On reopen the offsets are
// tried first; if the text moved (edited markdown, re-rendered docx) the quote
// is searched for and the occurrence whose context matches best wins.

export const CONTEXT = 32
const SKIP_PARENTS = new Set(["STYLE", "SCRIPT", "TITLE", "TEXTAREA", "NOSCRIPT"])
// Whitespace directly inside these is layout, not text: wrapping it would put
// inline marks where only rows/items/blocks belong.
const BLOCK_PARENTS = new Set([
  "TABLE", "THEAD", "TBODY", "TFOOT", "TR", "COLGROUP", "UL", "OL", "DL", "SELECT",
  "BODY", "DIV", "SECTION", "ARTICLE", "HEADER", "FOOTER", "MAIN", "NAV", "ASIDE", "FIGURE"
])

export function textNodes(root) {
  const doc = root.ownerDocument
  const walker = doc.createTreeWalker(root, 4 /* NodeFilter.SHOW_TEXT */)
  const nodes = []
  while (walker.nextNode()) nodes.push(walker.currentNode)
  return nodes
}

export function rootText(root) {
  return textNodes(root).map((node) => node.data).join("")
}

// Range -> stored anchor. Null when the range leaves the root or is blank.
export function describe(root, range) {
  if (!root.contains(range.startContainer) || !root.contains(range.endContainer)) return null

  const pre = root.ownerDocument.createRange()
  pre.setStart(root, 0)
  pre.setEnd(range.startContainer, range.startOffset)
  const start = pre.toString().length
  const quote = range.toString()
  if (!quote.trim()) return null

  const text = rootText(root)
  const end = start + quote.length
  return {
    start_offset: start,
    end_offset: end,
    quote,
    prefix: text.slice(Math.max(0, start - CONTEXT), start),
    suffix: text.slice(end, end + CONTEXT)
  }
}

// Stored anchor -> {start, end} in `text`, or null if the quote is gone.
export function locate(text, mark) {
  const { start_offset: start, end_offset: end, quote } = mark
  if (text.slice(start, end) === quote) return { start, end }

  const prefix = mark.prefix || ""
  const suffix = mark.suffix || ""
  let best = null
  for (let i = text.indexOf(quote); i !== -1; i = text.indexOf(quote, i + 1)) {
    const j = i + quote.length
    const score = sharedTail(text.slice(Math.max(0, i - prefix.length), i), prefix) +
      sharedHead(text.slice(j, j + suffix.length), suffix)
    const distance = Math.abs(i - start)
    if (!best || score > best.score || (score === best.score && distance < best.distance)) {
      best = { start: i, end: j, score, distance }
    }
  }
  return best && { start: best.start, end: best.end }
}

// Wraps text in [start, end) with elements from makeEl(); returns them in order.
// Whitespace-only fragments between blocks are left alone; spaces inside text
// (pdf.js emits them as their own nodes) are painted so marks read as one stroke.
export function wrap(root, start, end, makeEl) {
  const wrapped = []
  let pos = 0
  for (const node of textNodes(root)) {
    const nodeStart = pos
    const length = node.data.length
    pos += length
    if (pos <= start) continue
    if (nodeStart >= end) break
    if (SKIP_PARENTS.has(node.parentNode?.nodeName)) continue

    const a = Math.max(start, nodeStart) - nodeStart
    const b = Math.min(end, pos) - nodeStart
    if (!node.data.slice(a, b).trim() && BLOCK_PARENTS.has(node.parentNode?.nodeName)) continue

    let target = node
    if (b < length) target.splitText(b)
    if (a > 0) target = target.splitText(a)
    const el = makeEl()
    target.parentNode.insertBefore(el, target)
    el.appendChild(target)
    wrapped.push(el)
  }
  return wrapped
}

export function unwrap(elements) {
  for (const el of elements) {
    const parent = el.parentNode
    if (!parent) continue
    while (el.firstChild) parent.insertBefore(el.firstChild, el)
    parent.removeChild(el)
    parent.normalize()
  }
}

function sharedTail(a, b) {
  let n = 0
  while (n < a.length && n < b.length && a[a.length - 1 - n] === b[b.length - 1 - n]) n++
  return n
}

function sharedHead(a, b) {
  let n = 0
  while (n < a.length && n < b.length && a[n] === b[n]) n++
  return n
}
