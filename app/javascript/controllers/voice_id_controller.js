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
    if (this._isEnrollment() && !this._recordingSupported()) {
      this._blockEnrollment(this._enrollmentUnavailableMessage("Voice recording is not available in this browser."));
    }
  }

  record() {
    if (this._recording || this._enrollmentBlocked) return;

    if (this._audioSamplingSupported()) {
      this._recordWithLocalAudio();
      return;
    }

    this._recordWithRecognition();
  }

  async _recordWithLocalAudio() {
    this._recording = true;
    this._setRecordingState(true);
    this.statusTarget.textContent = "Listening... say the phrase now.";

    try {
      const sample = await this._captureLocalAudioSample(this._sampleTranscript());
      if (!sample.voice_detected) {
        this.statusTarget.textContent = "No speech detected. Press record and say the phrase clearly.";
        return;
      }
      delete sample.voice_detected;
      this._storeSample(sample);
      this.statusTarget.textContent = this._isEnrollment() ? "Voice sample captured." : "Voice sample captured. Submit to unlock.";
    } catch (error) {
      this._handleLocalAudioError(error);
    } finally {
      this._recording = false;
      if (!this._enrollmentBlocked) {
        this._setRecordingState(false);
      }
    }
  }

  _recordWithRecognition() {
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

      this._storeSample(sample);

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

  async _captureLocalAudioSample(transcript) {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
    });
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    let audioContext = null;
    try {
      audioContext = new AudioContext();
      if (audioContext.state === "suspended" && audioContext.resume) {
        await audioContext.resume();
      }

      const analyser = audioContext.createAnalyser();
      analyser.fftSize = 1024;
      analyser.smoothingTimeConstant = 0.2;
      const source = audioContext.createMediaStreamSource(stream);
      source.connect(analyser);

      return await this._measureVoiceSample({ analyser, transcript });
    } finally {
      stream.getTracks().forEach((track) => track.stop());
      if (audioContext?.close) await audioContext.close();
    }
  }

  _measureVoiceSample({ analyser, transcript }) {
    const startedAt = performance.now();
    const data = new Uint8Array(analyser.fftSize);
    const options = this._localAudioOptions();
    let animationId = null;
    let finishTimer = null;
    let lastVoiceAt = startedAt;
    let voiceDetected = false;
    let rmsFrameCount = 0;
    let rmsSquareTotal = 0;

    return new Promise((resolve) => {
      const finish = () => {
        if (animationId !== null) window.cancelAnimationFrame(animationId);
        if (finishTimer !== null) window.clearTimeout(finishTimer);
        const durationMs = Math.round(performance.now() - startedAt);
        const rms = rmsFrameCount > 0 ? Math.sqrt(rmsSquareTotal / rmsFrameCount) : 0;
        resolve({
          transcript,
          duration_ms: durationMs,
          rms: Number(rms.toFixed(4)),
          voice_detected: voiceDetected,
        });
      };

      const sampleFrame = () => {
        analyser.getByteTimeDomainData(data);
        const rms = this._rmsForAudioFrame(data);
        const now = performance.now();
        rmsSquareTotal += rms * rms;
        rmsFrameCount += 1;

        if (rms >= options.voiceThreshold) {
          voiceDetected = true;
          lastVoiceAt = now;
        }

        const longEnough = now - startedAt >= options.minDurationMs;
        const silentLongEnough = voiceDetected && now - lastVoiceAt >= options.silenceDurationMs;
        const maxedOut = now - startedAt >= options.maxDurationMs;

        if ((longEnough && silentLongEnough) || maxedOut) {
          finish();
        } else {
          animationId = window.requestAnimationFrame(sampleFrame);
        }
      };

      finishTimer = window.setTimeout(finish, options.maxDurationMs + 250);
      animationId = window.requestAnimationFrame(sampleFrame);
    });
  }

  _rmsForAudioFrame(data) {
    const sumSquares = data.reduce((sum, value) => {
      const normalized = (value - 128) / 128;
      return sum + normalized * normalized;
    }, 0);
    return Math.sqrt(sumSquares / data.length);
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

  _storeSample(sample) {
    if (this._isEnrollment()) {
      this.storeEnrollmentSample(sample);
    } else {
      this.transcriptTarget.value = sample.transcript;
      this.payloadTarget.value = JSON.stringify(sample);
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
