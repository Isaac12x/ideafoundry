# A pending/running background download into a KB folder, created when a user
# "creates a file" whose name is a URL. KbDownloadJob does the fetching; status
# changes broadcast a tree row via Turbo so the sidebar updates live.
#
# Web pages are saved as reader-mode PDFs. When the page cites sources, a
# toast offers the picker (it only opens by itself on that file's own page), asking which to pull
# (references_state "offered" -> "pulled" | "dismissed"). Picking any moves the
# page into a "{title}/" folder, with the references in "{title}/{title}-references/".
class KbDownload < ApplicationRecord
  belongs_to :user
  has_many :media_digests, dependent: :destroy

  STATUSES = %w[pending running done failed].freeze
  FORMATS  = %w[auto page video audio].freeze
  VIDEO_EXTS = %w[.mp4 .webm .mov .ogv .mkv .m4v .mpg .mpeg .avi .flv .wmv .3gp].freeze

  serialize :reference_list, coder: JSON, type: Array

  validates :url, presence: true, format: { with: %r{\Ahttps?://\S+\z}i }
  validates :status, inclusion: { in: STATUSES }
  validates :format, inclusion: { in: FORMATS }
  validate :clip_end_after_start
  validates :note, length: { maximum: 10_000 } # becomes the file's .note.md sidecar (Kb::Note)

  # Every intake path funnels through here: unwrap wrapper links first (http(s)
  # check runs after), then lift a start/end out of the URL unless set explicitly.
  before_validation :normalize_url
  before_validation :derive_clip, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[pending running]) }
  # A worker that dies mid-fetch leaves the row "running" forever, and every
  # spinner row keeps the sidebar polling. ponytail: age cutoff, no heartbeat;
  # add one if fetches legitimately run longer than this.
  scope :in_tree, -> { active.where(updated_at: 6.hours.ago..) }
  scope :transcribed, -> { where(transcript_status: "done") }
  scope :for_file, ->(index, rel) {
    dir = File.dirname(rel.to_s)
    where(status: "done", source_index: index, dir: dir == "." ? "" : dir, filename: File.basename(rel.to_s))
  }
  # Keeps rows pointing at their file after a rename/move of it or a parent folder,
  # so for_file never matches a stranger that later takes the old path.
  def self.move_subtree!(user:, source_index:, old_relative_path:, new_source_index:, new_relative_path:)
    old = old_relative_path.to_s
    where(user: user, source_index: source_index).find_each do |dl|
      rel = dl.file_rel or next
      next unless rel == old || rel.start_with?("#{old}/")

      new_rel = new_relative_path.to_s + rel.delete_prefix(old)
      dir = File.dirname(new_rel)
      dl.update_columns(source_index: new_source_index, dir: dir == "." ? "" : dir, filename: File.basename(new_rel))
    end
  end

  scope :references_pending, -> { where(status: "done", references_state: "offered").order(:created_at) }

  after_create_commit :broadcast_tree
  after_update_commit :broadcast_tree, if: -> { saved_change_to_status? || saved_change_to_references_state? }
  after_update_commit :broadcast_references_prompt, if: -> { saved_change_to_status? && references_offered? }

  # Create the record and enqueue the fetch. dir is relative to the source root.
  def self.enqueue(user:, source_index:, dir:, url:, format: "auto", clip_start: nil, clip_end: nil, note: nil, **extra)
    source = KbSource.list(user)[source_index]
    raise ArgumentError, "KB source is not available" unless source

    download = user.kb_downloads.create!(
      source_index: source_index,
      source_path: File.expand_path(source[:path]),
      dir: dir.to_s,
      url: url.to_s.strip,
      format: FORMATS.include?(format.to_s) ? format.to_s : "auto",
      status: "pending",
      clip_start: Kb::ClipTime.parse(clip_start), clip_end: Kb::ClipTime.parse(clip_end),
      note: note.to_s.strip.presence,
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

  # A saved web page with sources to pull, offered now or dismissed/ignored earlier.
  def references_pullable? = done? && references_state != "skip" && reference_list.any?

  def clip? = clip_start.present? || clip_end.present?

  # "5:54–7:10", "from 5:54", "to 7:10"
  def clip_label
    return unless clip?
    from = Kb::ClipTime.format(clip_start) if clip_start
    to = Kb::ClipTime.format(clip_end) if clip_end
    from && to ? "#{from}–#{to}" : from ? "from #{from}" : "to #{to}"
  end

  # Re-reads the page's citations when none were captured (older downloads).
  # Returns the list. ponytail: live fetch, no retry; empty on any failure.
  def extract_references!
    return reference_list if reference_list.any?

    page = Kb::WebPage.fetch(url)
    update!(reference_list: page.references, references_state: references_state || "dismissed") if page&.references&.any?
    reference_list
  rescue StandardError => e
    Rails.logger.info("KbDownload #{id} reference extract: #{e.message}")
    reference_list
  end

  # Path of the finished file relative to its source root (for kb_file links).
  def file_rel
    return nil if filename.blank?
    dir.present? ? File.join(dir, filename) : filename
  end

  # Absolute path of the finished file, or nil when it has none / escapes its source.
  # Folder is inside a project that is locking/unlocking or locked: don't write into it.
  def project_blocked? = source_path.present? && Kb::ProjectLock.write_block(source_path, dir).present?

  def file_abs
    return if filename.blank? || source_path.blank?

    base = File.expand_path(source_path)
    abs = File.expand_path(File.join(base, file_rel))
    abs if abs.start_with?("#{base}/") && File.file?(abs)
  end

  # Agent-facing reads (toolbox, work discovery) must skip downloads inside private projects.
  def private_project?
    file_rel.present? && source_path.present? && Kb::Privacy.private?(source_path, file_rel)
  end

  def label = filename.presence || url

  def references_folder = "#{self.class.safe_name(title.presence || File.basename(filename.to_s, '.*'))}-references"

  def references_dir = [ dir.presence, references_folder ].compact.join("/")

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

  def normalize_url
    self.url = Kb::UrlNormalizer.call(url) if url.present?
  end

  def derive_clip
    from, to = Kb::ClipTime.from_url(url)
    self.clip_start ||= from
    self.clip_end ||= to
  end

  def clip_end_after_start
    errors.add(:clip_end, "must be after the start") if clip_start && clip_end && clip_end <= clip_start
  end

  def broadcast_tree
    Kb::TreeBroadcaster.call(user)
  end

  def broadcast_references_prompt
    # Non-blocking toast: a modal here would hijack whatever page the user is on by now.
    broadcast_append_later_to [ user, "kb_tree" ], target: "kb-references-prompts", partial: "kb_references/toast",
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
