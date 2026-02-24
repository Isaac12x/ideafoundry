class ExportJob < ApplicationRecord
  belongs_to :user

  # Status enum
  enum :status, {
    pending: 0,
    processing: 1,
    completed: 2,
    failed: 3
  }

  # Kind enum
  enum :kind, { export: 0, backup: 1 }

  # Scopes by kind
  scope :exports, -> { where(kind: :export) }
  scope :backups, -> { where(kind: :backup) }

  # Validations
  validates :progress, presence: true, inclusion: { in: 0..100 }
  validates :status, presence: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }

  # Callbacks
  before_create :set_defaults

  def start_export!(password = nil)
    update!(
      status: :pending,
      progress: 0,
      password_protected: password.present?,
      error_message: nil
    )

    WorkspaceExportJob.perform_later(self, password)
  end

  def update_progress!(progress_value)
    update!(progress: [0, [progress_value, 100].min].max)
  end

  def complete!(file_path)
    update!(
      status: :completed,
      progress: 100,
      file_path: file_path
    )
  end

  def fail!(error_message)
    update!(
      status: :failed,
      error_message: error_message
    )
  end

  def file_exists?
    file_path.present? && File.exist?(file_path)
  end

  def file_size
    return 0 unless file_exists?
    File.size(file_path)
  end

  def file_size_human
    return "0 B" unless file_exists?
    
    size = file_size
    units = %w[B KB MB GB TB]
    unit_index = 0
    
    while size >= 1024 && unit_index < units.length - 1
      size /= 1024.0
      unit_index += 1
    end
    
    "#{size.round(1)} #{units[unit_index]}"
  end

  def download_filename
    return nil unless completed? && file_path.present?
    
    timestamp = created_at.strftime("%Y%m%d_%H%M%S")
    extension = password_protected? ? ".zip" : ".tar.gz"
    "idea_foundry_export_#{timestamp}#{extension}"
  end

  def cleanup_file!
    return unless file_path.present? && File.exist?(file_path)
    
    File.delete(file_path)
    update!(file_path: nil)
  end

  def duration
    return nil unless completed? || failed?
    
    end_time = updated_at
    start_time = created_at
    end_time - start_time
  end

  def duration_human
    return nil unless duration
    
    seconds = duration.to_i
    if seconds < 60
      "#{seconds}s"
    elsif seconds < 3600
      minutes = seconds / 60
      remaining_seconds = seconds % 60
      "#{minutes}m #{remaining_seconds}s"
    else
      hours = seconds / 3600
      remaining_minutes = (seconds % 3600) / 60
      "#{hours}h #{remaining_minutes}m"
    end
  end

  private

  def set_defaults
    self.status ||= :pending
    self.progress ||= 0
    self.password_protected ||= false
  end
end
