source "https://rubygems.org"

ruby "3.4.5"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use sqlite3 as the database for Active Record. Production databases require
# SQLCipher, so build sqlite3 from source with the Bundler flags in .bundle/config.
gem "sqlite3", "~> 2.7", ">= 2.7.3", force_ruby_platform: true

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", "~> 8.0"

# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"

# Bundle JavaScript with esbuild (for heavy 3D graph bundle)
gem "jsbundling-rails"

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"

# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Redis adapter to run Action Cable in production
# gem "redis", ">= 4.0.1"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1", ">= 3.1.22"

# Solid Queue for background jobs [https://github.com/rails/solid_queue]
gem "solid_queue"

# Solid Cache for caching [https://github.com/rails/solid_cache]
gem "solid_cache"

# Action Mailbox for email processing
gem "actionmailbox", "~> 8.1.3"

# Action Text for rich text content
gem "actiontext", "~> 8.1.3"

# Image processing for Active Storage variants
gem "image_processing", "~> 1.2"

# ZIP file handling for exports
gem "rubyzip", "~> 2.3"

# Pagination
gem "kaminari"

# SHA3 digest for integrity hashing
gem "sha3"

# Local QR code rendering for authenticator app setup
gem "rqrcode", "~> 2.2"

# Resend for email delivery
gem "resend"

# Resend webhook ingress for ActionMailbox (Svix-verified)
gem "actionmailbox-resend"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mswin mswin64 mingw x64_mingw jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Formula evaluation for napkin calculations
gem "dentaku", "~> 3.5"



group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri mswin mswin64 mingw x64_mingw ]
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "minitest", "~> 5.25"
  gem "selenium-webdriver"
  # Generate .xlsx fixtures for KB rendering tests (roo reads, caxlsx writes)
  gem "caxlsx"
end

gem "redcarpet", "~> 3.6"

# Read .xlsx spreadsheets for KB rendering (converted to HTML tables)
gem "roo", "~> 2.10"

gem "rack-attack"
