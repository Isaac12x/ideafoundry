// Pure ordering helpers for the KB tree (drag zones, sibling reordering).

// Where a drop lands on a row: folders split into thirds-ish (edges reorder, middle moves in), files in halves.
export function dropZone(offsetY, height, isDir) {
  const ratio = height > 0 ? offsetY / height : 0.5
  if (isDir) return ratio < 0.25 ? "before" : ratio > 0.75 ? "after" : "into"
  return ratio < 0.5 ? "before" : "after"
}

// names with `name` moved next to `target` (pos "before"/"after"); unknown target appends.
export function insertNear(names, name, target, pos) {
  const rest = names.filter((n) => n !== name)
  const at = rest.indexOf(target)
  if (at < 0) return [...rest, name]
  rest.splice(pos === "after" ? at + 1 : at, 0, name)
  return rest
}

// names with `name` moved one step (delta -1 up / +1 down); null when it can't move.
export function shift(names, name, delta) {
  const from = names.indexOf(name)
  const to = from + delta
  if (from < 0 || to < 0 || to >= names.length) return null
  const out = [...names]
  out.splice(from, 1)
  out.splice(to, 0, name)
  return out
}
