module LocalAgent
  # Agents a thread turn can be addressed to. "local" is the tool-using runner (idea-app-agent) that polls work discovery;
  # "model" answers directly from the local inference server (PromptClient) with the thread as context.
  module Agents
    DEFAULT = "local".freeze

    def self.all
      {
        "local" => "Local agent",
        "model" => "Local model (#{ENV["LOCAL_INFERENCE_MODEL"].presence || ENV["HERMES_MODEL"].presence || PromptClient::DEFAULT_MODEL})"
      }
    end

    def self.valid?(key) = all.key?(key.to_s)

    def self.normalize(key) = valid?(key) ? key.to_s : DEFAULT

    def self.label(key) = all.fetch(normalize(key))

    # Questions the runner must not pick up (answered by AgentModelTurnJob instead).
    def self.runner?(key) = normalize(key) == DEFAULT
  end
end
