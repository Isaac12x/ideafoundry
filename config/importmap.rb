# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"

# TipTap WYSIWYG editor (ESM via esm.sh)
pin "@tiptap/core", to: "https://esm.sh/@tiptap/core@2.11.5"
pin "@tiptap/extension-document", to: "https://esm.sh/@tiptap/extension-document@2.11.5"
pin "@tiptap/extension-paragraph", to: "https://esm.sh/@tiptap/extension-paragraph@2.11.5"
pin "@tiptap/extension-text", to: "https://esm.sh/@tiptap/extension-text@2.11.5"
pin "@tiptap/extension-bold", to: "https://esm.sh/@tiptap/extension-bold@2.11.5"
pin "@tiptap/extension-italic", to: "https://esm.sh/@tiptap/extension-italic@2.11.5"
pin "@tiptap/extension-underline", to: "https://esm.sh/@tiptap/extension-underline@2.11.5"
pin "@tiptap/extension-strike", to: "https://esm.sh/@tiptap/extension-strike@2.11.5"
pin "@tiptap/extension-heading", to: "https://esm.sh/@tiptap/extension-heading@2.11.5"
pin "@tiptap/extension-blockquote", to: "https://esm.sh/@tiptap/extension-blockquote@2.11.5"
pin "@tiptap/extension-code", to: "https://esm.sh/@tiptap/extension-code@2.11.5"
pin "@tiptap/extension-code-block", to: "https://esm.sh/@tiptap/extension-code-block@2.11.5"
pin "@tiptap/extension-bullet-list", to: "https://esm.sh/@tiptap/extension-bullet-list@2.11.5"
pin "@tiptap/extension-ordered-list", to: "https://esm.sh/@tiptap/extension-ordered-list@2.11.5"
pin "@tiptap/extension-list-item", to: "https://esm.sh/@tiptap/extension-list-item@2.11.5"
pin "@tiptap/extension-link", to: "https://esm.sh/@tiptap/extension-link@2.11.5"
pin "@tiptap/extension-image", to: "https://esm.sh/@tiptap/extension-image@2.11.5"
pin "@tiptap/extension-placeholder", to: "https://esm.sh/@tiptap/extension-placeholder@2.11.5"
pin "@tiptap/extension-history", to: "https://esm.sh/@tiptap/extension-history@2.11.5"
pin "@tiptap/extension-hard-break", to: "https://esm.sh/@tiptap/extension-hard-break@2.11.5"
pin "@tiptap/extension-dropcursor", to: "https://esm.sh/@tiptap/extension-dropcursor@2.11.5"
pin "@tiptap/extension-gapcursor", to: "https://esm.sh/@tiptap/extension-gapcursor@2.11.5"
pin "@tiptap/extension-horizontal-rule", to: "https://esm.sh/@tiptap/extension-horizontal-rule@2.11.5"