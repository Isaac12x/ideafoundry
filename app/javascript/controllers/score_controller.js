import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="score"
export default class extends Controller {
  static targets = [
    "trlSlider",
    "trlValue",
    "difficultySlider",
    "difficultyValue",
    "opportunitySlider",
    "opportunityValue",
    "timingSlider",
    "timingValue",
    "computedScore",
    "scoreFormula",
    "scoreDisplay",
    "trlBar",
    "difficultyBar",
    "opportunityBar",
    "timingBar",
    "difficultyExplanation",
    "opportunityExplanation",
    "timingExplanation",
  ];
  static values = {
    trlWeight: { type: Number, default: 0.3 },
    difficultyWeight: { type: Number, default: -0.1 },
    opportunityWeight: { type: Number, default: 0.4 },
    timingWeight: { type: Number, default: 0.2 },
    ideaId: { type: Number, default: null },
    updateUrl: { type: String, default: null },
  };

  connect() {
    this.updateAllValues();
    this.calculateScore();
    this.debounceTimer = null;
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
    }
  }

  updateTrl() {
    this.trlValueTarget.textContent = this.trlSliderTarget.value;
    this.updateProgressBar("trl", this.trlSliderTarget.value);
    this.calculateScore();
    this.debouncedSave();
  }

  updateDifficulty() {
    this.difficultyValueTarget.textContent = this.difficultySliderTarget.value;
    this.updateProgressBar("difficulty", this.difficultySliderTarget.value);
    this.calculateScore();
    this.debouncedSave();
  }

  updateOpportunity() {
    this.opportunityValueTarget.textContent =
      this.opportunitySliderTarget.value;
    this.updateProgressBar("opportunity", this.opportunitySliderTarget.value);
    this.calculateScore();
    this.debouncedSave();
  }

  updateTiming() {
    this.timingValueTarget.textContent = this.timingSliderTarget.value;
    this.updateProgressBar("timing", this.timingSliderTarget.value);
    this.calculateScore();
    this.debouncedSave();
  }

  updateAllValues() {
    if (this.hasTrlSliderTarget) {
      this.trlValueTarget.textContent = this.trlSliderTarget.value;
      this.updateProgressBar("trl", this.trlSliderTarget.value);
    }
    if (this.hasDifficultySliderTarget) {
      this.difficultyValueTarget.textContent =
        this.difficultySliderTarget.value;
      this.updateProgressBar("difficulty", this.difficultySliderTarget.value);
    }
    if (this.hasOpportunitySliderTarget) {
      this.opportunityValueTarget.textContent =
        this.opportunitySliderTarget.value;
      this.updateProgressBar("opportunity", this.opportunitySliderTarget.value);
    }
    if (this.hasTimingSliderTarget) {
      this.timingValueTarget.textContent = this.timingSliderTarget.value;
      this.updateProgressBar("timing", this.timingSliderTarget.value);
    }
  }

  updateProgressBar(type, value) {
    const capitalizedType = type.charAt(0).toUpperCase() + type.slice(1);
    const hasTarget = `has${capitalizedType}BarTarget`;
    const targetName = `${type}BarTarget`;
    if (this[hasTarget]) {
      const percentage = (value / 10) * 100;
      this[targetName].style.width = `${percentage}%`;
    }
  }

  calculateScore() {
    const trl = parseFloat(this.trlSliderTarget?.value) || 0;
    const difficulty = parseFloat(this.difficultySliderTarget?.value) || 0;
    const opportunity = parseFloat(this.opportunitySliderTarget?.value) || 0;
    const timing = parseFloat(this.timingSliderTarget?.value) || 0;

    // Calculate score using configurable weights
    const score =
      trl * this.trlWeightValue +
      difficulty * this.difficultyWeightValue +
      opportunity * this.opportunityWeightValue +
      timing * this.timingWeightValue;

    const roundedScore = Math.round(score * 100) / 100;

    // Update computed score display with animation
    if (this.hasComputedScoreTarget) {
      this.animateScoreChange(this.computedScoreTarget, roundedScore);
    }

    // Update score display in show view if present
    if (this.hasScoreDisplayTarget) {
      this.animateScoreChange(this.scoreDisplayTarget, roundedScore);
    }

    // Update the formula display if present
    if (this.hasScoreFormulaTarget) {
      this.updateFormulaDisplay(
        trl,
        difficulty,
        opportunity,
        timing,
        roundedScore
      );
    }

    // Update score styling based on positive/negative
    this.updateScoreStyle(roundedScore);

    // Trigger a custom event for other components to listen to
    this.dispatch("scoreChanged", {
      detail: {
        score: roundedScore,
        trl: trl,
        difficulty: difficulty,
        opportunity: opportunity,
        timing: timing,
      },
    });

    return roundedScore;
  }

  animateScoreChange(target, newScore) {
    target.classList.add("changing");
    target.textContent = newScore.toFixed(2);

    setTimeout(() => {
      target.classList.remove("changing");
    }, 300);
  }

  updateScoreStyle(score) {
    const targets = [];
    if (this.hasComputedScoreTarget) targets.push(this.computedScoreTarget);
    if (this.hasScoreDisplayTarget) targets.push(this.scoreDisplayTarget);

    targets.forEach((target) => {
      target.classList.remove("positive", "negative");
      target.classList.add(score >= 0 ? "positive" : "negative");

      // Update parent container if it exists
      const container = target.closest(
        ".computed-score-display, .idea-stats-card"
      );
      if (container) {
        container.classList.remove("positive", "negative");
        container.classList.add(score >= 0 ? "positive" : "negative");
      }
    });
  }

  updateFormulaDisplay(trl, difficulty, opportunity, timing, score) {
    const formula = `${trl} × ${this.trlWeightValue} + ${opportunity} × ${
      this.opportunityWeightValue
    } + ${timing} × ${this.timingWeightValue} + ${difficulty} × ${
      this.difficultyWeightValue
    } = ${score.toFixed(2)}`;
    this.scoreFormulaTarget.textContent = formula;
  }

  // Debounced save to prevent too many server requests
  debouncedSave() {
    if (!this.ideaIdValue || !this.updateUrlValue) return;

    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
    }

    this.debounceTimer = setTimeout(() => {
      this.saveScoreToServer();
    }, 1000); // Wait 1 second after last change
  }

  async saveScoreToServer() {
    if (!this.ideaIdValue || !this.updateUrlValue) return;

    const trl = parseInt(this.trlSliderTarget?.value) || 0;
    const difficulty = parseInt(this.difficultySliderTarget?.value) || 0;
    const opportunity = parseInt(this.opportunitySliderTarget?.value) || 0;
    const timing = parseInt(this.timingSliderTarget?.value) || 0;

    const formData = new FormData();
    formData.append("idea[trl]", trl);
    formData.append("idea[difficulty]", difficulty);
    formData.append("idea[opportunity]", opportunity);
    formData.append("idea[timing]", timing);
    if (this.hasDifficultyExplanationTarget)
      formData.append("idea[difficulty_explanation]", this.difficultyExplanationTarget.value);
    if (this.hasOpportunityExplanationTarget)
      formData.append("idea[opportunity_explanation]", this.opportunityExplanationTarget.value);
    if (this.hasTimingExplanationTarget)
      formData.append("idea[timing_explanation]", this.timingExplanationTarget.value);
    formData.append("_method", "PATCH");

    try {
      const response = await fetch(this.updateUrlValue, {
        method: "POST",
        body: formData,
        headers: {
          "X-Requested-With": "XMLHttpRequest",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            ?.content,
        },
      });

      if (response.ok) {
        // Show subtle success indicator
        this.showSaveIndicator("saved");
      } else {
        this.showSaveIndicator("error");
      }
    } catch (error) {
      console.error("Failed to save score:", error);
      this.showSaveIndicator("error");
    }
  }

  showSaveIndicator(status) {
    // Create or update save indicator
    let indicator = this.element.querySelector(".score-save-indicator");
    if (!indicator) {
      indicator = document.createElement("div");
      indicator.className = "score-save-indicator";
      this.element.appendChild(indicator);
    }

    indicator.className = `score-save-indicator ${status}`;
    indicator.textContent = status === "saved" ? "✓ Saved" : "⚠ Save failed";

    // Remove indicator after 2 seconds
    setTimeout(() => {
      indicator.remove();
    }, 2000);
  }

  // Method to update weights (can be called from settings)
  updateWeights(weights) {
    this.trlWeightValue = weights.trl || this.trlWeightValue;
    this.difficultyWeightValue =
      weights.difficulty || this.difficultyWeightValue;
    this.opportunityWeightValue =
      weights.opportunity || this.opportunityWeightValue;
    this.timingWeightValue = weights.timing || this.timingWeightValue;
    this.calculateScore();
  }

  // Method to reset all scores to zero
  resetScores() {
    if (this.hasTrlSliderTarget) this.trlSliderTarget.value = 0;
    if (this.hasDifficultySliderTarget) this.difficultySliderTarget.value = 0;
    if (this.hasOpportunitySliderTarget) this.opportunitySliderTarget.value = 0;
    if (this.hasTimingSliderTarget) this.timingSliderTarget.value = 0;

    this.updateAllValues();
    this.calculateScore();
    this.debouncedSave();
  }
}
