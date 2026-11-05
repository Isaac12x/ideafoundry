# Data for kb/_related: peers of one KB entry, with where each lives and whether it still exists.
module KbRelatedHelper
  RelatedPeer = Struct.new(:link, :rel, :src, :kind, keyword_init: true) # kind: :missing, :file or :dir

  def kb_related_peers(src, rel)
    sources = KbSource.list(@user)
    return [] unless sources[src]

    bases = sources.map { |s| File.expand_path(s[:path]) }
    KbLink.related_to(@user, bases[src], rel).map do |peer_base, peer_rel, link|
      peer_src = bases.index(peer_base)
      abs = File.join(peer_base, peer_rel)
      kind = peer_src.nil? || !File.exist?(abs) ? :missing : (File.file?(abs) ? :file : :dir)
      RelatedPeer.new(link: link, rel: peer_rel, src: peer_src, kind: kind)
    end
  end

  # Parent folder name shown muted after a chip's name, to tell same-named files apart.
  def kb_related_where(rel)
    dir = File.dirname(rel)
    File.basename(dir) unless dir == "."
  end
end
