import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "form",
    "payload",
    "status",
    "transcript",
    "manualTranscript",
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
    transcribeUrl: String,
  };

  connect() {
    this.sampleIndex = 0;
    this._recording = false;
    this._enrollmentBlocked = false;
    if (this.element.classList.contains("voice-id-shell--opening")) {
      window.setTimeout(() => {
        window.location.assign(this.redirectUrlValue || "/");
      }, 1700);
      return;
    }
    this._updateEnrollProgress();
    if (this._isEnrollment() && !this._recordingSupported()) {
      this._blockEnrollment(this._enrollmentUnavailableMessage("Voice recording is not available in this browser."));
    }
  }

  async record() {
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
      this.statusTarget.textContent = "Microphone recording is unavailable. Type the transcript below, then submit.";
      return;
    }

    try {
      this.statusTarget.textContent = "Listening locally… say the phrase now.";
      const startedAt = performance.now();
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const chunks = [];
      const mimeType = this.supportedMimeType();
      const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);

      recorder.ondataavailable = (event) => {
        if (event.data?.size) chunks.push(event.data);
      };

      const finished = new Promise((resolve) => {
        recorder.onstop = resolve;
      });

      recorder.start();
      window.setTimeout(() => {
        if (recorder.state !== "inactive") recorder.stop();
      }, 5200);

      await finished;
      stream.getTracks().forEach((track) => track.stop());

      const durationMs = Math.round(performance.now() - startedAt);
      const blob = new Blob(chunks, { type: recorder.mimeType || "audio/webm" });
      const rms = await this.calculateRms(blob);
      const transcription = await this.transcribe(blob, durationMs, rms);
      const sample = {
        transcript: transcription.transcript,
        duration_ms: Number(transcription.duration_ms || durationMs),
        rms: Number(transcription.rms || rms),
      };

      if (this.modeValue === "enroll") {
        this.storeEnrollmentSample(sample);
        this.statusTarget.textContent = "Captured locally. Record the next phrase when you're ready.";
      } else {
        this.submitUnlockSample(sample);
      }
    } catch (error) {
      this.statusTarget.textContent = error.message || "Could not capture speech locally. Try again or type the transcript manually.";
    }
  }

  supportedMimeType() {
    const candidates = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4"];
    return candidates.find((type) => MediaRecorder.isTypeSupported(type)) || "";
  }

  async transcribe(blob, durationMs, rms) {
    const formData = new FormData();
    formData.append("audio", blob, "voice-id.webm");
    formData.append("duration_ms", durationMs.toString());
    formData.append("rms", rms.toString());

    const response = await fetch(this.transcribeUrlValue, {
      method: "POST",
      headers: this.csrfHeaders(),
      body: formData,
    });
    const data = await response.json().catch(() => ({}));

    if (!response.ok) {
      throw new Error(data.error || "Local Voice ID transcription failed.");
    }

    return {
      transcript: data.transcript || "",
      duration_ms: data.duration_ms || durationMs,
      rms: data.rms || rms,
    };
  }

  csrfHeaders() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    return token ? { "X-CSRF-Token": token } : {};
  }

  async calculateRms(blob) {
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return 0;

    try {
      const audioContext = new AudioContext();
      const buffer = await audioContext.decodeAudioData(await blob.arrayBuffer());
      const data = buffer.getChannelData(0);
      let sumSquares = 0;
      for (let index = 0; index < data.length; index += 1) {
        sumSquares += data[index] * data[index];
      }
      await audioContext.close();
      return Math.sqrt(sumSquares / Math.max(data.length, 1));
    } catch (_error) {
      return 0;
    }
  }

  submitUnlockSample(sample) {
    this.transcriptTarget.value = sample.transcript || "";
    this.payloadTarget.value = JSON.stringify({
      duration_ms: sample.duration_ms,
      rms: sample.rms,
    });
    if (this.hasManualTranscriptTarget) {
      this.manualTranscriptTarget.disabled = true;
    }
    this.statusTarget.textContent = "Checking Voice ID locally…";
    this.formTarget.requestSubmit();
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

  _handleLocalAudioError(error) {
    if (error?.name === "NotAllowedError" || error?.name === "SecurityError") {
      this._handleRecordingUnavailable(
        this._isEnrollment()
          ? this._enrollmentUnavailableMessage("Microphone access is blocked.")
          : "Microphone access is blocked. Allow microphone access in your browser settings, then try again."
      );
    } else if (error?.name === "NotFoundError" || error?.name === "DevicesNotFoundError") {
      this._handleRecordingUnavailable(
        this._isEnrollment()
          ? this._enrollmentUnavailableMessage("No microphone was found.")
          : "No microphone was found. Connect a microphone, then try again."
      );
    } else {
      this._handleRecordingUnavailable(
        this._isEnrollment()
          ? this._enrollmentUnavailableMessage("Voice recording is not working right now.")
          : "Voice recording is not working right now. Try again later."
      );
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

  _audioSamplingSupported() {
    return Boolean(
      navigator.mediaDevices?.getUserMedia &&
        (window.AudioContext || window.webkitAudioContext) &&
        window.requestAnimationFrame &&
        window.cancelAnimationFrame
    );
  }

  _recordingSupported() {
    return this._audioSamplingSupported() || this._recognitionSupported();
  }

  _recordButtonIdleLabel() {
    return this._isEnrollment() ? "Record phrase" : "I'm ready";
  }

  _sampleTranscript() {
    if (!this._isEnrollment()) return this.phraseValue;

    const index = Math.min(this.sampleIndex, this.sampleTranscriptTargets.length - 1);
    return this.sampleTranscriptTargets[index]?.dataset.voiceIdVariant || this.phraseValue;
  }

  _localAudioOptions() {
    return {
      maxDurationMs: 7000,
      minDurationMs: 1200,
      silenceDurationMs: 800,
      voiceThreshold: 0.015,
    };
  }

  _isEnrollment() {
    return this.modeValue === "enroll";
  }

  _enrollmentUnavailableMessage(prefix) {
    return `${prefix} Try again later and turn Voice ID off in Security settings for now.`;
  }
}
