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
    transcribeUrl: String,
  };

  connect() {
    this.sampleIndex = 0;
    if (this.element.classList.contains("voice-id-shell--opening")) {
      window.setTimeout(() => {
        window.location.assign(this.redirectUrlValue || "/");
      }, 1700);
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
      const transcript = await this.transcribe(blob, durationMs, rms);
      const sample = { transcript, duration_ms: durationMs, rms };

      if (this.modeValue === "enroll") {
        this.storeEnrollmentSample(sample);
      } else {
        this.transcriptTarget.value = transcript;
        this.payloadTarget.value = JSON.stringify(sample);
      }

      this.statusTarget.textContent = `Captured locally: “${transcript}”`;
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

    return data.transcript || "";
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

  storeEnrollmentSample(sample) {
    const index = Math.min(this.sampleIndex, this.sampleTranscriptTargets.length - 1);
    if (index < 0) return;

    this.sampleTranscriptTargets[index].value = sample.transcript;
    this.sampleDurationTargets[index].value = sample.duration_ms;
    this.sampleRmsTargets[index].value = sample.rms;
    this.sampleIndex = Math.min(index + 1, this.sampleTranscriptTargets.length);
  }
}
