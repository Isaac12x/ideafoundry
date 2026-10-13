# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Sprockets has no .mjs mime type, so lib/*.mjs importmap modules were served
# without a Content-Type and browsers refused to load them as modules.
Rails.application.config.assets.configure do |env|
  env.register_mime_type "application/javascript", extensions: [ ".js", ".mjs" ], charset: :unicode
end
