// Regenerates app/assets/images/emoji.json (the KB emoji pickers' lazy data) from Unicode's emoji-test.txt.
// Usage: node scripts/generate_emoji.mjs [path-or-url]   Shape: [[group, [[emoji, name], ...]], ...]
import { readFile, writeFile } from "node:fs/promises"

const source = process.argv[2] || "https://unicode.org/Public/emoji/latest/emoji-test.txt"
const text = /^https?:/.test(source) ? await (await fetch(source)).text() : await readFile(source, "utf8")
const groups = []
for (const line of text.split("\n")) {
  const group = line.match(/^# group: (.+)/)
  if (group) { if (group[1] !== "Component") groups.push([group[1], []]); continue }
  const entry = line.match(/; fully-qualified\s+# (\S+) E[\d.]+ (.+)$/)
  if (entry && groups.length) groups.at(-1)[1].push([entry[1], entry[2]])
}
await writeFile(new URL("../app/assets/images/emoji.json", import.meta.url), JSON.stringify(groups))
console.log(groups.map(([name, list]) => `${name}: ${list.length}`).join("\n"))
