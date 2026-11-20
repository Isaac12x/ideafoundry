# Shared by Notification and TodoItem: an item is general (no idea, no project), per idea, or per KB project.
module NotificationScope
  extend ActiveSupport::Concern

  included do
    scope :general, -> { where(idea_id: nil, project_path: nil) }
    scope :for_project, ->(src, path) { where(project_src: src.to_s, project_path: path.to_s) }
  end

  class_methods do
    # scope: :general | Idea | { src:, path: } (KB project)
    def scope_attributes(scope)
      case scope
      when Idea then { idea_id: scope.id }
      when Hash then { project_src: scope[:src].to_s, project_path: scope[:path].to_s }
      else {}
      end
    end

    # "all" | "general" | "idea" | "project"
    def in_scope_kind(kind)
      case kind.to_s
      when "general" then general
      when "idea" then where.not(idea_id: nil)
      when "project" then where.not(project_path: nil)
      else all
      end
    end
  end

  def scope_label
    return idea&.title.presence || "Idea" if idea_id
    return File.basename(project_path) if project_path.present?

    "General"
  end
end
