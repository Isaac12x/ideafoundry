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
    this.showTab(validTab ? hash : this.defaultTabValue)
  }

  switch(event) {
    event.preventDefault();
    const tabName = event.currentTarget.dataset.tabName;
    this.showTab(tabName);
  }

  showTab(tabName) {
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

    // Update URL hash without scrolling. Keep Turbo's history.state: a null
    // state makes Turbo ignore Back to this entry (URL changes, page doesn't).
    // Replace, not push: nothing listens for hash changes, so a pushed tab entry
    // would only make Back change the URL without switching the tab.
    history.replaceState(history.state, "", `#${tabName}`);
  }
}
