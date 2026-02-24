class VersionService
  attr_reader :idea

  def initialize(idea)
    @idea = idea
  end

  # Create a new version with automatic parent detection
  def create_version(commit_message)
    Version.create_from_idea(idea, commit_message)
  end

  # Create a version and update the idea in one transaction
  def save_with_version(attributes, commit_message)
    idea.transaction do
      idea.assign_attributes(attributes)
      idea.save!
      create_version(commit_message)
    end
  end

  # Get the complete version tree for visualization
  def version_tree
    root_versions = idea.versions.root_versions
    root_versions.map { |root| build_tree_node(root) }
  end

  # Compare two versions and return detailed diff
  def compare_versions(version_a, version_b)
    raise ArgumentError, "Versions must belong to this idea" unless versions_belong_to_idea?(version_a, version_b)
    
    version_b.diff_with(version_a)
  end

  # Restore a version and create a new branch
  def restore_version(version)
    raise ArgumentError, "Version does not belong to this idea" unless version.idea_id == idea.id

    version.restore_to_idea!
    true
  end

  # Get timeline of all versions with metadata
  def timeline
    idea.versions.chronological.map do |version|
      {
        id: version.id,
        commit_message: version.commit_message,
        created_at: version.created_at,
        parent_id: version.parent_version_id,
        has_branches: version.has_branches?,
        is_root: version.root?
      }
    end
  end

  private

  def build_tree_node(version)
    {
      version: version,
      children: version.child_versions.map { |child| build_tree_node(child) }
    }
  end

  def versions_belong_to_idea?(version_a, version_b)
    version_a.idea_id == idea.id && version_b.idea_id == idea.id
  end
end
