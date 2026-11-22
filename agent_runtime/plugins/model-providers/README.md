# Model Providers

This fork intentionally ships one bundled inference provider profile:

- `custom` — local/OpenAI-compatible endpoints such as Ollama, vLLM, and llama.cpp.

The provider registry still supports user-installed provider plugins under
`$HERMES_HOME/plugins/model-providers/`, but the repository no longer carries
the broad cloud provider catalog. Keep the bundled path local-first unless the
webapp product explicitly needs another inference backend.
