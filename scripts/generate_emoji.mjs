// Regenerates app/assets/images/emoji.json (the KB emoji pickers' lazy data) from Unicode's emoji-test.txt.
// Usage: node scripts/generate_emoji.mjs [path-or-url]   Shape: [[group, [[emoji, name, "keywords"?], ...]], ...]
// Keywords/aliases come from emojibase (CLDR annotations) tags, merged by emoji; names from emoji-test.txt.
import { readFile, writeFile } from "node:fs/promises"

const source = process.argv[2] || "https://unicode.org/Public/emoji/latest/emoji-test.txt"
const text = /^https?:/.test(source) ? await (await fetch(source)).text() : await readFile(source, "utf8")
const base = await (await fetch("https://cdn.jsdelivr.net/npm/emojibase-data@latest/en/data.json")).json()
const tags = new Map()
for (const e of base) for (const x of [e, ...(e.skins || [])]) tags.set(x.emoji, e.tags || [])
const groups = []
for (const line of text.split("\n")) {
  const group = line.match(/^# group: (.+)/)
  if (group) { if (group[1] !== "Component") groups.push([group[1], []]); continue }
  const entry = line.match(/; fully-qualified\s+# (\S+) E[\d.]+ (.+)$/)
  if (entry && groups.length) {
    const words = (tags.get(entry[1]) || []).filter((tag) => !entry[2].includes(tag)).join(" ")
    groups.at(-1)[1].push(words ? [entry[1], entry[2], words] : [entry[1], entry[2]])
  }
}
await writeFile(new URL("../app/assets/images/emoji.json", import.meta.url), JSON.stringify(groups))
console.log(groups.map(([name, list]) => `${name}: ${list.length}`).join("\n"))
