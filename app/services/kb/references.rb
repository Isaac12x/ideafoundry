require "erb"

module Kb
  # @-mention tokens stored in project text: @[Label](type:ref).
  #   idea:ID               an idea; an idea VERSION (v1, v2...) is its own Idea row, so the id pins the version
  #   maxim:ID fact:ID problem:ID
  #   kb:SRC:KIND:ENCPATH   a KB file/folder/project (KIND file|dir|project, path percent-encoded)
  # Rendering turns tokens into chips (<a class="kb-ref">) before the shared markdown renderer runs.
  module References
    TYPES = %w[idea maxim fact problem kb].freeze
    TOKEN = /@\[([^\]\n]*)\]\((#{TYPES.join('|')}):([^)\s]+)\)/
    TAB = { "maxim" => "maxims", "fact" => "facts", "problem" => "problems" }.freeze
    # Fenced ``` blocks and inline `code` spans are shown literally, so tokens inside them stay as typed.
    CODE = /^[ \t]*(`{3,}|~{3,})[^\n]*\n.*?(?:^[ \t]*\1[`~]*[ \t]*$|\z)|`[^`\n]+`/m

    Ref = Struct.new(:label, :type, :ref, keyword_init: true) do
      def token = "@[#{label.to_s.gsub(/[\[\]\n]/, ' ').strip}](#{type}:#{ref})"
    end

    module_function

    def parse(text) = text.to_s.scan(TOKEN).map { |label, type, ref| Ref.new(label: label, type: type, ref: ref) }

    def kb_ref(src, kind, path) = "#{src.to_i}:#{kind}:#{ERB::Util.url_encode(path)}"

    # "Idea name · v3" for versions of an idea, the plain title otherwise.
    def idea_label(idea) = idea.versioned? ? "#{idea.title} · v#{idea.version_number}" : idea.title

    # Raw markdown with each token swapped for a chip link. Unknown/deleted targets keep their stored label, unlinked.
    def linkify(text, user:)
      text = text.to_s
      return text unless text.include?("@[")

      ideas = user.ideas.where(id: parse(text).select { |r| r.type == "idea" }.map { |r| r.ref.to_i }).index_by(&:id)
      text.gsub(Regexp.union(CODE, TOKEN)) do |m|
        next m unless (t = m.match(TOKEN)) && t[0] == m

        ref = Ref.new(label: t[1], type: t[2], ref: t[3])
        label, href = resolve(ref, ideas)
        chip(ref.type, label, href)
      end
    end

    def resolve(ref, ideas)
      routes = Rails.application.routes.url_helpers
      case ref.type
      when "idea"
        idea = ideas[ref.ref.to_i]
        idea ? [ idea_label(idea), routes.idea_path(idea) ] : [ ref.label, nil ]
      when "kb"
        src, kind, path = ref.ref.split(":", 3)
        path = CGI.unescape(path.to_s)
        key = { "file" => :file, "project" => :project }.fetch(kind, :folder)
        [ ref.label, routes.kb_path(:src => src, key => path) ]
      else
        # the card's dom id (maxim_5, fact_5, problem_5): tabs_controller opens the tab and scrolls to it
        [ ref.label, routes.kb_path(tab: TAB[ref.type], anchor: "#{ref.type}_#{ref.ref.to_i}") ]
      end
    end

    def chip(type, label, href)
      label = ERB::Util.html_escape(label)
      cls = "kb-ref kb-ref--#{type}"
      href ? %(<a class="#{cls}" href="#{ERB::Util.html_escape(href)}">#{label}</a>) : %(<span class="#{cls} is-gone">#{label}</span>)
    end
  end
end
