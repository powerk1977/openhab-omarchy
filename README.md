# openHAB for Omarchy

View and control your openHAB devices from the Omarchy bar.

Quickshell plugin for **Omarchy 4**. Browse your house by Location → Equipment,
toggle switches, and slide dimmers — or turn on demo mode to try it with a fake
house before you point it at a real instance.

> Not affiliated with or endorsed by the openHAB project.

## What it does

A small panel in the bar (keyboard-shortcut friendly, matching every other
panel in the shell) that lists your home by room:

- **Location → Equipment → Points**, straight from your items' semantic model
  (`metadata.semantics`). No manual device list to maintain.
- **Switch / Dimmer / Color** points get an on/off toggle.
- Dimmers and Color lights get an expandable brightness slider (0–100, sent on
  release).
- Everything else is listed for visibility only.

## Connecting

Either enter the API token in the overlay (`s` with the panel open) or place it
in your keyring yourself with exactly this origin label:

```
secret-tool store --service openhab --label "openHAB (Omarchy)" [your token]
```

The token is kept where it belongs — in the system keyring, never in config
files, arguments, or logs. The panel talks to your instance over its **REST
API** (`/rest/items`) plus a **Server-Sent Events** stream for live state
updates, with the connect token sent over HTTP **Basic** auth.

### A note on the wider openHAB deployment posture

Because the bridge talks HTTP directly at the OS-level script (not inside the
openHAB JVM), general hardening guidance applies: this plugin does live
updates, so it submits updates and commands over an authenticated channel, and
it treats any openHAB-mounted filesystem poorly held — do not grant the HTTP
user or bind a LAN-facing port on an instance whose `openhab/runtime/*` is
world-writable, keep tokens scoped to your dedicated bot item, avoid opening
the hmui/Shell port to unknown networks, and remember Main-Interface shutdown
port can be reached via that same network as the REST/SSE the bridge uses.
These are properties of the openHAB deployment, not of this plugin; check them
at install time and on updates.

### Local network URL

If your instance is reachable both over the internet and on your LAN, you can
set a LAN URL. It shares the same token and is **only ever tried while
connected to a Wi-Fi network you whitelist by name** — on any other network it
is never used, so the token can't be shipped to whatever happens to answer at
that address elsewhere. The `nmcli` check is read-only and, if it fails, the
plugin deliberately fails closed (falls straight back to the primary URL).

## Demo mode

Before you enter a token, or any time you want a preview, turn on **Demo mode**
in the overlay. The panel renders a small fake house — a few rooms with
switches, dimmers, and a colour light — driven by the same bridge code path as
a real instance, so what you see is exactly what a live connection behaves
like.

## Keyboard

`j` / `k` (or `↑` / `↓`) move between room rows and their expanded controls.
`enter` toggles the selected switch. `e` expands the selected light's
brightness slider, `←` / `→` adjust it (and `enter` commits). `s` opens
settings, `r` refreshes, `esc` closes. `tab` moves to the next bar panel.

## Lights, and everything else

| Point type | Control |
|---|---|
| `Switch` | On/off |
| `Dimmer` | On/off + brightness slider |
| `Color` | On/off + brightness slider (colour wheel planned) |
| `Rollershutter`, `Player`, `Contact`, `Number` | Listed; control coming |

## Building / running from source

```bash
omarchy plugin validate .
ln -s "$(pwd)" ~/.config/omarchy/plugins/openhab
```

Restart the shell (or let hot-reload pick it up on save). The panel is
`openhab` in the default section of the bar.

## Tests

No network or instance required.

```bash
# JS model layer
for t in config connection model row_model credentials mark; do node "tests/test_$t.js"; done

# Python bridge (demo + fake server)
PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 python3 tests/test_bridge.py

# Bridge byte-compiles cleanly
python3 -m py_compile bin/oh-bridge tests/*.py
```

## Security

* Token lives only in the system keyring, entered through the overlay or
  `secret-tool`. It reaches the bridge over stdin and is never in argv, logs,
  error output, or IPC.
* HTTP Basic is the transport credential; a non-HTTPS URL gets an explicit
  plaintext warning in the UI.
* TLS verification is on; the connection bypasses any ambient proxy and
  disables compression to keep the token out of a middlebox cache.
* Token, key, secret, and `Image` item states are redacted from logs and IPC.
* Item names are treated as untrusted server data and stored in maps that
  can't be poisoned via `__proto__`-style keys.

## AI disclosure

This repository follows the
[ai-disclosure convention](https://github.com/ggfevans/ai-disclosure); see
[`AI_DISCLOSURE.md`](AI_DISCLOSURE.md).

## License

MIT. This is an independent adaptation inspired by the Konrad Krawczyk /
`konradk` Home Assistant for Omarchy plugin (same bar interaction model,
openHAB-native REST + SSE bridge); see THIRD_PARTY_NOTICES.