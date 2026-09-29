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
TMPDIR=/path/to/disposable-output python3 Tests/MultiModel/storage.py
TMPDIR=/path/to/disposable-output python3 Tests/MultiModel/routing.py
TMPDIR=/path/to/disposable-output python3 Tests/MultiModel/generation.py
```

The harness compiles the actual message/history/request models. Only inline-image
extraction is stubbed; all inputs are invented plain text. Checks cover column
zero and nonzero indices, legacy/malformed indices, duplicate models,
regeneration, inactive siblings, JSON round trips, the active prompt branch, and
the optional native batch-request shape without changing ordinary requests.
All 43 history/request checks pass. Comparison columns keep their own regeneration
versions, including duplicate model selections; a missing column never borrows a
response explicitly indexed to another column. The pre-fix grouping assertion
reproduced a different column appearing as a regeneration version.

The storage harness compiles the actual conversation model, API method bodies,
manager save methods, and view-model selection restoration with a synthetic
transport. Its 57 checks cover ordered/duplicate selections, online/offline
restoration, native tree save/reopen, saving a temporary chat, precreating a chat,
legacy flat fallback, folder/summary parsing, and ordinary single-model behavior.
The pre-fix storage assertion reproduced a three-slot conversation being saved
with only its first model. Additional checks exercise actual response edits,
inactive-column citations/status/files/usage, exact-ID metadata refresh, and late
requests after navigation, account changes, a newer generation, or local edits.
Before fixes, structured output overwrote edited text on reopen and metadata was
dropped for inactive columns. The transport records JSON in memory; it makes no
network requests or changes to user preferences. Embed serialization is already
covered by the independently ported #300; it is not duplicated here.

The routing harness's 21 checks compile the actual socket-registration method and content
accumulator, replacing transport and view callbacks with isolated doubles. It
checks interleaved and concurrent tokens, duplicate model selections, structured
thinking/output, snapshot ordering, channel events, terminal-event destinations,
legacy single-response events, Continue prefixes, and stale registrations. The
baseline accepted an unrelated response into the current accumulator; an immediate
Continue delta also exposed a missing initial callback. These checks cover routing,
not full per-response completion, playback, rendering, or background recovery.

The generation harness compiles the actual response-group lifecycle, request
population, regeneration, Continue, edit, recovery, and Stop methods. Its 68
checks use asynchronous synthetic transport and display doubles. They verify:

- Independent stores, accumulators, completion/errors, and branch-specific
  postprocessing; no concatenation of comparison answers into the prompt.
- One native fan-out request, plural task IDs, Stop racing HTTP acceptance,
  account replacement, duplicate completion, and ignored late tokens.
- Recovery of inactive columns, structured-output-only responses, pending legacy
  tools, and socket activity newer than a fetch. Quiet output is not completion.
- Continued and regenerated responses retain the original model/column; editing
  creates all selected responses without deleting earlier branches.
- Workspace-specific system prompts, filters, and tool modes are not copied from
  the primary model into peer requests. Explicit shared chat overrides remain.
- Server refreshes keep the selected comparison branch instead of switching to
  whichever response finished last. Ordinary single-response requests remain valid.

An added negative test caught `error: null` incorrectly failing an accepted request
in the initial implementation; it now passes, including null error plus real detail
failure. All 189 focused checks pass. Network, notification presentation, and display
timing are doubles here; these checks do not establish full-app runtime correctness.

Reproduce the original routing/metadata failures without changing branches:

```sh
TMPDIR=/path/to/disposable-output python3 Tests/MultiModel/routing.py --revision 4151a735
TMPDIR=/path/to/disposable-output python3 Tests/MultiModel/storage.py --metadata-revision 4151a735
```

The standalone Swift 5 compile reports pre-existing
`Any`/Sendable warnings in the shared API models; it completes successfully.

This branch is still in progress: comparison selection/rendering, reconnect
restoration, pending-input presentation, and full-app synthetic tests remain.
It is not a claim that the complete UI or streaming workflow is runtime-tested.
The native web client sends one completion request with an ordered `message_ids`
array of `{model_id, message_id, modelIdx}`; the server performs the fan-out.

Public contract references:

- [Send and column identity](https://github.com/open-webui/open-webui/blob/8bd8b4fac5e059578ac0c74b3c18d11139f88b7d/src/lib/components/chat/Chat.svelte#L3255)
- [Comparison grouping](https://github.com/open-webui/open-webui/blob/8bd8b4fac5e059578ac0c74b3c18d11139f88b7d/src/lib/components/chat/Messages/MultiResponseMessages.svelte#L151)

Do not add real chats, configuration, credentials, recordings, or raw logs to
these fixtures or reports. Future UI media must use isolated synthetic data.
