# Run using bin/ci

ruby = RbConfig.ruby
javascript_tests = Dir["test/javascript/*.mjs"].sort

CI.run do
  step "Setup: Bundler", ruby, "-S", "bundle", "check"
  step "Setup: Test database", "env", "RAILS_ENV=test", ruby, "bin/rails", "db:prepare"
  step "Assets: JavaScript", "yarn", "build"
  step "Tests: JavaScript", "node", "--test", *javascript_tests if javascript_tests.any?
  step "Tests: Rails", "env", "RAILS_ENV=test", "PARALLEL_WORKERS=1", ruby, "bin/rails", "test"
end
