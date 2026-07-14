class KbEntryPreference < ApplicationRecord
  DEFAULT_SOURCE_PATH = "".freeze
  DEFAULT_RELATIVE_PATH = "".freeze
  DEFAULT_ENTRY_TYPE = "default_folder".freeze
  ENTRY_TYPES = %w[root folder file default_folder].freeze
  ICON_KINDS = %w[default emoji image].freeze

  belongs_to :user
  has_one_attached :icon_image

  validates :source_path, presence: true, unless: :default_folder?
  validates :relative_path, presence: true, unless: :root_or_default?
  validates :entry_type, inclusion: { in: ENTRY_TYPES }
  validates :icon_kind, inclusion: { in: ICON_KINDS }
  validates :emoji, length: { maximum: 24 }, allow_blank: true
  validates :relative_path,
            uniqueness: { scope: [:user_id, :source_path, :entry_type] }
  validate :image_icon_is_an_image

  scope :for_source, ->(path) { where(source_path: normalize_source_path(path)) }

  class << self
    def default_folder_for(user)
      user.kb_entry_preferences.find_or_initialize_by(
        source_path: DEFAULT_SOURCE_PATH,
        relative_path: DEFAULT_RELATIVE_PATH,
        entry_type: DEFAULT_ENTRY_TYPE
      )
    end

    def find_or_initialize_entry(user:, source_path:, relative_path:, entry_type:)
      user.kb_entry_preferences.find_or_initialize_by(
        source_path: normalize_source_path(source_path),
        relative_path: normalize_relative_path(relative_path),
        entry_type: entry_type.to_s
      )
    end

    def move_subtree!(user:, source_path:, old_relative_path:, new_source_path:, new_relative_path:)
      old_source = normalize_source_path(source_path)
      new_source = normalize_source_path(new_source_path)
      old_rel = normalize_relative_path(old_relative_path)
      new_rel = normalize_relative_path(new_relative_path)

      matching_subtree(user, old_source, old_rel).order(:id).find_each do |preference|
        suffix = preference.relative_path.delete_prefix(old_rel).delete_prefix("/")
        moved_rel = suffix.present? ? File.join(new_rel, suffix) : new_rel
        conflict = user.kb_entry_preferences.find_by(
          source_path: new_source,
          relative_path: moved_rel,
          entry_type: preference.entry_type
        )
        conflict&.destroy! unless conflict == preference
        preference.update!(source_path: new_source, relative_path: moved_rel)
      end
    end

    def delete_subtree!(user:, source_path:, relative_path:)
      matching_subtree(user, normalize_source_path(source_path), normalize_relative_path(relative_path)).destroy_all
    end

    def normalize_source_path(path)
      return DEFAULT_SOURCE_PATH if path.blank?

      File.expand_path(path.to_s)
    end

    def normalize_relative_path(path)
      path.to_s.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
    end

    private

    def matching_subtree(user, source_path, relative_path)
      escaped = sanitize_sql_like(relative_path)
      user.kb_entry_preferences.where(source_path: source_path)
          .where("relative_path = ? OR relative_path LIKE ?", relative_path, "#{escaped}/%")
    end
  end

  def default_folder?
    entry_type == DEFAULT_ENTRY_TYPE
  end

  def root_or_default?
    entry_type == "root" || default_folder?
  end

  def custom_icon?
    (icon_kind == "emoji" && emoji.present?) || (icon_kind == "image" && icon_image.attached?)
  end

  def set_icon!(kind:, emoji: nil, image: nil)
    kind = kind.to_s
    raise ArgumentError, "Unsupported icon type" unless ICON_KINDS.include?(kind)

    transaction do
      case kind
      when "emoji"
        icon_image.purge if icon_image.attached?
        update!(icon_kind: "emoji", emoji: emoji.to_s.strip.presence || "📁")
      when "image"
        raise ArgumentError, "Choose an image first" if image.blank?

        icon_image.purge if icon_image.attached?
        icon_image.attach(image)
        update!(icon_kind: "image", emoji: nil)
      else
        icon_image.purge if icon_image.attached?
        update!(icon_kind: "default", emoji: nil)
      end
    end
  end

  private

  def image_icon_is_an_image
    return unless icon_image.attached?
    return if icon_image.blob.content_type.to_s.start_with?("image/")

    errors.add(:icon_image, "must be an image")
  end
end
