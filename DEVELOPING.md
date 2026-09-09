# openHAB for Omarchy

## Project overview

This repository is an Omarchy 4 Quickshell plugin for viewing and controlling
openHAB items from the desktop bar. The UI is QML with small pure JavaScript
modules. A long-lived Python helper owns the openHAB REST/SSE connection and
communicates with QML over versioned NDJSON on stdin/stdout.

The plugin connects to any openHAB 3+ instance over its REST API. There is no
instance-specific configuration baked in: the only per-user inputs are a
server URL and an API token, both entered in the settings overlay. The token
is stored in the system keyring, never in the plugin config or the process
arguments.

The plugin must remain installable without npm, pip, a virtual environment, or
first-run downloads. Python 3.11 or newer and `secret-tool` are the runtime
dependencies (the bridge uses only the Python standard library — openHAB's
REST/SSE API needs nothing vendored). `nmcli` is an additional, conditional
one, invoked from two places: the bridge (only when a local network URL is
actually configured, to gate every connection attempt — see the security
invariant below) and the settings UI (each time it opens, to suggest a value
for the trusted-network field; read-only, never a security decision). Its
absence must degrade to "never use the local URL" for the bridge and "no
suggestion" for the UI, not an error either way.

Reference implementation this is built against: `https://github.com/konradk/hass`
(Home Assistant for Omarchy).

## Architecture map

- `Service.qml`: session-wide facade and owner of configuration, connection
  reconciliation, item state, action dispatch, and the projected item rows.
- `BridgeController.qml`: lifecycle and NDJSON transport for `bin/oh-bridge`.
- `CredentialManager.qml`: serialized access to the system keyring.
- `Connection.js`: URL/origin identity, connection signatures, and generation
  filtering.
- `Credentials.js`: pure credential normalization/classification between the
  settings fields and the keyring's single per-origin string (API token or
  `username:password` pair). Mirrors `bin/oh-bridge`'s `normalize_credential`.
- `ConfigStore.js`: persisted configuration normalization and serialization.
- `EntityStore.js`: item state, index, and Location→Equipment→Point
  projections from the openHAB semantic model.
- `Model.js`: item display policy, capabilities, action classification, and
  attribute redaction.
- `RowModel.js`: projection from an item into a QML `ListModel` row.
- `Mark.js`: the openHAB brand mark's geometry (official SVG paths parsed into
  absolute commands and fitted into a square), replayed by `OpenHabIcon.qml`.
- `OpenHabIcon.qml`: Canvas drawing of the openHAB mark in a single theme tint.
- `Panel.qml`: bar widget, popup, keyboard navigation, and IPC surface.
- `Settings.qml`: connection settings overlay.
- `bin/oh-bridge`: openHAB REST/SSE protocol adapter and demo backend.
- `tests/fake_openhab.py`: local fake openHAB used by bridge tests.

Keep transport, credential lifecycle, state projection, and UI policy
separate. Prefer extending the existing pure JavaScript modules over adding
more policy to `Service.qml`.

## openHAB REST surface used

- Inventory: `GET {base}/rest/items?recursive=false` returns every item with
  `name`, `type`, `label`, `category`, `tags`, `groupNames`, `state`, and a
  `metadata.semantics` block when the instance uses the semantic model.
- Live state push: the tracked-states SSE endpoint (the same one the Main UI
  uses). `GET {base}/rest/events/states` yields a `ready` event carrying a
  connectionId; `POST {base}/rest/events/states/{connectionId}` with a JSON
  array of item names then streams `{"ItemName":{"state":...,"type":...}}`
  maps for exactly those items — current values first, then every change.
- Commands: `POST {base}/rest/items/{itemName}` with `Content-Type:
  text/plain` and the command string as body (ON/OFF, `0-100`, `h,s,b`, PLAY,
  ...).
- Authentication: HTTP Basic. The origin's keyring credential is one of two
  forms, both normalized (whitespace/quotes/a pasted `Bearer ` prefix are
  stripped by `Credentials.js` and the bridge's `normalize_credential`): an
  API token sent as username with an empty password (`token:`), the form the
  openHAB REST docs document; or a `username:password` pair (`user:pass`) for
  servers/proxies that demand a real login. openHAB API tokens start with
  `oh.` and never contain `:`, so `Credentials.js` / `normalize_credential`
  classify a stored string by whether it contains a `:`.

## Security invariants

- Never persist an openHAB API token in `config.json`, logs, fixtures, process
  arguments, error text, or IPC output. Tokens may travel only through stdin
  to `secret-tool` and the bridge.
- Scope credentials to a normalized server origin. Changing origin must never
  silently reuse a credential. Credential deletion must target an explicit
  origin and must not remove a saved live credential as a side effect of demo
  mode. The optional local-network URL (`localUrl`) is a deliberate, narrow
  exception: it is an alternate address for the same instance the primary URL
  already names, not a second server, so it intentionally shares the primary
  origin's stored token rather than getting its own keyring entry. Do not add
  separate credential storage for it, and do not let it participate in
  `currentOrigin()`/`requiresTokenFor()` — those stay scoped to the primary
  URL only.
- `localUrl` must never be tried unless `trustedNetwork` is set and one of its
  comma-separated names matches the current Wi-Fi network name
  (`current_wifi_ssid()` and `trusted_network_list()` in `bin/oh-bridge`,
  checked fresh on every connection attempt — the list exists because a
  router commonly broadcasts more than one SSID). This is the only thing
  standing between an alternate address and sending the token to whatever
  happens to answer there on a network the user never trusted — fail closed on
  every path (no NetworkManager, an nmcli error or timeout, no active Wi-Fi,
  no match) rather than defaulting to "trusted". Enforce this in both the
  bridge and `Service.applyConnection` — the settings UI check is a fast-fail
  convenience, not the security boundary.
- Treat `http://` as plaintext transport. Any UI path that permits it must
  make the token-exposure risk explicit; never downgrade an invalid or unknown
  scheme to plaintext.
- TLS verification, proxy bypass, compression disablement, message limits,
  bounded receive queues, and connection timeouts are deliberate hardening.
  Do not weaken them without an explicit security decision and regression test.
- Keep protocol version and connection generation on every bridge command and
  event. Reject data from old generations before mutating UI state.
- Report `connected` only after inventory, the SSE subscription, and the
  initial state snapshot succeed. Reset reconnect backoff only after the full
  connection is ready, not merely after authentication.
- Bound both process startup and completion for every keyring operation. Clear
  plaintext token properties on every success, failure, timeout, and cancel
  path.
- Render openHAB-controlled strings as plain text. Debug/IPC output must pass
  through explicit redaction and must not expose location or signed media
  attributes.
- Use argument arrays for `Process`; do not introduce shell interpolation for
  URLs, item names, commands, paths, or secrets.

## Coding conventions

- Keep JavaScript helpers side-effect free where practical and compatible with
  the QML JavaScript engine. Do not add Node-only APIs to production modules.
- Validate external JSON shapes before indexing or rendering them. Use safe map
  keys or prototype-free maps for server-controlled identifiers.
- Derive actions from `Model.capabilitiesFor`; do not expose arbitrary openHAB
  item commands through UI or IPC beyond the controlled mapping.
- Keep high-frequency `statechanged` handling incremental. Avoid copying or
  rebuilding the entire item collection for a known item update.
- Use `Style` and `Color` tokens in QML. Every `Text` must set
  `textFormat: Text.PlainText` and an explicit font family.
- Sliders should send commands on release rather than on every movement.
- Preserve public IPC commands and the NDJSON protocol unless a versioned
  migration is part of the task.

## Verification

Run the checks relevant to the files changed. Before handing off a broad or
security-sensitive change, run the full suite:

```bash
PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 python3 tests/test_bridge.py
node tests/test_config.js
node tests/test_connection.js
node tests/test_model.js
node tests/test_row_model.js
node tests/test_mark.js
node tests/test_credentials.js
python3 -m py_compile bin/oh-bridge tests/*.py
```

When available, also run `qmllint`, `qmlformat` in check/read-only mode, and
`omarchy plugin validate .`. Do not make tests depend on a real openHAB, real
credentials, global Python packages, or internet access. The bridge tests use
`tests/fake_openhab.py`, a stdlib `http.server` that speaks the exact REST/SSE
contract this plugin consumes.

## Code review rules

- Flag every new path that can leak or retain a token, bypass TLS verification,
  honor proxy environment variables, or reuse a credential across origins.
- Flag connection changes that can accept stale generations, claim readiness
  before synchronization, retry indefinitely without exponential backoff, or
  leave authenticated sockets open after configuration removal.
- Flag keyring flows without terminal cleanup and an operation deadline.
- Flag destructive credential actions without a clearly identified target and
  an appropriate confirmation or recovery path.
- Flag raw openHAB item names or states written to logs or IPC beyond the
  controlled row projection, even when the current fixtures do not contain
  secrets.
- Require behavioral regression tests for security and lifecycle fixes. Source
  string assertions may supplement but must not replace behavior tests.