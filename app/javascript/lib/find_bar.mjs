// Pure text matching for the in-app find bar. `texts` = text of each visible text node, in order.
// Returns [{ node, start, end }] (matches never span nodes; ponytail: inline markup splits a phrase
// across nodes, so a search for "bold word" misses when only half is <b>. Join nodes if that bites).
export function findMatches(texts, query, matchCase = false) {
  if (!query) return []
  const needle = matchCase ? query : query.toLowerCase()
  const out = []
  texts.forEach((text, node) => {
    const hay = matchCase ? text : text.toLowerCase()
    for (let i = hay.indexOf(needle); i !== -1; i = hay.indexOf(needle, i + needle.length)) {
      out.push({ node, start: i, end: i + needle.length })
    }
  })
  return out
}

// Index after stepping `dir` (+1/-1) from `current` over `count` matches, wrapping.
export const stepIndex = (current, dir, count) => (count ? (current + dir + count) % count : -1)
