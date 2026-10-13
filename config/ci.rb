# Run using bin/ci

ruby = RbConfig.ruby
javascript_tests = Dir["test/javascript/*.mjs"].sort

# Steps spawn their own bundler; drop the one bin/ci loaded (version mismatch -> superclass error).
Bundler.with_original_env do
  CI.run do
    step "Setup", "bin/setup --skip-server"
    step "Style: Ruby", "bin/rubocop"
    step "Security: Importmap vulnerability audit", "bin/importmap audit"
    step "Assets: JavaScript", "yarn", "build"
    step "Tests: JavaScript", "node", "--test", *javascript_tests if javascript_tests.any?
    step "Tests: Rails", "env", "RAILS_ENV=test", "PARALLEL_WORKERS=1", ruby, "bin/rails", "test"
    # Boot production config eagerly (no DB/secrets needed) to catch config conflicts like solid_cache database vs connects_to.
    step "Boot: production eager load", "env", "RAILS_ENV=production", "SECRET_KEY_BASE_DUMMY=1", ruby, "bin/rails", "runner", "Rails.application.eager_load!"
  end
end
