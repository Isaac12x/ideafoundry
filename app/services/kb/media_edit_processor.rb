require "digest"
require "fileutils"
require "open3"
require "securerandom"

module Kb
  class MediaEditProcessor
    class Error < StandardError; end

    VIDEO_CODECS = {
      ".mp4" => %w[-c:v libx264 -preset medium -crf 20 -c:a aac -b:a 192k -movflags +faststart],
      ".mov" => %w[-c:v libx264 -preset medium -crf 20 -c:a aac -b:a 192k -movflags +faststart],
      ".webm" => %w[-c:v libvpx-vp9 -crf 30 -b:v 0 -c:a libopus -b:a 160k],
      ".ogv" => %w[-c:v libtheora -q:v 7 -c:a libvorbis -q:a 5]
    }.freeze
    AUDIO_CODECS = {
      ".mp3" => %w[-c:a libmp3lame -q:a 2],
      ".wav" => %w[-c:a pcm_s16le],
      ".ogg" => %w[-c:a libvorbis -q:a 6],
      ".m4a" => %w[-c:a aac -b:a 192k -movflags +faststart],
      ".aac" => %w[-c:a aac -b:a 192k],
      ".flac" => %w[-c:a flac]
    }.freeze
    PDF_QUALITY = { "screen" => "/screen", "ebook" => "/ebook", "print" => "/printer" }.freeze

    def initialize(path:, source_root:, operations:, replacement_path: nil, runner: Open3.method(:capture3))
      @path = File.expand_path(path)
      @source_root = File.expand_path(source_root)
      @operations = operations.to_h.stringify_keys
      @replacement_path = replacement_path
      @runner = runner
    end

    def call
      validate_source!
      original_sha = sha256(path)
      temporary = temporary_path

      replacement_path.present? ? copy_replacement(temporary) : process_media(temporary)
      raise Error, "The editor produced an empty file." unless File.file?(temporary) && File.size(temporary).positive?

      revision = preserve_revision(original_sha)
      File.chmod(File.stat(path).mode & 0o777, temporary)
      File.rename(temporary, path)

      {
        original_sha256: original_sha,
        result_sha256: sha256(path),
        revision_path: revision.delete_prefix("#{source_root}/")
      }
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    private

    attr_reader :path, :source_root, :operations, :replacement_path, :runner

    def validate_source!
      unless path.start_with?("#{source_root}/") && File.file?(path)
        raise Error, "The source file is no longer available."
      end

      current = source_root
      path.delete_prefix("#{source_root}/").split("/").each do |segment|
        current = File.join(current, segment)
        raise Error, "Symbolic links cannot be edited." if File.symlink?(current)
      end
    end

    def temporary_path
      extension = File.extname(path)
      File.join(File.dirname(path), ".#{File.basename(path, extension)}.editing-#{SecureRandom.hex(8)}#{extension}")
    end

    def copy_replacement(destination)
      raise Error, "The replacement file is unavailable." unless File.file?(replacement_path)

      FileUtils.copy_file(replacement_path, destination)
    end

    def process_media(destination)
      case MediaTypes.kind_for(path)
      when :video then transcode(destination, video: true)
      when :audio then transcode(destination, video: false)
      when :pdf then edit_pdf(destination)
      else raise Error, "This format needs a replacement file to save edits."
      end
    end

    def transcode(destination, video:)
      info = MediaInspector.new(path, runner: runner).call
      duration = info[:duration].to_f
      raise Error, "Could not read the media duration." unless duration.positive?

      start_at = decimal("trim_start", 0.0, min: 0.0, max: duration)
      finish_at = decimal("trim_end", duration, min: 0.0, max: duration)
      raise Error, "The out point must be after the in point." unless finish_at > start_at

      speed = decimal("speed", 1.0, min: 0.5, max: 2.0)
      edited_duration = (finish_at - start_at) / speed
      # -t is deliberately an input option (before -i). As an output option it
      # would truncate slowed-down media before atempo/setpts can extend it.
      command = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-ss", number(start_at),
                 "-t", number(finish_at - start_at), "-i", path, "-map_metadata", "0"]

      if video
        video_filters = build_video_filters(speed, edited_duration)
        audio_filters = build_audio_filters(speed, edited_duration)
        command.concat(["-map", "0:v:0", "-map", "0:a?"])
        command.concat(["-vf", video_filters.join(",")]) if video_filters.any?
        if truthy?("mute")
          command << "-an"
        elsif audio_filters.any? && info[:has_audio]
          command.concat(["-af", audio_filters.join(",")])
        end
        command.concat(VIDEO_CODECS.fetch(File.extname(path).downcase))
      else
        audio_filters = build_audio_filters(speed, edited_duration)
        command << "-vn"
        command.concat(["-af", audio_filters.join(",")]) if audio_filters.any?
        command.concat(["-ac", "1"]) if truthy?("mono")
        command.concat(AUDIO_CODECS.fetch(File.extname(path).downcase))
      end

      command << destination
      run!(*command)
    end

    def build_video_filters(speed, duration)
      filters = []
      crop = operations["crop_aspect"].to_s
      filters << "crop=min(iw\\,ih*16/9):min(ih\\,iw*9/16)" if crop == "16:9"
      filters << "crop=min(iw\\,ih*9/16):min(ih\\,iw*16/9)" if crop == "9:16"
      filters << "crop=min(iw\\,ih):min(ih\\,iw)" if crop == "1:1"
      filters << "crop=min(iw\\,ih*4/3):min(ih\\,iw*3/4)" if crop == "4:3"

      case operations["rotate"].to_s
      when "90" then filters << "transpose=1"
      when "180" then filters.concat(%w[transpose=1 transpose=1])
      when "270" then filters << "transpose=2"
      end
      filters << "hflip" if truthy?("flip_horizontal")
      filters << "vflip" if truthy?("flip_vertical")

      brightness = decimal("brightness", 0.0, min: -1.0, max: 1.0)
      contrast = decimal("contrast", 1.0, min: 0.0, max: 2.0)
      saturation = decimal("saturation", 1.0, min: 0.0, max: 3.0)
      if brightness != 0.0 || contrast != 1.0 || saturation != 1.0
        filters << "eq=brightness=#{number(brightness)}:contrast=#{number(contrast)}:saturation=#{number(saturation)}"
      end
      filters << "hue=s=0" if truthy?("grayscale")

      height = { "1080" => 1080, "720" => 720, "480" => 480 }[operations["resolution"].to_s]
      filters << "scale=-2:#{height}" if height
      filters << "setpts=PTS/#{number(speed)}" if speed != 1.0
      filters.concat(fade_filters("fade", duration))
      filters
    end

    def build_audio_filters(speed, duration)
      filters = []
      filters << "atempo=#{number(speed)}" if speed != 1.0
      filters << "volume=#{number(decimal('volume', 1.0, min: 0.0, max: 2.0))}"
      filters << "loudnorm=I=-16:LRA=11:TP=-1.5" if truthy?("normalize")
      filters.concat(fade_filters("afade", duration))
      filters
    end

    def fade_filters(filter_name, duration)
      fade_in = decimal("fade_in", 0.0, min: 0.0, max: duration)
      fade_out = decimal("fade_out", 0.0, min: 0.0, max: duration)
      result = []
      result << "#{filter_name}=t=in:st=0:d=#{number(fade_in)}" if fade_in.positive?
      result << "#{filter_name}=t=out:st=#{number([duration - fade_out, 0].max)}:d=#{number(fade_out)}" if fade_out.positive?
      result
    end

    def edit_pdf(destination)
      sequence = operations["page_sequence"].to_s.strip.presence || "1-end"
      unless sequence.match?(/\A(?:\d+|end)(?:-(?:\d+|end))?(?:\s+(?:\d+|end)(?:-(?:\d+|end))?)*\z/i)
        raise Error, "Page sequence must look like “1-3 5 8-end”."
      end

      rotation = { "90" => "right", "180" => "south", "270" => "left" }[operations["pdf_rotation"].to_s]
      pages = sequence.split.map { |part| rotation ? "#{part}#{rotation}" : part }
      intermediate = PDF_QUALITY.key?(operations["pdf_quality"].to_s) ? "#{destination}.pages.pdf" : destination
      run!("pdftk", path, "cat", *pages, "output", intermediate, "compress")

      quality = PDF_QUALITY[operations["pdf_quality"].to_s]
      return unless quality

      run!("gs", "-q", "-dNOPAUSE", "-dBATCH", "-dSAFER", "-sDEVICE=pdfwrite",
           "-dPDFSETTINGS=#{quality}", "-sOutputFile=#{destination}", intermediate)
      FileUtils.rm_f(intermediate)
    ensure
      FileUtils.rm_f(intermediate) if defined?(intermediate) && intermediate.present? && intermediate != destination
    end

    def preserve_revision(original_sha)
      relative_directory = File.dirname(path.delete_prefix("#{source_root}/"))
      relative_directory = nil if relative_directory == "."
      history = File.join(source_root, ".ideafoundry-history", *[relative_directory, File.basename(path)].compact)
      FileUtils.mkdir_p(history)
      extension = File.extname(path)
      stem = File.basename(path, extension)
      revision = File.join(history, "#{Time.current.utc.strftime('%Y%m%dT%H%M%S.%6NZ')}-#{stem}-#{original_sha.first(12)}#{extension}")
      FileUtils.copy_file(path, revision)
      revision
    end

    def sha256(file)
      Digest::SHA256.file(file).hexdigest
    end

    def decimal(key, default, min:, max:)
      Float(operations[key].presence || default).clamp(min, max)
    rescue ArgumentError, TypeError
      default
    end

    def truthy?(key)
      ActiveModel::Type::Boolean.new.cast(operations[key])
    end

    def number(value)
      format("%.4f", value).sub(/\.?0+\z/, "")
    end

    def run!(*command)
      _stdout, stderr, status = runner.call(*command)
      return if status.success?

      message = stderr.to_s.lines.last(8).join.strip.presence || "Local media tool failed."
      raise Error, message
    rescue Errno::ENOENT => error
      raise Error, "Required local editor #{error.message.split(' - ').last} is not installed."
    end
  end
end
