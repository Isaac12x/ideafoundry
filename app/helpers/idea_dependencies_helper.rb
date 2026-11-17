module IdeaDependenciesHelper
  # Turns stored @[Title](idea:123) tokens in rendered description HTML into links to the (current) idea.
  def link_idea_mentions(html, user)
    html = String.new(html.to_s)
    ids = html.scan(Idea::MENTION).flatten.map(&:to_i)
    return html.html_safe if ids.empty?

    titles = user.ideas.where(id: ids).pluck(:id, :title).to_h
    html.gsub(Idea::MENTION) do |token|
      id = Regexp.last_match(1).to_i
      titles[id] ? link_to("@#{titles[id]}", idea_path(id), class: "idea-mention") : token
    end.html_safe
  end
end
