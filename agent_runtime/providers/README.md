# providers/

Registry and base classes for inference provider profiles.

This fork keeps the registry because core agent code reads provider metadata,
but the bundled catalog has been reduced to the local/OpenAI-compatible
`custom` provider. User-installed provider plugins can still live under
`$HERMES_HOME/plugins/model-providers/` if a deployment needs one, but the
repository default should stay local-first.

## Layout

```text
providers/
├── base.py
├── __init__.py
└── README.md
```

Bundled profiles live in `plugins/model-providers/`.
