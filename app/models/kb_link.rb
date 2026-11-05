# Alias ("also in") and related links between KB entries. Canonical bytes stay
# in one place; rows only point at them. See the migration for column meaning.
class KbLink < ApplicationRecord
  KINDS = %w[alias related].freeze

  belongs_to :user

  before_validation do
    self.source_path = self.class.normalize_source_path(source_path)
    self.peer_source_path = self.class.normalize_source_path(peer_source_path)
    self.relative_path = self.class.normalize_relative_path(relative_path)
    self.peer_relative_path = self.class.normalize_relative_path(peer_relative_path)
  end

  validates :kind, inclusion: { in: KINDS }
  validates :source_path, :peer_source_path, :relative_path, :peer_relative_path, presence: true
  validates :peer_relative_path, uniqueness: { scope: %i[user_id kind source_path relative_path peer_source_path] }
  validate :related_pair_is_new, if: -> { kind == "related" }

  scope :aliases, -> { where(kind: "alias") }
  scope :related, -> { where(kind: "related") }

  class << self
    # Aliases whose slot lives in this source.
    def aliases_in(user, source_path)
      user.kb_links.aliases.where(peer_source_path: normalize_source_path(source_path))
    end

    # [[peer_source_path, peer_relative_path, link], ...] for an entry, from either side.
    def related_to(user, source_path, relative_path)
      src = normalize_source_path(source_path)
      rel = normalize_relative_path(relative_path)
      user.kb_links.related.where(source_path: src, relative_path: rel).map { |l| [ l.peer_source_path, l.peer_relative_path, l ] } +
        user.kb_links.related.where(peer_source_path: src, peer_relative_path: rel).map { |l| [ l.source_path, l.relative_path, l ] }
    end

    # Rewrites every path under old_relative_path (either side of any link) to the new location.
    def move_subtree!(user:, source_path:, old_relative_path:, new_source_path:, new_relative_path:)
      old_source = normalize_source_path(source_path)
      new_source = normalize_source_path(new_source_path)
      old_rel = normalize_relative_path(old_relative_path)
      new_rel = normalize_relative_path(new_relative_path)

      touching(user, old_source, old_rel).order(:id).each do |link|
        link.remap!(old_source, old_rel, new_source, new_rel)
      end
    end

    # Alias slots and related links inside a deleted subtree go away; aliases whose
    # canonical entry was deleted stay, so they show as broken and can be removed.
    def delete_subtree!(user:, source_path:, relative_path:)
      src = normalize_source_path(source_path)
      rel = normalize_relative_path(relative_path)
      touching(user, src, rel).each do |link|
        link.destroy if link.kind == "related" || link.in_subtree?(link.peer_source_path, link.peer_relative_path, src, rel)
      end
    end

    def normalize_source_path(path)
      path.blank? ? "" : File.expand_path(path.to_s)
    end

    def normalize_relative_path(path)
      path.to_s.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
    end

    private

    def touching(user, source_path, relative_path)
      escaped = sanitize_sql_like(relative_path)
      like = "#{escaped}/%"
      user.kb_links.where(source_path: source_path).where("relative_path = ? OR relative_path LIKE ?", relative_path, like)
          .or(user.kb_links.where(peer_source_path: source_path).where("peer_relative_path = ? OR peer_relative_path LIKE ?", relative_path, like))
    end
  end

  def in_subtree?(src, rel, base_src, base_rel)
    src == base_src && (rel == base_rel || rel.start_with?("#{base_rel}/"))
  end

  def remap!(old_source, old_rel, new_source, new_rel)
    attrs = {}
    if in_subtree?(source_path, relative_path, old_source, old_rel)
      attrs[:source_path] = new_source
      attrs[:relative_path] = join(new_rel, relative_path.delete_prefix(old_rel))
    end
    if in_subtree?(peer_source_path, peer_relative_path, old_source, old_rel)
      attrs[:peer_source_path] = new_source
      attrs[:peer_relative_path] = join(new_rel, peer_relative_path.delete_prefix(old_rel))
    end
    update!(attrs)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    destroy # the moved link now duplicates an existing one
  end

  private

  def join(base, suffix)
    suffix = suffix.delete_prefix("/")
    suffix.empty? ? base : File.join(base, suffix)
  end

  def related_pair_is_new
    reverse = self.class.where(user_id: user_id, kind: "related", source_path: peer_source_path, relative_path: peer_relative_path,
                               peer_source_path: source_path, peer_relative_path: relative_path)
    errors.add(:base, "Already related") if reverse.where.not(id: id).exists?
    errors.add(:base, "Can't relate an entry to itself") if source_path == peer_source_path && relative_path == peer_relative_path
  end
end
