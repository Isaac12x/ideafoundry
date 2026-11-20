import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="tabs"
export default class extends Controller {
  static targets = ["tab", "panel"];
  static values = {
    defaultTab: { type: String, default: "description" },
  };

  connect() {
    const hash = window.location.hash?.slice(1)
    const validTab = hash && this.panelTargets.some(p => p.dataset.tabPanel === hash)
    // A hash naming an item inside a panel (#maxim_5, from a chip) opens that panel, scrolls to it and flashes it.
    const item = hash && !validTab ? document.getElementById(decodeURIComponent(hash)) : null
    const itemPanel = item && this.panelTargets.find(p => p.contains(item))
    this.showTab(validTab ? hash : itemPanel?.dataset.tabPanel || this.defaultTabValue, true)
    if (itemPanel) this.spotlight(item)
  }

  spotlight(el) {
    el.scrollIntoView({ block: "center" })
    el.classList.add("is-ref-target")
    setTimeout(() => el.classList.remove("is-ref-target"), 2600)
  }

  switch(event) {
    event.preventDefault();
    const tabName = event.currentTarget.dataset.tabName;
    this.showTab(tabName);
  }

  showTab(tabName, replace = false) {
    // Hide all panels
    this.panelTargets.forEach((panel) => {
      panel.classList.add("hidden");
    });

    // Deactivate all tabs
    this.tabTargets.forEach((tab) => {
      tab.classList.remove("active");
    });

    // Show selected panel
    const selectedPanel = this.panelTargets.find(
      (panel) => panel.dataset.tabPanel === tabName
    );
    if (selectedPanel) {
      selectedPanel.classList.remove("hidden");
      selectedPanel.dispatchEvent(new CustomEvent("tab:shown", { bubbles: true }));
    }

    // Activate selected tab
    const selectedTab = this.tabTargets.find(
      (tab) => tab.dataset.tabName === tabName
    );
    if (selectedTab) {
      selectedTab.classList.add("active");
    }

    // Update URL hash without scrolling
    if (history.pushState) {
      // replace on initial connect so Back doesn't stack duplicate entries
      history[replace ? "replaceState" : "pushState"](null, null, `#${tabName}`);
    }
  }
}
