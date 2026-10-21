module Kb
  # Print stylesheets for WebPage#reader_html. Inlined into the HTML sent to
  # headless Chrome (nothing hotlinked at render time).
  module ReaderStyles
    # Running footer via @page margin boxes (Chrome 131+; older ones ignore it):
    # short title left, page number right; the first page keeps just the number.
    def self.footer(title)
      short = title.truncate(60).gsub(/["\\\n]/, " ")
      <<~CSS
        @page { @bottom-left { content: "#{short}"; } @bottom-right { content: counter(page); } }
        @page :first { @bottom-left { content: none; } }
        @page { @bottom-left, @bottom-right { font: 7.5pt -apple-system, "Helvetica Neue", Arial, sans-serif; color: #8a8f94; vertical-align: top; padding-top: 4mm; } }
      CSS
    end

    READER = <<~CSS.freeze
      @page { size: A4; margin: 20mm 20mm 22mm; }
      * { box-sizing: border-box; }
      html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
      body { margin: 0; color: #1f1b16; overflow-wrap: break-word; hyphens: auto; -webkit-hyphens: auto;
             font: 11pt/1.6 "Iowan Old Style", Charter, "Palatino Linotype", Georgia, serif; }
      main { max-width: 36em; margin: 0 auto; }
      header { border-bottom: 0.5pt solid #d9cfbf; margin-bottom: 1.6em; padding-bottom: 1em; }
      .kicker { font: 600 8pt/1 -apple-system, "Helvetica Neue", Arial, sans-serif; letter-spacing: .16em;
                text-transform: uppercase; color: #a0672a; margin: 0 0 1em; }
      h1 { font-size: 25pt; line-height: 1.12; font-weight: 600; margin: 0 0 .45em; letter-spacing: -.01em; }
      .source { font: 8.5pt/1.4 -apple-system, "Helvetica Neue", Arial, sans-serif; color: #7d7263; margin: 0; word-break: break-all; }
      .source a { color: inherit; }
      h2 { font-size: 16pt; line-height: 1.2; margin: 1.7em 0 .5em; }
      h3 { font-size: 13pt; line-height: 1.25; margin: 1.4em 0 .4em; }
      h4, h5, h6 { font-size: 11.5pt; margin: 1.2em 0 .3em; }
      h1, h2, h3, h4, h5, h6, dt { break-after: avoid; break-inside: avoid; hyphens: manual; }
      figure, figcaption { break-inside: avoid; } figure > img + figcaption { break-before: avoid; }
      p { margin: 0 0 .8em; }
      p, li, dd { orphans: 3; widows: 3; }
      a { color: inherit; text-decoration: underline; text-decoration-color: #c9bca6; text-decoration-thickness: .5pt; text-underline-offset: 1.5pt; hyphens: manual; overflow-wrap: anywhere; }
      h1 a, h2 a, h3 a, h4 a, h5 a, h6 a { text-decoration: none; }
      img, video, canvas { max-width: 100%; max-height: 150mm; width: auto; height: auto; object-fit: contain; break-inside: avoid; }
      figure, p > img:only-child { break-inside: avoid; }
      figure img, figure picture { display: block; margin: 0 auto; }
      figure { margin: 1.3em 0; break-inside: avoid; text-align: center; }
      figcaption, caption { font: 9pt/1.4 -apple-system, "Helvetica Neue", Arial, sans-serif; color: #6b6154; margin-top: .4em; text-align: left; }
      table { border-collapse: collapse; font: 9pt/1.4 -apple-system, "Helvetica Neue", Arial, sans-serif;
              margin: 1.2em 0; max-width: 100%; }
      thead { display: table-header-group; }
      tr, th, td { break-inside: avoid; }
      th, td { border: 0.5pt solid #d9cfbf; padding: .3em .5em; vertical-align: top; text-align: left; }
      th { background: #f5f0e8; }
      blockquote { margin: 1.2em 0; padding-left: 1em; border-left: 2pt solid #d9cfbf; color: #4d443a; break-inside: avoid; }
      pre { font: 8.5pt/1.45 ui-monospace, Menlo, Consolas, monospace; white-space: pre-wrap; overflow-wrap: anywhere;
            background: #f6f2ea; border: 0.5pt solid #e4dccf; border-radius: 2pt; padding: .6em .8em; margin: 1em 0; }
      code, kbd, samp { font: 0.88em ui-monospace, Menlo, Consolas, monospace; overflow-wrap: anywhere; }
      pre code { font-size: inherit; background: none; }
      :not(pre) > code { background: #f6f2ea; padding: 0 .25em; border-radius: 2pt; }
      hr { border: 0; border-top: 0.5pt solid #d9cfbf; margin: 1.6em 0; }
      sup, sub { font-size: 7.5pt; line-height: 0; }
      ol.references, #references ol, .footnotes { font-size: 9pt; }
    CSS

    # Wikipedia's own look (Vector-ish): serif headings with the rule, sans
    # body, floated infobox, thumbnails, wikitables, references.
    WIKIPEDIA = <<~CSS.freeze
      @page { size: A4; margin: 18mm 18mm 20mm; }
      html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
      body { margin: 0; color: #202122; overflow-wrap: break-word; hyphens: auto; -webkit-hyphens: auto;
             font: 10pt/1.6 -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
      main { max-width: none; }
      .wp-head { margin-bottom: 1em; }
      .wp-head h1 { font: normal 22pt/1.3 "Linux Libertine", "Georgia", "Times", serif; border-bottom: 0.75pt solid #a2a9b1;
                    margin: 0 0 .2em; padding: 0 0 .15em; }
      .wp-head .tagline { font-size: 8.5pt; color: #54595d; margin: 0 0 .1em; }
      .wp-head .source { font-size: 7pt; color: #8a8f94; margin: 0; word-break: break-all; }
      .wp-head .source a { color: inherit; text-decoration: none; }
      a { color: #0645ad; text-decoration: none; hyphens: manual; } a.new, a.new:visited { color: #ba0000; }
      a.external { color: #36c; }
      p { margin: .5em 0; }
      p, li, dd { orphans: 3; widows: 3; }
      h2, .mw-heading2 { font: normal 16pt/1.3 "Linux Libertine", "Georgia", "Times", serif; border-bottom: 0.75pt solid #a2a9b1;
                         margin: 1.1em 0 .25em; padding: 0; }
      h3 { font: bold 12.5pt/1.3 sans-serif; margin: 1em 0 .2em; }
      h4, h5, h6 { font: bold 10.5pt/1.3 sans-serif; margin: .9em 0 .2em; }
      h1, h2, h3, h4, h5, h6, .mw-heading { break-after: avoid; break-inside: avoid; hyphens: manual; }
      .mw-heading > h2, .mw-heading > h3, .mw-heading > h4 { margin-top: 0; }
      .mw-heading2 { margin-top: 1.1em; } .mw-heading3, .mw-heading4 { margin-top: .9em; }
      .mw-heading2 > h2 { border: 0; }
      ul { list-style: disc; margin: .3em 0 0 1.6em; padding: 0; } ol { margin: .3em 0 0 3.2em; padding: 0; }
      li { margin-bottom: .1em; } dl { margin: .2em 0; } dd { margin: 0 0 .1em 1.6em; }
      .hatnote, .dablink, .rellink { font-style: italic; padding-left: 1.6em; margin: .3em 0 .6em; }
      .hatnote i { font-style: normal; }
      .shortdescription, .mw-empty-elt { display: none; }

      table.infobox, table.infobox_v2, .infobox { float: right; clear: right; width: 20em; margin: .4em 0 .8em 1.2em;
                      background: #f8f9fa; border: 0.75pt solid #a2a9b1; padding: .25em; font-size: 88%; line-height: 1.5;
                      border-collapse: collapse; text-align: left; }
      .infobox caption, .infobox-title { font-size: 125%; font-weight: bold; text-align: center; padding: .3em; }
      .infobox th, .infobox td { padding: .2em .4em; vertical-align: top; border: 0; }
      .infobox-label, .infobox th { text-align: left; font-weight: bold; padding-right: .8em; }
      .infobox-header, .infobox-above, .infobox-subheader, .infobox-full-data { text-align: center; }
      .infobox-above { font-size: 125%; font-weight: bold; }
      .infobox-image { text-align: center; } .infobox img { max-width: 100%; height: auto; }
      .infobox .infobox-data, .infobox td { text-align: left; }
      .infobox tr { break-inside: avoid; }
      .infobox td > div, .infobox td > ul { margin: 0; } .infobox ul, .infobox ol { margin: 0; padding-left: 1.1em; }
      .infobox .plainlist ul, .infobox .hlist ul { list-style: none; margin: 0; padding: 0; }
      .infobox .hlist li { display: inline; } .infobox .hlist li + li::before { content: " \\2022  "; }
      .infobox-image + tr .infobox-data, .infobox .infobox-caption { font-size: 90%; text-align: center; }
      .infobox-image img { margin: 0 auto; display: block; }

      figure[typeof~="mw:File/Thumb"], figure[typeof~="mw:File/Frame"], .thumb { background: #f8f9fa; border: 0.75pt solid #c8ccd1;
                      padding: 3pt; margin: .5em 0 .8em; font-size: 88%; break-inside: avoid; }
      figure[typeof~="mw:File/Thumb"], figure[typeof~="mw:File/Frame"], .tright, .floatright { float: right; clear: right; margin-left: 1.2em; max-width: 14em; }
      .tleft, .floatleft { float: left; clear: left; margin-right: 1.2em; max-width: 14em; }
      .tnone, .center { clear: both; }
      .thumbinner { background: #f8f9fa; text-align: left; }
      figure img, .thumb img { max-width: 100%; height: auto; display: block; margin: 0 auto; border: 0.75pt solid #c8ccd1; }
      figure figcaption, .thumbcaption { font: 88%/1.4 sans-serif; color: #202122; padding: 3pt 0 0; text-align: left; }
      .mw-halign-right { float: right; margin-left: 1em; } .mw-halign-left { float: left; margin-right: 1em; }
      .mw-halign-center { display: block; text-align: center; }
      img.mwe-math-fallback-image-inline, img.mwe-math-fallback-image-display { border: 0; display: inline; max-width: none; }
      .mwe-math-element { display: inline; } .mwe-math-element.mwe-math-element-block { display: block; text-align: center; margin: .5em 0; }
      .mwe-math-mathml-a11y, .mwe-math-mathml-inline, .mwe-math-mathml-display { display: none !important; }
      img { max-width: 100%; max-height: 190mm; width: auto; }
      img.mwe-math-fallback-image-inline, img.mwe-math-fallback-image-display { max-height: none; width: auto; }

      table.wikitable { background: #f8f9fa; border: 0.75pt solid #a2a9b1; border-collapse: collapse; margin: .8em 0; font-size: 90%; max-width: 100%; }
      .wikitable th, .wikitable td { border: 0.75pt solid #a2a9b1; padding: .2em .4em; vertical-align: top; }
      .wikitable th { background: #eaecf0; text-align: center; }
      .wikitable caption { font-weight: bold; padding: .3em; }
      table { break-inside: auto; } tr { break-inside: avoid; } thead { display: table-header-group; }
      .sidebar, .side-box { float: right; clear: right; width: 20em; margin: .4em 0 .8em 1.2em; background: #f8f9fa;
                            border: 0.75pt solid #a2a9b1; padding: .4em; font-size: 88%; }

      sup.reference, sup { font-size: 70%; line-height: 0; } sup.reference a { white-space: nowrap; }
      .reflist, ol.references { font-size: 90%; } ol.references { margin-left: 2.4em; }
      .references li { margin-bottom: .2em; } .reflist-columns, .references-column-width, .mw-references-columns, .reflist { column-width: 22em; column-gap: 2em; } .references li { break-inside: avoid; }
      .mw-cite-backlink { color: #54595d; } cite { font-style: normal; }
      .citation-comment, .cs1-hidden-error, .cs1-visible-error { color: #d33; }
      blockquote { margin: .8em 3em; } .quotebox, .cquote { border-left: 2pt solid #a2a9b1; padding-left: 1em; }
      pre, code { font: 9pt/1.4 ui-monospace, Menlo, Consolas, monospace; white-space: pre-wrap; background: #f8f9fa; }
      pre { border: 0.75pt solid #eaecf0; padding: .5em .8em; break-inside: avoid; }
      .mw-parser-output > h2:first-child, .mw-parser-output > .mw-heading2:first-child { margin-top: .6em; }
    CSS
  end
end
