# Resolves ?src=&file= to a regular, symlink-free file inside a configured KB source.
module KbFileLookup
  extend ActiveSupport::Concern

  private

  # => { root:, rel:, abs: } or nil
  def locate_kb_file
    index = params[:src].to_i
    source = KbSource.list(@user)[index] unless index.negative?
    rel = KbEntryPreference.normalize_relative_path(params[:file])
    return if source.nil? || rel.blank?

    root = File.expand_path(source[:path])
    abs = File.expand_path(File.join(root, rel))
    return unless abs.start_with?("#{root}/") && File.file?(abs)

    current = root
    return if rel.split("/").any? { |segment| File.symlink?(current = File.join(current, segment)) }

    { root: root, rel: rel, abs: abs, src: index }
  end

  def private_kb_file?(located) = Kb::Privacy.private?(located[:root], located[:rel])
end
