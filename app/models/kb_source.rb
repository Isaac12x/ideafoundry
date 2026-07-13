# Ordered list of KB sources for a user: the native App KB, configured folders,
# and mounted drives (network shares / external volumes). Shared by KbController
# and KbDownloadJob so source_index -> path resolution never drifts.
class KbSource
  NATIVE_PATH  = Rails.root.join("storage", "kb").to_s.freeze
  NATIVE_LABEL = "App KB".freeze

  def self.list(user)
    sources = []
    sources << source(NATIVE_PATH, native: true) unless user.kb_hide_native?
    user.kb_folders.each { |path| sources << source(path) }
    user.kb_drives.each  { |path| sources << source(path, drive: true) }
    sources
  end

  def self.source(path, native: false, drive: false, label: nil)
    { path: path, label: label || label_for(path), native: native, drive: drive }
  end

  def self.label_for(path)
    return NATIVE_LABEL if path == NATIVE_PATH
    File.basename(path.to_s.chomp(File::SEPARATOR)).presence || path.to_s
  end
end
