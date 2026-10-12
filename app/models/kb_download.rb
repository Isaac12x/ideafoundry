# A pending/running background download into a KB folder, created when a user
# "creates a file" whose name is a URL. KbDownloadJob does the fetching; status
# changes broadcast a tree row via Turbo so the sidebar updates live.
#
# Web pages are saved as reader-mode PDFs. When the page cites sources, a
# picker dialog pops up on the KB page asking which to pull
# (references_state "offered" -> "pulled" | "dismissed"). Picking any moves the
# page into a "{title}/" folder, with the references in "{title}/{title}-references/".
class KbDownload < ApplicationRecord
  belongs_to :user
  has_many :media_digests, dependent: :destroy

  STATUSES = %w[pending running done failed].freeze
  FORMATS  = %w[auto page video audio].freeze
  VIDEO_EXTS = %w[.mp4 .webm .mov .ogv .mkv .m4v].freeze

  serialize :reference_list, coder: JSON, type: Array

  validates :url, presence: true, format: { with: %r{\Ahttps?://\S+\z}i }
  validates :status, inclusion: { in: STATUSES }
  validates :format, inclusion: { in: FORMATS }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[pending running]) }
  # A worker that dies mid-fetch leaves the row "running" forever, and every
  # spinner row keeps the sidebar polling. ponytail: age cutoff, no heartbeat;
  # add one if fetches legitimately run longer than this.
  scope :in_tree, -> { active.where(updated_at: 6.hours.ago..) }
  scope :transcribed, -> { where(transcript_status: "done") }
  scope :references_pending, -> { where(status: "done", references_state: "offered").order(:created_at) }

  after_create_commit :broadcast_tree
  after_update_commit :broadcast_tree, if: -> { saved_change_to_status? || saved_change_to_references_state? }
  after_update_commit :broadcast_references_prompt, if: -> { saved_change_to_status? && references_offered? }

  # Create the record and enqueue the fetch. dir is relative to the source root.
  def self.enqueue(user:, source_index:, dir:, url:, format: "auto", **extra)
    source = KbSource.list(user)[source_index]
    raise ArgumentError, "KB source is not available" unless source

    download = user.kb_downloads.create!(
      source_index: source_index,
      source_path: File.expand_path(source[:path]),
      dir: dir.to_s,
      url: url.to_s.strip,
      format: FORMATS.include?(format.to_s) ? format.to_s : "auto",
      status: "pending",
      **extra.slice(:archive_url, :references_state)
    )
    KbDownloadJob.perform_later(download.id)
    download
  end

  # Page title -> safe single path segment.
  def self.safe_name(title)
    name = title.to_s.gsub(%r{[/\\:\0]}, "-").gsub(/[[:cntrl:]]/, "").squish.sub(/\A\.+/, "")
    name.truncate(120, omission: "").strip.presence || "page"
  end

  def done?   = status == "done"
  def failed? = status == "failed"
  def youtube? = KbDownloadJob.youtube?(url)
  def video? = youtube? || VIDEO_EXTS.include?(File.extname(filename.to_s).downcase)

  # Captions via KbTranscriptJob; a direct video file has none, so it goes straight
  # to the future audio service.
  def queue_transcript
    return unless done? && video? && transcript_status.nil?

    if KbDownloadJob.direct_file?(url)
      update!(transcript_status: "awaiting_audio")
    else
      update!(transcript_status: "pending")
      KbTranscriptJob.perform_later(id)
    end
  end

  def references_offered? = done? && references_state == "offered"

  # Path of the finished file relative to its source root (for kb_file links).
  def file_rel
    return nil if filename.blank?
    dir.present? ? File.join(dir, filename) : filename
  end

  def label = filename.presence || url

  def references_folder = "#{self.class.safe_name(title.presence || File.basename(filename.to_s, '.*'))}-references"

  def references_dir = [dir.presence, references_folder].compact.join("/")

  # Moves the page into its own "{title}/" folder and queues the chosen
  # references (by URL) into "{title}/{title}-references/". Returns the number queued.
  def pull_references!(urls)
    chosen = reference_list.select { |ref| urls.include?(ref["url"]) }
    return 0 if chosen.empty?

    base = File.expand_path(source_path)
    move_into_own_folder!(base)
    target = File.expand_path(File.join(base, references_dir))
    raise ArgumentError, "Invalid references folder" unless target.start_with?("#{base}/")
    FileUtils.mkdir_p(target)

    chosen.each do |ref|
      self.class.enqueue(user: user, source_index: source_index, dir: references_dir, url: ref["url"],
                         format: "page", archive_url: ref["archive"], references_state: "skip")
    end
    update!(references_state: "pulled")
    chosen.size
  end

  private

  def broadcast_tree
    Kb::TreeBroadcaster.call(user)
  end

  def broadcast_references_prompt
    broadcast_append_later_to [user, "kb_tree"], target: "kb-references-prompts", partial: "kb_references/picker",
                              locals: { download: self }
  end

  # ponytail: a file missing on disk (deleted/renamed meanwhile) stays put;
  # the references still land next to where it was.
  def move_into_own_folder!(base)
    file = File.expand_path(File.join(base, file_rel.to_s))
    return unless filename.present? && File.file?(file) && file.start_with?("#{base}/")

    folder = File.join(File.dirname(file), self.class.safe_name(title.presence || File.basename(filename, ".*")))
    folder = "#{folder}-#{SecureRandom.hex(2)}" if File.exist?(folder)
    FileUtils.mkdir_p(folder)
    FileUtils.mv(file, folder)
    update!(dir: folder.delete_prefix("#{base}/"))
  end
end
