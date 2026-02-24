class Template < ApplicationRecord
  belongs_to :user
  has_many :ideas, dependent: :nullify

  # Validations
  validates :name, presence: true, uniqueness: { scope: :user_id }
  validate :valid_field_definitions_type
  validate :only_one_default_per_user
  validate :valid_field_definitions_format
  validate :valid_field_instance_ids
  validate :valid_section_order_format
  validate :valid_tab_definitions_format

  # JSON serialization
  serialize :field_definitions, coder: JSON
  serialize :section_order, coder: JSON
  serialize :tab_definitions, coder: JSON

  # Scopes
  scope :default_for_user, ->(user) { where(user: user, is_default: true) }

  # Callbacks
  before_save :ensure_single_default

  def self.default_for(user)
    default_for_user(user).first
  end

  def apply_to_idea(idea)
    return false unless idea.user == user
    
    # Set template reference
    idea.template = self
    
    # Initialize any missing custom fields with default values
    initialize_custom_fields(idea)
    
    true
  end

  def required_fields
    field_definitions.select { |field| field['required'] == true }
  end

  def validate_idea_against_template(idea)
    errors = []

    required_fields.each do |field|
      key = field['instance_id'] || field['name']
      field_value = get_field_value_from_idea(idea, key)

      if field_value.blank?
        errors << "#{field['label'] || field['name'].humanize} is required"
      end
    end

    errors
  end

  def get_sections
    section_order || default_section_order
  end

  def section_field_instances
    (section_order || []).select { |s| s.start_with?('field:') }.map { |s| s.delete_prefix('field:') }
  end

  def field_by_instance_id(instance_id)
    (field_definitions || []).find { |fd| fd['instance_id'] == instance_id }
  end

  def effective_tab_definitions
    tab_definitions.presence || [{ 'name' => 'general', 'label' => 'General', 'position' => 0 }]
  end

  def fields_by_tab
    tabs = effective_tab_definitions.sort_by { |t| t['position'].to_i }
    default_tab = tabs.first&.dig('name') || 'general'

    grouped = {}
    tabs.each { |t| grouped[t['name']] = [] }

    (field_definitions || []).each do |field|
      tab = field['tab'].presence || default_tab
      grouped[tab] ||= []
      grouped[tab] << field
    end

    # Sort fields within each tab by position
    grouped.each { |_, fields| fields.sort_by! { |f| f['position'].to_i } }
    grouped
  end

  private

  def valid_field_definitions_type
    return if field_definitions.nil? || field_definitions.is_a?(Array)
    errors.add(:field_definitions, "must be an array")
  end

  def only_one_default_per_user
    return unless is_default?
    
    existing_default = user.templates.where(is_default: true).where.not(id: id)
    if existing_default.exists?
      errors.add(:is_default, "can only have one default template per user")
    end
  end

  def ensure_single_default
    return unless is_default_changed? && is_default?
    
    # Set all other templates for this user to non-default
    user.templates.where.not(id: id).update_all(is_default: false)
  end

  def valid_field_definitions_format
    return if field_definitions.blank?
    
    unless field_definitions.is_a?(Array)
      errors.add(:field_definitions, "must be an array")
      return
    end
    
    field_definitions.each_with_index do |field, index|
      unless field.is_a?(Hash)
        errors.add(:field_definitions, "field at index #{index} must be a hash")
        next
      end
      
      unless field['name'].present?
        errors.add(:field_definitions, "field at index #{index} must have a name")
      end
      
      unless field['type'].present?
        errors.add(:field_definitions, "field at index #{index} must have a type")
      end
      
      unless %w[text textarea number select boolean date].include?(field['type'])
        errors.add(:field_definitions, "field at index #{index} has invalid type")
      end
    end
  end

  def valid_section_order_format
    return if section_order.blank?

    unless section_order.is_a?(Array)
      errors.add(:section_order, "must be an array")
      return
    end

    valid_builtin = %w[header stats description media metadata timeline]
    section_order.each do |section|
      next if section.start_with?('field:')
      unless valid_builtin.include?(section)
        errors.add(:section_order, "contains invalid section: #{section}")
      end
    end
  end

  def valid_tab_definitions_format
    return if tab_definitions.blank?

    unless tab_definitions.is_a?(Array)
      errors.add(:tab_definitions, "must be an array")
      return
    end

    tab_definitions.each_with_index do |tab, index|
      unless tab.is_a?(Hash)
        errors.add(:tab_definitions, "tab at index #{index} must be a hash")
        next
      end
      unless tab['name'].present?
        errors.add(:tab_definitions, "tab at index #{index} must have a name")
      end
    end
  end

  def valid_field_instance_ids
    return if field_definitions.blank?
    return unless field_definitions.is_a?(Array)

    ids = field_definitions.map { |fd| fd['instance_id'] }.compact
    if ids.length != ids.uniq.length
      errors.add(:field_definitions, "contain duplicate instance_ids")
    end
    field_definitions.each_with_index do |fd, idx|
      if fd.is_a?(Hash) && fd['name'].present? && fd['instance_id'].blank?
        errors.add(:field_definitions, "field at index #{idx} must have an instance_id")
      end
    end
  end

  def initialize_custom_fields(idea)
    field_definitions.each do |field|
      key = field['instance_id'] || field['name']

      next if get_field_value_from_idea(idea, key).present?

      if field['default_value'].present?
        set_field_value_on_idea(idea, key, field['default_value'])
      end
    end
  end

  def get_field_value_from_idea(idea, key)
    return idea.send(key) if idea.respond_to?(key)
    idea.metadata&.dig(key)
  end

  def set_field_value_on_idea(idea, key, value)
    if idea.respond_to?("#{key}=")
      idea.send("#{key}=", value)
    else
      idea.metadata ||= {}
      idea.metadata[key] = value
    end
  end

  def default_section_order
    %w[header stats description media metadata timeline]
  end
end