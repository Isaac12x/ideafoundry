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
      history.pushState(null, null, `#${tabName}`);
    }
  }
}
