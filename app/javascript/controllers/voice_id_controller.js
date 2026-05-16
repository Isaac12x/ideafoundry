import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "form",
    "payload",
    "status",
    "transcript",
    "sampleTranscript",
    "sampleDuration",
    "sampleRms",
  ];
  static values = {
    mode: String,
    phrase: String,
    redirectUrl: String,
  };

  connect() {
    this.sampleIndex = 0;
    if (this.element.classList.contains("voice-id-shell--opening")) {
      window.setTimeout(() => {
        window.location.assign(this.redirectUrlValue || "/");
      }, 1700);
    }
  }

  record() {
    const startedAt = performance.now();
    this.statusTarget.textContent = "Listening… say the phrase now.";

    const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!Recognition) {
      this.statusTarget.textContent = "Speech recognition is unavailable. Type the transcript below, then submit.";
      return;
    }

    const recognition = new Recognition();
    recognition.lang = "en-US";
    recognition.interimResults = false;
    recognition.maxAlternatives = 1;

    recognition.onresult = (event) => {
      const transcript = event.results?.[0]?.[0]?.transcript || "";
      const durationMs = Math.round(performance.now() - startedAt);
      const sample = {
        transcript,
        duration_ms: durationMs,
        rms: 0,
      };

      if (this.modeValue === "enroll") {
        this.storeEnrollmentSample(sample);
      } else {
        this.transcriptTarget.value = transcript;
        this.payloadTarget.value = JSON.stringify(sample);
      }

      this.statusTarget.textContent = `Captured: “${transcript}”`;
    };

    recognition.onerror = () => {
      this.statusTarget.textContent = "Could not capture speech. Try again or type the transcript manually.";
    };

    recognition.start();
  }

  storeEnrollmentSample(sample) {
    const index = Math.min(this.sampleIndex, this.sampleTranscriptTargets.length - 1);
    if (index < 0) return;

    this.sampleTranscriptTargets[index].value = sample.transcript;
    this.sampleDurationTargets[index].value = sample.duration_ms;
    this.sampleRmsTargets[index].value = sample.rms;
    this.sampleIndex = Math.min(index + 1, this.sampleTranscriptTargets.length);
  }
}
