# Conservative ingredient-list detection for rendered markdown. A <ul>/<ol> qualifies when it follows an
# "Ingredients" heading/paragraph, or when at least 2 items and >= 60% of them start with quantity + unit
# ("200 g flour"). Each item becomes a name badge; a parsed quantity becomes a clickable badge
# (data-qty/data-unit) that ingredients_controller.js flips between units. Everything else is untouched.
module Kb
  module Ingredients
    UNITS = {
      "g" => %w[g gram grams], "kg" => %w[kg kilo kilos kilogram kilograms], "ml" => %w[ml milliliter milliliters millilitre millilitres],
      "l" => %w[l liter liters litre litres], "tsp" => %w[tsp teaspoon teaspoons], "tbsp" => %w[tbsp tablespoon tablespoons],
      "cup" => %w[cup cups], "fl oz" => [ "fl oz", "fl. oz", "fluid ounce", "fluid ounces" ], "oz" => %w[oz ounce ounces],
      "lb" => %w[lb lbs pound pounds]
    }.freeze
    ALIASES = UNITS.flat_map { |canon, names| names.map { |n| [ n, canon ] } }.to_h.freeze
    FRACTIONS = { "½" => 0.5, "¼" => 0.25, "¾" => 0.75, "⅓" => 1 / 3.0, "⅔" => 2 / 3.0, "⅛" => 0.125 }.freeze
    ITEM = /\A\s*(\d+\s+\d+\/\d+|\d+\/\d+|\d+(?:[.,]\d+)?\s?[½¼¾⅓⅔⅛]?|[½¼¾⅓⅔⅛])\s*(#{ALIASES.keys.sort_by { |k| -k.size }.map { |k| Regexp.escape(k) }.join("|")})\b\.?\s*(?:of\s+)?(.+)\z/i

    # [value, canonical unit, name] or nil.
    def self.parse(text)
      m = ITEM.match(text.to_s.strip) or return
      [ quantity(m[1]), ALIASES.fetch(m[2].downcase), m[3].strip ]
    end

    def self.quantity(raw)
      raw = raw.strip
      return FRACTIONS.fetch(raw) if FRACTIONS.key?(raw)
      if (m = raw.match(/\A(\d+)\s*([½¼¾⅓⅔⅛])\z/)) then return m[1].to_f + FRACTIONS[m[2]] end
      if (m = raw.match(/\A(?:(\d+)\s+)?(\d+)\/(\d+)\z/)) then return m[1].to_f + m[2].to_f / m[3].to_f end
      raw.tr(",", ".").to_f
    end

    # Rewrites qualifying lists in an HTML string; returns it unchanged when none qualify.
    def self.transform(html)
      return html unless html.include?("<li")
      fragment = Loofah.fragment(html)
      lists = fragment.css("ul, ol").select { |list| ingredient_list?(list) }
      return html if lists.empty?
      lists.each { |list| decorate(list, fragment.document) }
      fragment.to_s
    end

    def self.items(list) = list.xpath("./li")

    def self.ingredient_list?(list)
      lis = items(list)
      return false if lis.empty? || list.ancestors("li").any?
      return true if heading?(list)
      hits = lis.count { |li| parse(li.xpath("./text()").text) }
      lis.size >= 2 && hits >= 2 && hits >= lis.size * 0.6
    end

    def self.heading?(list)
      prev = list.previous_element
      prev && prev.name.match?(/\A(h[1-6]|p)\z/) && prev.text.strip.length < 40 && prev.text.match?(/ingredient/i)
    end

    def self.decorate(list, doc)
      list["class"] = [ list["class"], "kb-ingredients" ].compact.join(" ")
      list["data-controller"] = "ingredients"
      items(list).each do |li|
        next if li.element_children.any? { |c| %w[ul ol].include?(c.name) }
        text = li.text.strip
        qty, unit, name = parse(text)
        li.children.remove
        li["class"] = "kb-ingredient"
        if qty
          badge = doc.create_element("span", "#{trim(qty)} #{unit}", class: "kb-ingredient__qty", "data-ingredients-target": "qty",
                                     "data-qty": qty.to_s, "data-unit": unit, "data-action": "click->ingredients#flip", role: "button", tabindex: "0", title: "Click to switch units")
          li.add_child(badge)
          li.add_child(" ")
        end
        li.add_child(doc.create_element("span", name || text, class: "kb-ingredient__name"))
      end
    end

    def self.trim(value) = (value.round(2) % 1).zero? ? value.round.to_s : value.round(2).to_s
  end
end
