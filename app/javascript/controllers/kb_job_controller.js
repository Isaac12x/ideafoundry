import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "form", "src", "path", "contextKind", "contextLabel", "prompt", "recordButton", "recordLabel", "status", "submitButton"]
  static values = { createUrl: String }

  open(event) {
    const detail = event.detail
    this.srcTarget.value = detail.src
    this.pathTarget.value = detail.path
    this.contextKindTarget.value = detail.contextKind
    this.contextLabelTarget.textContent = detail.label
    this.promptTarget.value = ""
    this.audioBlob = null
    this._setStatus("The request and selected context stay on this machine.")
    this.dialogTarget.showModal()
    this.promptTarget.focus()
  }

  close() {
    this._stopTracks()
    if (this.recorder?.state === "recording") this.recorder.stop()
    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  async toggleRecording(event) {
    event.preventDefault()
    if (this.recorder?.state === "recording") {
      this.recorder.stop()
      return
    }

    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
      this._setStatus("Voice recording is unavailable in this browser. Type the request instead.", true)
      return
    }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      this.chunks = []
      this.recorder = new MediaRecorder(this.stream, this._recorderOptions())
      this.recorder.addEventListener("dataavailable", (recordingEvent) => {
        if (recordingEvent.data.size) this.chunks.push(recordingEvent.data)
      })
      this.recorder.addEventListener("stop", () => this._recordingStopped())
      this.recorder.start()
      this.recordButtonTarget.classList.add("is-recording")
      this.recordLabelTarget.textContent = "Stop recording"
      this.submitButtonTarget.disabled = true
      this._setStatus("Recording locally… choose Stop recording when finished.")
      this.recordingTimeout = window.setTimeout(() => {
        if (this.recorder?.state === "recording") this.recorder.stop()
      }, 120000)
    } catch (error) {
      this._setStatus(error?.name === "NotAllowedError" ? "Microphone access is blocked. Allow it or type the request." : "The microphone could not start. Type the request instead.", true)
    }
  }

  async submit(event) {
    event.preventDefault()
    if (!this.promptTarget.value.trim() && !this.audioBlob) {
      this._setStatus("Type a request or record a voice message first.", true)
      this.promptTarget.focus()
      return
    }

    const formData = new FormData(this.formTarget)
    if (this.audioBlob) formData.append("voice_message", this.audioBlob, "kb-request.webm")
    const active = document.querySelector(".kb-file-row.is-active")
    if (active) {
      formData.append("sel_src", active.dataset.kbTreeSrcParam || "")
      formData.append("sel_file", active.dataset.kbTreeRelParam || "")
    }

    this.submitButtonTarget.disabled = true
    this.submitButtonTarget.textContent = "Creating job…"
    try {
      const response = await fetch(this.createUrlValue, {
        method: "POST",
        headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": this._csrfToken() },
        body: formData
      })
      const html = await response.text()
      if (html) window.Turbo?.renderStreamMessage(html)
      if (!response.ok) throw new Error("The AI job could not be created.")
      this.close()
    } catch (error) {
      this._setStatus(error.message, true)
    } finally {
      this.submitButtonTarget.disabled = false
      this.submitButtonTarget.textContent = "Create AI job"
    }
  }

  _recordingStopped() {
    if (this.recordingTimeout) window.clearTimeout(this.recordingTimeout)
    const mimeType = this.recorder?.mimeType || "audio/webm"
    this.audioBlob = new Blob(this.chunks, { type: mimeType })
    this._stopTracks()
    this.recordButtonTarget.classList.remove("is-recording")
    this.recordLabelTarget.textContent = "Replace voice message"
    this.submitButtonTarget.disabled = false
    this._setStatus("Voice message attached. FluidVoice will transcribe it before the AI job runs.")
  }

  _stopTracks() {
    this.stream?.getTracks()?.forEach((track) => track.stop())
    this.stream = null
  }

  _recorderOptions() {
    const candidates = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4"]
    const mimeType = candidates.find((type) => MediaRecorder.isTypeSupported(type))
    return mimeType ? { mimeType } : undefined
  }

  _setStatus(message, error = false) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("is-error", error)
  }

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content ?? ""
  }
}
