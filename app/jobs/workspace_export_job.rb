class WorkspaceExportJob < ApplicationJob
  queue_as :default

  def perform(export_job, password = nil)
    export_job.update!(status: :processing, progress: 0)
    
    begin
      # Create temporary directory for export
      temp_dir = Rails.root.join('tmp', 'exports', export_job.id.to_s)
      FileUtils.mkdir_p(temp_dir)
      
      # Export database data
      export_job.update_progress!(10)
      export_database_data(export_job.user, temp_dir)
      
      # Export files
      export_job.update_progress!(30)
      export_files(export_job.user, temp_dir)
      
      # Create manifest and documentation
      export_job.update_progress!(60)
      create_manifest(export_job.user, temp_dir)
      create_readme(temp_dir)
      
      # Package the export
      export_job.update_progress!(80)
      final_path = package_export(temp_dir, password.present?)
      
      # Encrypt if password provided
      if password.present?
        export_job.update_progress!(90)
        final_path = encrypt_export(final_path, password)
      end
      
      # Complete the export
      export_job.complete!(final_path)
      
      # Cleanup temporary directory
      FileUtils.rm_rf(temp_dir)
      
    rescue => e
      Rails.logger.error "Export job #{export_job.id} failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      export_job.fail!(e.message)
      
      # Cleanup on failure
      FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
    end
  end

  private

  def export_database_data(user, temp_dir)
    data = {
      export_info: {
        version: "1.0",
        exported_at: Time.current.iso8601,
        user_email: user.email,
        user_name: user.name
      },
      user: user_data(user),
      lists: lists_data(user),
      ideas: ideas_data(user),
      versions: versions_data(user),
      templates: templates_data(user)
    }
    
    File.write(
      temp_dir.join('data.json'),
      JSON.pretty_generate(data)
    )
  end

  def user_data(user)
    {
      id: user.id,
      email: user.email,
      name: user.name,
      settings: user.settings,
      created_at: user.created_at.iso8601,
      updated_at: user.updated_at.iso8601
    }
  end

  def lists_data(user)
    user.lists.order(:position).map do |list|
      {
        id: list.id,
        name: list.name,
        position: list.position,
        created_at: list.created_at.iso8601,
        updated_at: list.updated_at.iso8601,
        idea_ids: list.ideas.pluck(:id)
      }
    end
  end

  def ideas_data(user)
    user.ideas.includes(:template, :versions, :topologies, hero_image_attachment: :blob, attachments_attachments: :blob).map do |idea|
      {
        id: idea.id,
        title: idea.title,
        state: idea.state,
        topology_ids: idea.topology_ids,
        topology_names: idea.topologies.pluck(:name),
        trl: idea.trl,
        difficulty: idea.difficulty,
        opportunity: idea.opportunity,
        timing: idea.timing,
        computed_score: idea.computed_score,
        attempt_count: idea.attempt_count,
        cool_off_until: idea.cool_off_until&.iso8601,
        metadata: idea.metadata,
        template_id: idea.template_id,
        description: idea.description.to_plain_text,
        hero_image: attachment_data(idea.hero_image),
        attachments: idea.attachments.map { |attachment| attachment_data(attachment) },
        created_at: idea.created_at.iso8601,
        updated_at: idea.updated_at.iso8601,
        list_memberships: idea.idea_lists.map do |idea_list|
          {
            list_id: idea_list.list_id,
            position: idea_list.position
          }
        end
      }
    end
  end

  def versions_data(user)
    Version.joins(:idea).where(ideas: { user: user }).includes(:idea).map do |version|
      {
        id: version.id,
        idea_id: version.idea_id,
        parent_version_id: version.parent_version_id,
        commit_message: version.commit_message,
        snapshot_data: version.snapshot_data,
        diff_summary: version.diff_summary,
        created_at: version.created_at.iso8601,
        updated_at: version.updated_at.iso8601
      }
    end
  end

  def templates_data(user)
    user.templates.map do |template|
      {
        id: template.id,
        name: template.name,
        is_default: template.is_default,
        field_definitions: template.field_definitions,
        section_order: template.section_order,
        created_at: template.created_at.iso8601,
        updated_at: template.updated_at.iso8601
      }
    end
  end

  def attachment_data(attachment)
    return nil unless attachment.attached?
    
    {
      filename: attachment.filename.to_s,
      content_type: attachment.content_type,
      byte_size: attachment.byte_size,
      checksum: attachment.checksum,
      key: attachment.key
    }
  end

  def export_files(user, temp_dir)
    files_dir = temp_dir.join('files')
    FileUtils.mkdir_p(files_dir)
    
    # Export all attachments for user's ideas
    user.ideas.each do |idea|
      export_idea_files(idea, files_dir)
    end
  end

  def export_idea_files(idea, files_dir)
    # Export hero image
    if idea.hero_image.attached?
      export_attachment(idea.hero_image, files_dir)
    end
    
    # Export attachments
    idea.attachments.each do |attachment|
      export_attachment(attachment, files_dir)
    end
  end

  def export_attachment(attachment, files_dir)
    return unless attachment.attached?
    
    # Create subdirectory based on attachment key for organization
    key_dir = files_dir.join(attachment.key[0..1])
    FileUtils.mkdir_p(key_dir)
    
    # Copy the file
    source_path = attachment.blob.service.path_for(attachment.key)
    dest_path = key_dir.join(attachment.key)
    
    if File.exist?(source_path)
      FileUtils.cp(source_path, dest_path)
    end
  end

  def create_manifest(user, temp_dir)
    manifest = {
      format_version: "1.0",
      export_type: "idea_foundry_workspace",
      exported_at: Time.current.iso8601,
      user_email: user.email,
      statistics: {
        ideas_count: user.ideas.count,
        lists_count: user.lists.count,
        versions_count: Version.joins(:idea).where(ideas: { user: user }).count,
        templates_count: user.templates.count,
        attachments_count: count_user_attachments(user)
      },
      files: {
        database: "data.json",
        attachments_directory: "files/",
        readme: "README_IMPORT.md"
      }
    }
    
    File.write(
      temp_dir.join('manifest.json'),
      JSON.pretty_generate(manifest)
    )
  end

  def count_user_attachments(user)
    count = 0
    user.ideas.each do |idea|
      count += 1 if idea.hero_image.attached?
      count += idea.attachments.count
    end
    count
  end

  def create_readme(temp_dir)
    readme_content = <<~README
      # Idea Foundry Export

      This archive contains a complete export of your Idea Foundry workspace.

      ## Contents

      - `manifest.json` - Export metadata and file inventory
      - `data.json` - Complete database export in JSON format
      - `files/` - Directory containing all uploaded files and attachments
      - `README_IMPORT.md` - This file

      ## Import Instructions

      To import this data into a new Idea Foundry instance:

      1. Ensure you have a fresh Idea Foundry installation
      2. Create a new user account with the same email address
      3. Use the import functionality in the application settings
      4. Upload this entire archive

      ## Data Structure

      The `data.json` file contains:
      - User profile and settings
      - All ideas with their content and metadata
      - List organization and positioning
      - Complete version history
      - Custom templates
      - File attachment references

      ## File Organization

      Files are organized in the `files/` directory using the same key-based
      structure as Active Storage. Each file is stored using its unique key
      for reliable restoration.

      ## Security Note

      This export may contain sensitive information. Store it securely and
      delete it when no longer needed.

      ## Export Details

      - Export Format Version: 1.0
      - Exported At: #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')}
      - Application: Idea Foundry
    README

    File.write(temp_dir.join('README_IMPORT.md'), readme_content)
  end

  def package_export(temp_dir, will_encrypt = false)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    output_dir = Rails.root.join('exports', 'backup')
    FileUtils.mkdir_p(output_dir)

    if will_encrypt
      # Create ZIP for encryption
      zip_path = Rails.root.join('exports', 'backup', "export_#{timestamp}.zip")
      
      Zip::File.open(zip_path, Zip::File::CREATE) do |zipfile|
        Dir.glob(File.join(temp_dir, '**', '*')).each do |file|
          next if File.directory?(file)
          
          relative_path = file.sub("#{temp_dir}/", '')
          zipfile.add(relative_path, file)
        end
      end
      
      zip_path.to_s
    else
      # Create tar.gz
      tar_path = Rails.root.join('exports', 'backup', "export_#{timestamp}.tar.gz")
      
      system("cd #{temp_dir} && tar -czf #{tar_path} .")
      
      tar_path.to_s
    end
  end

  def encrypt_export(file_path, password)
    encrypted_path = file_path.sub(/\.(zip|tar\.gz)$/, '_encrypted.zip')
    
    # Use rubyzip with encryption
    Zip::File.open(encrypted_path, Zip::File::CREATE) do |zipfile|
      zipfile.encryption_level = 1  # Standard encryption
      zipfile.password = password
      
      filename = File.basename(file_path)
      zipfile.add(filename, file_path)
    end
    
    # Remove unencrypted file
    File.delete(file_path)
    
    encrypted_path
  end
end