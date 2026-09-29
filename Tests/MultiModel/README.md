# Multi-model conversation contract checks

Baseline: Open Relay 6.0 (`4151a735`), Open WebUI `8bd8b4fa`.

The baseline parser ignores native `modelIdx`, and serialization writes zero
for every assistant. The first assertion was run against the unchanged source
and failed: reopening and saving a response in column one changes it to zero.
The change preserves the optional column rather than inventing one for legacy
history. Duplicate model IDs are valid, so model ID alone is not column identity.

Run from the repository root:

```sh
TMPDIR=/path/to/disposable-output sh Tests/MultiModel/run.sh
```

The harness compiles the actual message/history/request models. Only inline-image
extraction is stubbed; all inputs are invented plain text. Checks cover column
zero and nonzero indices, legacy/malformed indices, duplicate models,
regeneration, inactive siblings, JSON round trips, the active prompt branch, and
the optional native batch-request shape without changing ordinary requests.
All 27 checks pass. The standalone Swift 5 compile reports pre-existing
`Any`/Sendable warnings in the shared API models; it completes successfully.

This is a prerequisite for multi-model sending/rendering, not a claim that the
complete multi-model UI or streaming workflow is implemented or runtime-tested.
The native web client sends one completion request with an ordered `message_ids`
array of `{model_id, message_id, modelIdx}`; the server performs the fan-out.

Public contract references:

- [Send and column identity](https://github.com/open-webui/open-webui/blob/8bd8b4fac5e059578ac0c74b3c18d11139f88b7d/src/lib/components/chat/Chat.svelte#L3255)
- [Comparison grouping](https://github.com/open-webui/open-webui/blob/8bd8b4fac5e059578ac0c74b3c18d11139f88b7d/src/lib/components/chat/Messages/MultiResponseMessages.svelte#L151)

Do not add real chats, configuration, credentials, recordings, or raw logs to
these fixtures or reports. Future UI media must use isolated synthetic data.
