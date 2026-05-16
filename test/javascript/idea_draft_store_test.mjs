import test from "node:test";
import assert from "node:assert/strict";
import {
  decryptDraft,
  encryptDraft,
  hasMeaningfulDraft,
  stableDraftDigest,
} from "../../app/javascript/lib/idea_draft_store.mjs";

test("encrypted idea drafts do not expose plaintext and decrypt with the unlock seed", async () => {
  const draft = {
    "idea[title]": "Never lose this idea",
    "idea[description]": "<p>Private details</p>",
  };

  const encrypted = await encryptDraft(draft, {
    storageKey: "idea-draft:test:user-1",
    unlockSeed: "unlocked-session-token",
  });

  const serialized = JSON.stringify(encrypted);
  assert.equal(encrypted.version, 1);
  assert.match(encrypted.digest, /^[a-f0-9]{64}$/);
  assert.doesNotMatch(serialized, /Never lose this idea/);
  assert.doesNotMatch(serialized, /Private details/);

  const restored = await decryptDraft(encrypted, {
    storageKey: "idea-draft:test:user-1",
    unlockSeed: "unlocked-session-token",
  });

  assert.deepEqual(restored, draft);
});

test("draft digest is stable for the same content", async () => {
  assert.equal(
    await stableDraftDigest({ b: "two", a: "one" }),
    await stableDraftDigest({ a: "one", b: "two" })
  );
});

test("meaningful draft detection ignores empty scaffolding", () => {
  assert.equal(hasMeaningfulDraft({ "idea[title]": "  ", authenticity_token: "token" }), false);
  assert.equal(hasMeaningfulDraft({ "idea[title]": "Something worth saving" }), true);
});
