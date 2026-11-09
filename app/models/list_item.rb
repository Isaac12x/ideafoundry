# A non-idea entry of a named list: free text, an http(s) link, or an in-app path (e.g. a KB file).
# ponytail: KB entries are stored as a URL, so moving the file breaks the link; store src+path if that bites.
class ListItem < ApplicationRecord
  belongs_to :list

  validates :title, presence: true, length: { maximum: 500 }
  validates :position, presence: true
  validate :url_is_safe
  validate :list_is_named

  before_validation :set_position, on: :create

  # A trailing URL becomes the link and the text before it the title.
  def self.from_text(text)
    text = text.to_s.strip.first(501) # one over the cap so validation still rejects it
    m = text.match(%r{\A(.*?)\s*(https?://\S+)\z}i)
    m ? new(title: m[1].presence || m[2], url: m[2]) : new(title: text)
  end

  def internal?
    url.to_s.start_with?("/")
  end

  def host
    URI.parse(url).host unless url.blank? || internal?
  rescue URI::InvalidURIError
    nil
  end

  private

  def url_is_safe
    return if url.blank?
    return if url.match?(%r{\Ahttps?://}i) || url.match?(%r{\A/(?![/\\])})

    errors.add(:url, "must be an http(s) link or an app path")
  end

  def list_is_named
    errors.add(:list, "must be a named list") unless list&.named?
  end

  def set_position
    self.position ||= list.list_items.maximum(:position).to_i + 1 if list
  end
end
