import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const CANONICAL_PHRASE = "By my will and power you will open. Open sesame";

test("enrollment records a local microphone sample when speech recognition fails", async () => {
  const VoiceIdController = await loadVoiceIdController();
  const controller = buildEnrollmentController(new VoiceIdController());
  const restoreBrowser = installBrowserStubs();

  try {
    controller.connect();
    controller.record();
    await delay(500);

    assert.equal(controller.recordBtnTarget.textContent, "Record phrase 2 of 3");
    assert.equal(controller.recordBtnTarget.disabled, false);
    assert.equal(controller.sampleTranscriptTargets[0].value, CANONICAL_PHRASE);
    assert.ok(Number(controller.sampleDurationTargets[0].value) > 0);
    assert.ok(Number(controller.sampleRmsTargets[0].value) > 0);
    assert.doesNotMatch(controller.statusTarget.textContent, /unavailable/i);
    assert.doesNotMatch(controller.statusTarget.textContent, new RegExp(CANONICAL_PHRASE));
  } finally {
    restoreBrowser();
  }
});

test("unlock waits for the ready action before listening", async () => {
  const VoiceIdController = await loadVoiceIdController();
  const controller = buildUnlockController(new VoiceIdController());
  const restoreBrowser = installBrowserStubs();

  try {
    controller.connect();
    await delay(300);

    assert.equal(controller.formSubmitted, false);
    assert.equal(controller.transcriptTarget.value, "");
    assert.equal(controller.recordBtnTarget.disabled, false);
    assert.equal(controller.recordBtnTarget.textContent, "I'm ready");

    controller.record();
    await delay(500);

    assert.equal(controller.formSubmitted, true);
    assert.equal(controller.transcriptTarget.value, CANONICAL_PHRASE);
    assert.ok(Number(JSON.parse(controller.payloadTarget.value).duration_ms) > 0);
    assert.match(controller.statusTarget.textContent, /checking voice id/i);
    assert.doesNotMatch(controller.statusTarget.textContent, new RegExp(CANONICAL_PHRASE));
  } finally {
    restoreBrowser();
  }
});

async function loadVoiceIdController() {
  const source = await readFile(
    new URL("../../app/javascript/controllers/voice_id_controller.js", import.meta.url),
    "utf8"
  );
  const runnableSource = source
    .replace('import { Controller } from "@hotwired/stimulus";\n\n', "")
    .replace("export default class extends Controller", "return class VoiceIdController extends Controller");

  return new Function("Controller", runnableSource)(class {});
}

function buildEnrollmentController(controller) {
  controller.modeValue = "enroll";
  controller.phraseValue = CANONICAL_PHRASE;
  controller.element = { classList: { contains: () => false } };
  controller.statusTarget = { textContent: "" };
  controller.recordBtnTarget = {
    dataset: {},
    disabled: false,
    textContent: "Record phrase",
  };
  controller.submitBtnTarget = { disabled: true };
  controller.sampleTranscriptTargets = [
    { dataset: { voiceIdVariant: CANONICAL_PHRASE }, value: "" },
    { dataset: { voiceIdVariant: "By my will and power, you will open. Open sesame!" }, value: "" },
    { dataset: { voiceIdVariant: "By my will and power you will open open sesame" }, value: "" },
  ];
  controller.sampleDurationTargets = [{ value: "" }, { value: "" }, { value: "" }];
  controller.sampleRmsTargets = [{ value: "" }, { value: "" }, { value: "" }];
  controller.variantItemTargets = [fakeVariantItem(), fakeVariantItem(), fakeVariantItem()];
  controller.hasRecordBtnTarget = true;
  controller.hasSubmitBtnTarget = true;
  controller.hasVariantItemTarget = true;
  return controller;
}

function buildUnlockController(controller) {
  controller.modeValue = "unlock";
  controller.phraseValue = CANONICAL_PHRASE;
  controller.element = { classList: { contains: () => false } };
  controller.formSubmitted = false;
  controller.formTarget = {
    requestSubmit: () => {
      controller.formSubmitted = true;
    },
  };
  controller.payloadTarget = { value: "{}" };
  controller.statusTarget = { textContent: "" };
  controller.transcriptTarget = { value: "" };
  controller.hasFormTarget = true;
  controller.recordBtnTarget = {
    dataset: {},
    disabled: false,
    textContent: "I'm ready",
  };
  controller.hasRecordBtnTarget = true;
  controller.hasSubmitBtnTarget = false;
  controller.hasVariantItemTarget = false;
  controller.sampleTranscriptTargets = [];
  controller.sampleDurationTargets = [];
  controller.sampleRmsTargets = [];
  controller.variantItemTargets = [];
  return controller;
}

function fakeVariantItem() {
  return {
    classList: {
      remove() {},
      toggle() {},
    },
  };
}

function installBrowserStubs() {
  const previousWindow = globalThis.window;
  const previousNavigator = globalThis.navigator;
  const previousPerformance = globalThis.performance;
  const previousMediaRecorder = globalThis.MediaRecorder;
  const previousFetch = globalThis.fetch;
  const previousDocument = globalThis.document;

  let now = 1000;

  class FakeAnalyser {
    constructor() {
      this.fftSize = 32;
      this.smoothingTimeConstant = 0;
      this.frames = 0;
    }

    getByteTimeDomainData(data) {
      this.frames += 1;
      const amplitude = this.frames < 14 ? 32 : 0;
      for (let i = 0; i < data.length; i += 1) {
        data[i] = 128 + (i % 2 === 0 ? amplitude : -amplitude);
      }
    }
  }

  class FakeAudioContext {
    constructor() {
      this.state = "running";
    }

    createAnalyser() {
      return new FakeAnalyser();
    }

    createMediaStreamSource() {
      return { connect() {} };
    }

    decodeAudioData() {
      return Promise.resolve({
        getChannelData: () => new Float32Array([0.4, -0.4, 0.4, -0.4]),
      });
    }

    close() {
      return Promise.resolve();
    }

    resume() {
      return Promise.resolve();
    }
  }

  class FakeMediaRecorder {
    constructor(_stream, options = {}) {
      this.mimeType = options.mimeType || "audio/webm";
      this.state = "inactive";
    }

    static isTypeSupported() {
      return true;
    }

    start() {
      this.state = "recording";
      setTimeout(() => {
        this.ondataavailable?.({ data: new Blob(["fake audio"], { type: this.mimeType }) });
        this.stop();
      }, 5);
    }

    stop() {
      this.state = "inactive";
      now += 2100;
      setTimeout(() => this.onstop?.(), 5);
    }
  }

  class FailingSpeechRecognition {
    start() {
      setTimeout(() => {
        this.onerror?.({ error: "network" });
        this.onend?.();
      }, 20);
    }
  }

  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {
      mediaDevices: {
        getUserMedia: () => Promise.resolve({
          getTracks: () => [{ stop() {} }],
        }),
      },
    },
  });

  globalThis.window = {
    AudioContext: FakeAudioContext,
    MediaRecorder: FakeMediaRecorder,
    SpeechRecognition: undefined,
    webkitSpeechRecognition: FailingSpeechRecognition,
    cancelAnimationFrame: clearTimeout,
    clearTimeout,
    location: { assign() {} },
    requestAnimationFrame: (callback) => setTimeout(() => {
      now += 120;
      callback(now);
    }, 5),
    setTimeout,
  };
  globalThis.MediaRecorder = FakeMediaRecorder;
  globalThis.fetch = () => Promise.resolve({
    ok: true,
    json: () => Promise.resolve({ transcript: CANONICAL_PHRASE, duration_ms: 2100, rms: 0.38 }),
  });
  globalThis.document = {
    querySelector: () => null,
  };
  globalThis.performance = { now: () => now };

  return () => {
    globalThis.window = previousWindow;
    Object.defineProperty(globalThis, "navigator", {
      configurable: true,
      value: previousNavigator,
    });
    globalThis.performance = previousPerformance;
    globalThis.MediaRecorder = previousMediaRecorder;
    globalThis.fetch = previousFetch;
    globalThis.document = previousDocument;
  };
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
