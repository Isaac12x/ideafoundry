# frozen_string_literal: true

require "test_helper"

class EmailPresetHelperTest < ActiveSupport::TestCase
  test "PRESETS contains all five preset keys" do
    assert_equal %w[alert digest info neutral success], EmailPresetHelper::PRESETS.keys.sort
  end

  test "each preset has required color keys" do
    required = %i[bg text accent card_bg border muted]
    EmailPresetHelper::PRESETS.each do |name, preset|
      required.each do |key|
        assert preset.key?(key), "Preset '#{name}' missing key :#{key}"
      end
    end
  end

  test "preset_for returns default preset for event type" do
    user = User.create!(email: "preset@test.com", name: "T")
    preset = EmailPresetHelper.preset_for("state_changed", user)
    assert_equal "#e74c3c", preset[:accent]
  end

  test "preset_for returns user-chosen preset" do
    user = User.create!(email: "preset2@test.com", name: "T")
    user.update_event_presets({ "state_changed" => "info" })
    preset = EmailPresetHelper.preset_for("state_changed", user)
    assert_equal "#3498db", preset[:accent]
  end

  test "preset_for falls back to neutral for unknown event" do
    user = User.create!(email: "preset3@test.com", name: "T")
    preset = EmailPresetHelper.preset_for("nonexistent", user)
    assert_equal "#d4953a", preset[:accent]
  end

  test "all presets share same dark base" do
    base_keys = %i[bg text card_bg border muted]
    EmailPresetHelper::PRESETS.values.combination(2).each do |a, b|
      base_keys.each do |key|
        assert_equal a[key], b[key], "Base key :#{key} differs between presets"
      end
    end
  end
end
