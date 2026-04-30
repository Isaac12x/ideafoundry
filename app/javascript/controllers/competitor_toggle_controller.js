import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["tab", "panel"];

  switch(event) {
    event.preventDefault();
    const name = event.currentTarget.dataset.subtab;
    this.show(name);
  }

  show(name) {
    this.tabTargets.forEach((t) => {
      t.classList.toggle("is-active", t.dataset.subtab === name);
    });
    this.panelTargets.forEach((p) => {
      p.classList.toggle("hidden", p.dataset.subpanel !== name);
    });
  }
}
