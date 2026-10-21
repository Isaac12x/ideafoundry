# Link from an idea to a KB file, folder or project (created from the idea page).
class IdeaKbLink < ApplicationRecord
  ENTRY_TYPES = %w[file dir project].freeze

  belongs_to :idea

  before_validation { self.source_path = self.class.normalize_source_path(source_path) }
  before_validation { self.relative_path = self.class.normalize_relative_path(relative_path) }

  validates :source_path, presence: true
  validates :entry_type, inclusion: { in: ENTRY_TYPES }
  validates :relative_path, uniqueness: { scope: [ :idea_id, :source_path ] }

  class << self
    # { rel:, type: } for an existing, non-hidden, symlink-free entry inside base, else nil.
    def resolve_entry(base, rel)
      rel = normalize_relative_path(rel)
      parts = rel.split("/")
      return if parts.empty? || parts.any? { |p| p.start_with?(".") || p == ".." }

      abs = File.expand_path(File.join(base, rel))
      return unless abs.start_with?("#{base}/")
      return if parts.each_with_index.any? { |_, i| File.symlink?(File.join(base, *parts.first(i + 1))) }
      return unless File.exist?(abs)

      type = Kb::Project.at(base, rel) ? "project" : (File.directory?(abs) ? "dir" : "file")
      { rel: rel, type: type }
    end

    # "src:path" picks (idea form) -> links; raises on any bad pick so callers roll back.
    def link_picks!(idea, user, picks)
      sources = KbSource.list(user)
      Array(picks).each do |pick|
        src, path = pick.to_s.split(":", 2)
        source = sources[src.to_i] if src.to_s.match?(/\A\d+\z/)
        entry = source && resolve_entry(File.expand_path(source[:path]), path)
        raise ActiveRecord::RecordInvalid, idea unless entry

        idea.kb_links.find_or_create_by!(source_path: source[:path], relative_path: entry[:rel]) do |link|
          link.entry_type = entry[:type]
          link.position = idea.kb_links.maximum(:position).to_i + 1
        end
      end
    end

    # Backlinks: links (across the user's ideas) pointing at this exact path.
    def for_path(user:, source_path:, relative_path:)
      joins(:idea).where(ideas: { user_id: user.id },
                         source_path: normalize_source_path(source_path),
                         relative_path: normalize_relative_path(relative_path))
    end

    def move_subtree!(user:, source_path:, old_relative_path:, new_source_path:, new_relative_path:)
      old_source = normalize_source_path(source_path)
      new_source = normalize_source_path(new_source_path)
      old_rel = normalize_relative_path(old_relative_path)
      new_rel = normalize_relative_path(new_relative_path)

      matching_subtree(user, old_source, old_rel).order(:id).find_each do |link|
        suffix = link.relative_path.delete_prefix(old_rel).delete_prefix("/")
        moved_rel = suffix.present? ? File.join(new_rel, suffix) : new_rel
        conflict = where(idea_id: link.idea_id, source_path: new_source, relative_path: moved_rel).where.not(id: link.id).first
        conflict&.destroy!
        link.update!(source_path: new_source, relative_path: moved_rel)
      end
    end

    def delete_subtree!(user:, source_path:, relative_path:)
      matching_subtree(user, normalize_source_path(source_path), normalize_relative_path(relative_path)).destroy_all
    end

    def normalize_source_path(path)
      path.blank? ? "" : File.expand_path(path.to_s)
    end

    def normalize_relative_path(path)
      path.to_s.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
    end

    private

    def matching_subtree(user, source_path, relative_path)
      escaped = sanitize_sql_like(relative_path)
      joins(:idea).where(ideas: { user_id: user.id }, source_path: source_path)
                  .where("idea_kb_links.relative_path = ? OR idea_kb_links.relative_path LIKE ?", relative_path, "#{escaped}/%")
    end
  end
end
