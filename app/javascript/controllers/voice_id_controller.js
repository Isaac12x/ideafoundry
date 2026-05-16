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
    "recordBtn",
    "submitBtn",
    "variantItem",
  ];
  static values = {
    mode: String,
    phrase: String,
    redirectUrl: String,
  };

  connect() {
    this.sampleIndex = 0;
    this._recording = false;
    this._enrollmentBlocked = false;
    if (this.element.classList.contains("voice-id-shell--opening")) {
      window.setTimeout(() => {
        window.location.assign(this.redirectUrlValue || "/");
      }, 1700);
    }
    this._updateEnrollProgress();
    if (this._isEnrollment() && !this._recognitionSupported()) {
      this._blockEnrollment(this._enrollmentUnavailableMessage("Voice recording is not available in this browser."));
    }
  }

  record() {
    if (this._recording || this._enrollmentBlocked) return;

    const Recognition = this._recognitionConstructor();
    if (!Recognition) {
      this._handleRecordingUnavailable(
        this._isEnrollment()
          ? this._enrollmentUnavailableMessage("Voice recording is not available in this browser.")
          : "Voice recording is not available in this browser. Try again later."
      );
      return;
    }

    this._recording = true;
    this._setRecordingState(true);

    const startedAt = performance.now();
    const recognition = new Recognition();
    recognition.lang = "en-US";
    recognition.interimResults = false;
    recognition.maxAlternatives = 1;
    recognition.continuous = false;

    let captured = false;

    recognition.onresult = (event) => {
      captured = true;
      const transcript = (event.results?.[0]?.[0]?.transcript || "").trim();
      if (!transcript) {
        this.statusTarget.textContent = "Couldn't hear that clearly. Press record and try again.";
        return;
      }
      const durationMs = Math.round(performance.now() - startedAt);
      const sample = { transcript, duration_ms: durationMs, rms: 0 };

      if (this._isEnrollment()) {
        this.storeEnrollmentSample(sample);
      } else {
        this.transcriptTarget.value = transcript;
        this.payloadTarget.value = JSON.stringify(sample);
      }

      this.statusTarget.textContent = `Captured: "${transcript}"`;
    };

    recognition.onerror = (event) => {
      captured = true;
      if (event.error === "not-allowed" || event.error === "service-not-allowed") {
        this._handleRecordingUnavailable(
          this._isEnrollment()
            ? this._enrollmentUnavailableMessage("Microphone access is blocked.")
            : "Microphone access is blocked. Allow microphone access in your browser settings, then try again."
        );
      } else if (event.error === "audio-capture" || event.error === "network" || event.error === "language-not-supported") {
        this._handleRecordingUnavailable(
          this._isEnrollment()
            ? this._enrollmentUnavailableMessage("Voice recording is not working right now.")
            : "Voice recording is not working right now. Try again later."
        );
      } else if (event.error === "no-speech") {
        this.statusTarget.textContent = "No speech detected. Press record and say the phrase clearly.";
      } else if (event.error === "aborted") {
        this.statusTarget.textContent = "Recording stopped. Press record to try again.";
      } else {
        this.statusTarget.textContent = "Could not capture speech. Press record to try again.";
      }
    };

    recognition.onend = () => {
      this._recording = false;
      if (!this._enrollmentBlocked) {
        this._setRecordingState(false);
      }
      if (!captured) {
        this.statusTarget.textContent = "No speech detected. Press record and say the phrase clearly.";
      }
    };

    try {
      recognition.start();
      this.statusTarget.textContent = "Listening... say the phrase now.";
    } catch {
      this._recording = false;
      this._setRecordingState(false);
      this._handleRecordingUnavailable(
        this._isEnrollment()
          ? this._enrollmentUnavailableMessage("Could not start recording.")
          : "Could not start recording. Try again later."
      );
    }
  }

  _setRecordingState(active) {
    if (!this.hasRecordBtnTarget) return;
    if (active) {
      this.recordBtnTarget.dataset.prevText = this.recordBtnTarget.textContent;
      this.recordBtnTarget.textContent = "Listening...";
      this.recordBtnTarget.disabled = true;
    } else {
      this.recordBtnTarget.textContent = this.recordBtnTarget.dataset.prevText || "Record phrase";
      this.recordBtnTarget.disabled = false;
      this._updateEnrollProgress();
    }
  }

  storeEnrollmentSample(sample) {
    const index = Math.min(this.sampleIndex, this.sampleTranscriptTargets.length - 1);
    if (index < 0) return;

    this.sampleTranscriptTargets[index].value = sample.transcript;
    this.sampleDurationTargets[index].value = sample.duration_ms;
    this.sampleRmsTargets[index].value = sample.rms;
    this.sampleIndex = Math.min(index + 1, this.sampleTranscriptTargets.length);
    this._updateEnrollProgress();
  }

  _updateEnrollProgress() {
    if (!this._isEnrollment() || this._enrollmentBlocked) return;
    if (!this.hasRecordBtnTarget) return;

    const total = this.sampleTranscriptTargets.length;
    const done = this.sampleIndex;

    if (done >= total) {
      this.recordBtnTarget.textContent = "All phrases recorded";
      this.recordBtnTarget.disabled = true;
    } else {
      this.recordBtnTarget.textContent = `Record phrase ${done + 1} of ${total}`;
      this.recordBtnTarget.disabled = false;
    }

    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = done < total;
    }

    if (this.hasVariantItemTarget) {
      this.variantItemTargets.forEach((item, i) => {
        item.classList.toggle("voice-id-variant--active", i === done);
        item.classList.toggle("voice-id-variant--done", i < done);
      });
    }
  }

  _handleRecordingUnavailable(message) {
    if (this._isEnrollment()) {
      this._blockEnrollment(message);
    } else {
      this.statusTarget.textContent = message;
    }
  }

  _blockEnrollment(message) {
    this._enrollmentBlocked = true;
    this.statusTarget.textContent = message;
    if (this.hasRecordBtnTarget) {
      this.recordBtnTarget.textContent = "Recording unavailable";
      this.recordBtnTarget.disabled = true;
    }
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = true;
    }
    if (this.hasVariantItemTarget) {
      this.variantItemTargets.forEach((item) => {
        item.classList.remove("voice-id-variant--active", "voice-id-variant--done");
      });
    }
  }

  _recognitionSupported() {
    return Boolean(this._recognitionConstructor());
  }

  _recognitionConstructor() {
    return window.SpeechRecognition || window.webkitSpeechRecognition;
  }

  _isEnrollment() {
    return this.modeValue === "enroll";
  }

  _enrollmentUnavailableMessage(prefix) {
    return `${prefix} Try again later and turn Voice ID off in Security settings for now.`;
  }
}
