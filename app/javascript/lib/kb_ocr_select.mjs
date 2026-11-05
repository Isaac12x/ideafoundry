// Where a pointer at (x, y) -- percent of the image -- lands among OCR line boxes ({x,y,w,h}, percent).
// => { index, side: "before" | "inside" | "after" }: nearest line by y (above all = first line start,
// below all = last line end), then which side of that line's box the x falls on.
export function nearestLine(lines, x, y) {
  if (!lines.length) return null
  const last = lines.length - 1
  const top = Math.min(...lines.map((l) => l.y))
  const bottom = Math.max(...lines.map((l) => l.y + l.h))
  if (y < top) return { index: 0, side: "before" }
  if (y > bottom) return { index: last, side: "after" }
  let best = 0, bestGap = Infinity
  lines.forEach((l, i) => {
    const gap = y < l.y ? l.y - y : y > l.y + l.h ? y - (l.y + l.h) : 0
    if (gap < bestGap) { best = i; bestGap = gap }
  })
  const l = lines[best]
  return { index: best, side: x < l.x ? "before" : x > l.x + l.w ? "after" : "inside" }
}
