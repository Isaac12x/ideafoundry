import test from "node:test"
import assert from "node:assert/strict"
import { embeddedUrl, clipFromUrl, formatClip, parseClip } from "../../app/javascript/lib/kb_clip_time.mjs"

const wrapped = "chrome-extension://noogafoofpebimajpfpamcfhoaifemoa/suspended.html#ttl=(12)%20this%20method&pos=0&uri=https://www.youtube.com/watch?v=ews_k4ikjuy&t=354s"

test("embeddedUrl finds wrapped and plain urls, rejects prose", () => {
  assert.match(embeddedUrl(wrapped), /^https:\/\/www\.youtube\.com\/watch\?v=ews_k4ikjuy&t=354s$/)
  assert.equal(embeddedUrl("https://a.com/x"), "https://a.com/x")
  assert.equal(embeddedUrl("new note.md"), null)
  assert.equal(embeddedUrl("notes.md"), null)
})

test("clipFromUrl mirrors Kb::ClipTime", () => {
  assert.deepEqual(clipFromUrl("https://youtu.be/x?t=354s"), [354, null])
  assert.deepEqual(clipFromUrl("https://x.com/v?start=10&end=20"), [10, 20])
  assert.deepEqual(clipFromUrl("https://x.com/v#t=1:02,2:00"), [62, 120])
  assert.deepEqual(clipFromUrl("https://x.com/v"), [null, null])
  assert.deepEqual(clipFromUrl(embeddedUrl(wrapped)), [354, null])
})

test("parse/format", () => {
  assert.equal(parseClip("5m54s"), 354)
  assert.equal(parseClip("1:02:03"), 3723)
  assert.equal(parseClip("abc"), null)
  assert.equal(formatClip(354), "5:54")
  assert.equal(formatClip(3723), "1:02:03")
})
