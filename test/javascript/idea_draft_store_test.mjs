import test from "node:test";
import assert from "node:assert/strict";
import {
  decryptDraft,
  encryptDraft,
  hasMeaningfulDraft,
  restoreDraftFields,
  shouldShowResumePrompt,
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

test("meaningful draft detection ignores empty scaffolding and default idea fields", () => {
  assert.equal(hasMeaningfulDraft({ "idea[title]": "  ", authenticity_token: "token" }), false);
  assert.equal(hasMeaningfulDraft({ "idea[state]": "idea_new", "idea[template_id]": "", "idea[title]": "" }), false);
  assert.equal(hasMeaningfulDraft({ "idea[title]": "Something worth saving" }), true);
});

test("resume prompt can appear over existing idea content when an edit draft is stored", () => {
  const currentDraft = { "idea[title]": "Saved title already on the server" };
  const storedRecord = { savedAt: "2026-05-23T10:00:00.000Z" };

  assert.equal(shouldShowResumePrompt({ record: storedRecord, currentDraft }), false);
  assert.equal(shouldShowResumePrompt({ record: storedRecord, currentDraft, promptWithExistingContent: true }), true);
  assert.equal(shouldShowResumePrompt({ record: null, currentDraft, promptWithExistingContent: true }), false);
});

// Minimal DOM stand-in: node has no document, so fake just what restoreDraftFields touches.
function fakeForm(fields) {
  const events = [];
  globalThis.CSS ||= { escape: (s) => s };
  return {
    events,
    querySelectorAll: (selector) => fields.filter((f) => selector === `[name="${f.name}"]`),
    querySelector: () => null,
    dispatchEvent: (e) => events.push(e),
  };
}
const field = (name, type, value = "") => ({ name, type, value, checked: false, dispatchEvent() {} });

test("restore never writes into the hidden theme_ids sentinel, so a restored theme can still be removed", () => {
  const sentinel = field("idea[theme_ids][]", "hidden", "");
  const chip = field("idea[theme_ids][]", "checkbox", "7");
  restoreDraftFields(fakeForm([sentinel, chip]), { "idea[theme_ids][]": [ "7" ] });
  assert.equal(sentinel.value, "");
  assert.equal(chip.checked, true);
});

test("restore still fills ordinary hidden fields (description) and text fields", () => {
  const desc = field("idea[description]", "hidden");
  const title = field("idea[title]", "text");
  restoreDraftFields(fakeForm([desc, title]), { "idea[description]": "<p>x</p>", "idea[title]": "T" });
  assert.equal(desc.value, "<p>x</p>");
  assert.equal(title.value, "T");
});

test("restore announces the draft so client-built chips (new themes, KB picks) can be rebuilt", () => {
  const form = fakeForm([]);
  const draft = { "idea[new_theme_names][]": [ "Health" ], "kb_picks[]": [ "0:Ferment" ] };
  restoreDraftFields(form, draft);
  const event = form.events.find((e) => e.type === "idea-draft:restore");
  assert.deepEqual(event.detail.draft, draft);
  assert.equal(event.bubbles, true);
});

test("new theme chips and KB picks round-trip through collectDraftFields", async () => {
  const { collectDraftFields } = await import("../../app/javascript/lib/idea_draft_store.mjs");
  const newTheme = { ...field("idea[new_theme_names][]", "checkbox", "Health"), checked: true };
  const pick = field("kb_picks[]", "hidden", "0:Ferment");
  const sentinel = field("idea[theme_ids][]", "hidden", "");
  const draft = collectDraftFields({ elements: [ newTheme, pick, sentinel ] });
  assert.deepEqual(draft["idea[new_theme_names][]"], [ "Health" ]);
  assert.deepEqual(draft["kb_picks[]"], [ "0:Ferment" ]);
  assert.deepEqual(draft["idea[theme_ids][]"], []);
});

test("an untouched editor description (<p></p>) is not a meaningful draft", () => {
  assert.equal(hasMeaningfulDraft({ "idea[description]": "<p></p>", "idea[title]": "" }), false);
  assert.equal(hasMeaningfulDraft({ "idea[description]": "<p>words</p>" }), true);
  assert.equal(hasMeaningfulDraft({ "idea[description]": "<p></p>", "idea[for_licensing]": "0", "idea[state]": "idea_new" }), false);
});
