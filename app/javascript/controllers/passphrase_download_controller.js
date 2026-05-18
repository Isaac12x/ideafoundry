import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["passphrase"]

  download() {
    const passphrase = this.passphraseTarget.value.trim()
    if (!passphrase) return

    const content = [
      "Idea Foundry — Database Recovery Passphrase",
      "============================================",
      "",
      `Generated: ${new Date().toISOString()}`,
      "",
      passphrase,
      "",
      "Store this file in a secure, offline location.",
      "Do NOT store it alongside the encrypted database.",
    ].join("\n")

    const blob = new Blob([content], { type: "text/plain" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = "idea-foundry-recovery-passphrase.txt"
    a.click()
    URL.revokeObjectURL(url)
  }
}
