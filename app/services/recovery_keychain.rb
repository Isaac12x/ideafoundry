require "fileutils"
require "json"
require "pathname"
require "rbconfig"

# Platform-aware secure storage for the recovery passphrase.
# Priority: macOS Keychain → Linux libsecret → fallback file outside Rails.root.
class RecoveryKeychain
  KEYCHAIN_SERVICE = "idea-foundry-recovery-passphrase"
  KEYCHAIN_ACCOUNT = "idea-foundry"

  # Returns {passphrase:, kdf_n:, kdf_r:, kdf_p:} or nil.
  def self.retrieve(app_node_id:)
    raw = backend.retrieve
    return unless raw.present?

    decoded = JSON.parse(raw)
    return unless decoded.is_a?(Hash) && decoded["passphrase"].present?
    return unless decoded["app_node_id"].to_s == app_node_id.to_s

    {
      passphrase: decoded["passphrase"],
      kdf_n: decoded["kdf_n"]&.to_i,
      kdf_r: decoded["kdf_r"]&.to_i,
      kdf_p: decoded["kdf_p"]&.to_i
    }
  rescue JSON::ParserError
    nil
  end

  # Stores passphrase + kdf_params in the platform keychain.
  # kdf_params: {n:, r:, p:}
  def self.store(passphrase, app_node_id:, kdf_params: {})
    data = JSON.generate({
      "version" => 2,
      "app_node_id" => app_node_id,
      "passphrase" => passphrase.to_s,
      "kdf_n" => kdf_params[:n],
      "kdf_r" => kdf_params[:r],
      "kdf_p" => kdf_params[:p]
    })
    backend.store(data)
  end

  def self.delete
    backend.delete
  end

  # True when a real OS keychain (not the file fallback) is in use.
  def self.keychain_available?
    !backend.is_a?(FileBackend)
  end

  # Canonical path for the file fallback — always outside Rails.root.
  def self.fallback_path
    FileBackend.data_path
  end

  class << self
    private

    def backend
      @backend ||= select_backend
    end

    def select_backend
      macos = MacosBackend.new
      return macos if macos.available?

      linux = LinuxSecretToolBackend.new
      return linux if linux.available?

      FileBackend.new
    end
  end

  # ── Backends ──────────────────────────────────────────────────────────────

  class MacosBackend
    # Compiled from libexec/keychain-helper.swift by bin/setup.
    # Using a dedicated binary (rather than the `security` CLI) lets us
    # create keychain items whose ACL restricts silent access to THIS
    # binary only — the `security` CLI and all other processes get a
    # user-confirmation dialog instead.
    HELPER = File.expand_path("../../../libexec/keychain-helper", __FILE__).freeze

    def available?
      RbConfig::CONFIG["host_os"].match?(/darwin/) && File.executable?(HELPER)
    end

    def store(data_json)
      IO.popen([HELPER, "store"], "w") do |io|
        io.write(data_json)
      end
      $?.success?
    end

    def retrieve
      out, _err, status = Open3.capture3(HELPER, "retrieve")
      return unless status.success?

      out.presence
    end

    def delete
      system(HELPER, "delete", out: File::NULL, err: File::NULL)
    end
  end

  class LinuxSecretToolBackend
    ATTRS = %w[service idea-foundry username recovery-passphrase].freeze
    LABEL = "Idea Foundry Recovery Passphrase"

    def available?
      return false unless RbConfig::CONFIG["host_os"].match?(/linux/)

      system("which", "secret-tool", out: File::NULL, err: File::NULL)
    end

    def store(data_json)
      IO.popen(["secret-tool", "store", "--label=#{LABEL}", *ATTRS], "w") do |io|
        io.write(data_json)
      end
      $?.success?
    end

    def retrieve
      out, _err, status = Open3.capture3("secret-tool", "lookup", *ATTRS)
      return unless status.success?

      out.strip.presence
    end

    def delete
      system("secret-tool", "clear", *ATTRS, out: File::NULL, err: File::NULL)
    end
  end

  class FileBackend
    def self.data_path
      os = RbConfig::CONFIG["host_os"]
      dir = if os.match?(/darwin/)
        Pathname.new("~/Library/Application Support/IdeaFoundry").expand_path
      elsif os.match?(/mswin|mingw/)
        Pathname.new(ENV.fetch("APPDATA", "~")).expand_path.join("IdeaFoundry")
      else
        Pathname.new(ENV.fetch("XDG_CONFIG_HOME", "#{Dir.home}/.config")).join("idea-foundry")
      end
      dir.join("recovery_passphrase.json")
    end

    def store(data_json)
      path = self.class.data_path
      FileUtils.mkdir_p(path.dirname)
      File.write(path, data_json)
      File.chmod(0o600, path)
      true
    end

    def retrieve
      path = self.class.data_path
      return unless path.file?

      File.read(path).strip.presence
    end

    def delete
      path = self.class.data_path
      FileUtils.rm_f(path)
    end

    def available?
      true
    end
  end
end
