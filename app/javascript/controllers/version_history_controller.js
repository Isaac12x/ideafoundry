import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["entry", "detail", "sparkline"];

  connect() {
    this.animateSparkline();
  }

  toggle(event) {
    const entry = event.currentTarget.closest("[data-version-history-target='entry']");
    const detail = entry.querySelector("[data-version-history-target='detail']");
    if (!detail) return;

    const isOpen = entry.classList.contains("is-expanded");

    // Close all others
    this.entryTargets.forEach((e) => {
      e.classList.remove("is-expanded");
      const d = e.querySelector("[data-version-history-target='detail']");
      if (d) d.style.maxHeight = "0px";
    });

    if (!isOpen) {
      entry.classList.add("is-expanded");
      detail.style.maxHeight = detail.scrollHeight + "px";
      // Recheck after transition in case content shifts
      setTimeout(() => {
        if (entry.classList.contains("is-expanded")) {
          detail.style.maxHeight = detail.scrollHeight + "px";
        }
      }, 350);
    }
  }

  animateSparkline() {
    if (!this.hasSparklineTarget) return;
    const line = this.sparklineTarget.querySelector(".vh-spark-line");
    if (!line) return;

    const length = line.getTotalLength();
    line.style.strokeDasharray = length;
    line.style.strokeDashoffset = length;

    requestAnimationFrame(() => {
      line.style.transition = "stroke-dashoffset 1.2s cubic-bezier(0.4, 0, 0.2, 1)";
      line.style.strokeDashoffset = "0";
    });
  }
}
