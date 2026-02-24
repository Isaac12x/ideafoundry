# frozen_string_literal: true

module EmailPresetHelper
  BASE = {
    bg: '#14141a', text: '#ece8e1', card_bg: '#1c1c24',
    border: '#2a2a36', muted: '#9a9498'
  }.freeze

  PRESETS = {
    'alert'   => BASE.merge(accent: '#e74c3c').freeze,
    'info'    => BASE.merge(accent: '#3498db').freeze,
    'success' => BASE.merge(accent: '#2ecc71').freeze,
    'neutral' => BASE.merge(accent: '#d4953a').freeze,
    'digest'  => BASE.merge(accent: '#9b59b6').freeze
  }.freeze

  DEFAULT_EVENT_PRESETS = {
    'state_changed'     => 'alert',
    'webhook_triggered' => 'alert',
    'score_changed'     => 'info',
    'created'           => 'success',
    'added_to_list'     => 'success',
    'share_idea'        => 'neutral',
    'share_list'        => 'neutral',
    'digest_daily'      => 'digest',
    'digest_weekly'     => 'digest'
  }.freeze

  def self.preset_for(event_type, user)
    key = user.event_preset_for(event_type)
    PRESETS[key] || PRESETS['neutral']
  end
end
