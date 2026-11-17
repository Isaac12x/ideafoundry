import { Controller } from "@hotwired/stimulus";

// Captures where an idea was born: auto on a brand-new idea, or on demand via the button.
// Never overwrites a label the user typed during auto-capture.
export default class extends Controller {
  static targets = ["label", "lat", "lng", "status"];
  static values = { auto: Boolean };

  connect() {
    if (this.autoValue && !this.latTarget.value && !this.lngTarget.value) this.capture(false);
  }

  locate() {
    this.capture(true);
  }

  capture(overwrite) {
    if (!navigator.geolocation) return this.say("Location unavailable");
    this.say("Locating…");
    navigator.geolocation.getCurrentPosition(
      (pos) => this.found(pos.coords, overwrite),
      (err) => this.say(err.code === 1 ? "Location permission denied" : "Location unavailable"),
      { enableHighAccuracy: false, timeout: 10000, maximumAge: 600000 }
    );
  }

  async found({ latitude, longitude }, overwrite) {
    this.latTarget.value = latitude.toFixed(6);
    this.lngTarget.value = longitude.toFixed(6);
    if (this.labelTarget.value.trim() && !overwrite) return this.say("");
    const fallback = `${latitude.toFixed(4)}, ${longitude.toFixed(4)}`;
    let label = fallback;
    try {
      const res = await fetch(
        `https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=14&lat=${latitude}&lon=${longitude}`,
        { headers: { Accept: "application/json" } }
      );
      const a = (await res.json()).address || {};
      const place = a.city || a.town || a.village || a.suburb || a.municipality;
      label = [place, a.country].filter(Boolean).join(", ") || fallback;
    } catch (_) {
      // ponytail: offline or blocked, coordinates are label enough
    }
    // a label typed while the lookup was in flight wins over auto-capture
    if (overwrite || !this.labelTarget.value.trim()) {
      this.labelTarget.value = label;
      this.labelTarget.dispatchEvent(new Event("input", { bubbles: true }));
    }
    this.say("");
  }

  say(text) {
    this.statusTarget.textContent = text;
  }
}
