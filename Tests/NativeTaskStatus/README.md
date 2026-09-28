# Native task status regression

Baseline: Open Relay 6.0 (`4151a73`), Open WebUI `8bd8b4f`.

Task rows cycled their status locally and silently posted to the nonexistent
`/api/v1/tasks/{chat_id}/update` endpoint. The displayed change was not saved.
Separately, native `chat:message:tasks` snapshots were ignored, while older tool
text could be reparsed and replace newer state.

The fix makes task rows read-only, handles native snapshots in both active and
passive chat listeners, and removes the unsupported write and text-inference paths.
Saved conversation task loading and the collapsible panel remain unchanged.

## Focused tests

Run `python3 Tests/NativeTaskStatus/run.py`. It compiles the actual task model and
snapshot method with a stub chat, checks all native states, malformed/duplicate
IDs, clearing and repeated updates, and verifies both listener branches and the
absence of the obsolete write paths. `--baseline` intentionally fails because a
mock 404 still leaves a task looking completed.

## Simulator

Use an isolated simulator with `fixture.py` running on loopback port 18191 in a
Python environment containing `aiohttp` and `python-socketio`. Connect Relay to
`http://127.0.0.1:18191`, using `demo@example.test` / `synthetic` if prompted.
Generate this directory's `project.yml` with XcodeGen. Run `testBefore` on the
baseline app, or `testNativeTasks` on the fixed app. The tests inspect fixture
state and unsupported-write counts as well as the actual task panel.

The 6.0-based full Release build and 11 focused checks pass. The final simulator
test passed three consecutive times. The fixture persists the completed node
before emitting completion, matching the server. An earlier incomplete fixture
only emitted completion; its immediate-clear check failed intermittently.
The included before/after screenshots are from the 6.0-based simulator runs.

All content is newly invented. This fixture does not import Open WebUI, use a real
provider, or read private chats, settings, credentials, or logs.
