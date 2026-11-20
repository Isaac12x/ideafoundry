import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { emojiScore, usableEmoji } from "../../app/javascript/lib/emoji_grid.mjs"

const data = JSON.parse(await readFile(new URL("../../app/assets/images/emoji.json", import.meta.url), "utf8")).flatMap(([, list]) => list)

test("dna ranks the DNA emoji first and excludes unrelated ones", () => {
  const hits = data.map(([emoji, label, keywords]) => [emoji, emojiScore(label, keywords, "dna")]).filter(([, score]) => score).sort((a, b) => b[1] - a[1])
  assert.equal(hits[0][0], "🧬")
  assert.ok(hits.length <= 3, `too many hits: ${hits.map(([emoji]) => emoji).join("")}`)
})

test("name matches beat keyword matches; every term must match", () => {
  assert.ok(emojiScore("gear", "cog tool", "gear") > emojiScore("wrench", "gear tool", "gear"))
  assert.equal(emojiScore("gear", "cog tool", "gear moon"), 0)
  assert.ok(emojiScore("thumbs up", "", "thu") > 0, "prefix match")
  assert.equal(emojiScore("abandoned", "", "dna"), 0, "short substrings do not count")
})

test("skin-tone variants collapse into the base and unsupported emoji are dropped", () => {
  const list = [["👍", "thumbs up"], ["👍🏽", "thumbs up: medium skin tone"], ["🫨", "shaking face"]]
  assert.deepEqual(usableEmoji(list, (emoji) => emoji !== "🫨").map(([emoji]) => emoji), ["👍"])
  assert.ok(usableEmoji(data).length < data.length / 2, "tone variants are not shown")
})
