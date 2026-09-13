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
- **Scenes**: instances with `Scene` items get a SCENES band above the item
  list (hidden when there are none) — cursor to a chip and press `enter` to
  run it. Rules disabled in openHAB are dimmed with their tooltip; a running
  scene's chip spins until openHAB reports it finished.
- **Favorites view**: star any item from Settings → Items browser to pin it
  for quick access. Favorites is the panel's default view, with every location
  still one entry away in the view dropdown.
- **Pop-out window**: a button in the panel header detaches the whole panel
  into its own floating window — move and resize it anywhere, with the same
  keyboard control and live view.

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

## Scenes

When your instance has `Scene` items, a **SCENES** band appears between the
panel header and the item list. `j` / `k` move the cursor; moving up past the
first item reaches the band, where `←` / `→` pick a chip and `enter` runs the
highlighted scene. A scene you ran with `enter` behaves identically to running
it in the openHAB UI. With no `Scene` items the band is hidden entirely.

## Favorites

Press `s` and open the **Items** tab: every item gets a star button to pin it
("Add to panel"). Pinned items are the panel's default view — the dropdown
above the item list shows **Favorites** and one entry per location — so your
most-used switches stay one keypress away. The tab's right column ("IN THE
PANEL") lists what's pinned, with up/down buttons to reorder and a star to
unpin.

## Pop-out window

The button at the top-right of the panel header pops the panel out into its
own floating window, detached from the bar. Drag it to any screen and resize
it freely — it keeps the full panel behaviour: keyboard navigation, every
shortcut (`r` refresh, `e` expand, `s` settings), and `esc` closes it back
into the bar popup.

## Keyboard

`j` / `k` (or `↑` / `↓`) move between room rows and their expanded controls.
`enter` toggles the selected switch. `e` expands the selected light's
brightness slider, `←` / `→` adjust it (and `enter` commits). `s` opens
settings, `r` refreshes, `esc` closes. `tab` moves to the next bar panel.
With scenes active, `←` / `→` on the SCENES band select a chip and `enter`
runs it (see [Scenes](#scenes)).

## Lights, and everything else

| Point type | Control |
|---|---|
| `Switch` | On/off |
| `Dimmer` | On/off + brightness slider |
| `Color` | On/off + brightness slider (colour wheel planned) |
| `Rollershutter`, `Player`, `Contact`, `Number` | Listed; control coming |

## Install

From the marketplace-ready source:

```bash
omarchy plugin add https://github.com/powerk1977/openhab-omarchy.git --enable
```

The panel lands in the bar's right section by default. To place it
elsewhere, move it:

```bash
omarchy bar move io.github.powerk1977.openhab --section right
```

First time through, open the panel with `s` and enter your API token, or store
it in the keyring yourself — see [Connecting](#connecting).

## Build from source

```bash
omarchy plugin validate .
ln -s "$(pwd)" ~/.config/omarchy/plugins/io.github.powerk1977.openhab
```

Restart the shell (or let hot-reload pick it up on save). The panel is
`io.github.powerk1977.openhab` in the right section of the bar.

## Remove

```bash
omarchy plugin remove io.github.powerk1977.openhab
```

If you stored a token in the keyring yourself (rather than through the
overlay), also delete it:

```bash
secret-tool clear --service openhab
```

## External dependencies

- **Python 3.11 or newer** — `bin/oh-bridge` uses only the Python standard
  library; nothing is pip-installed and no virtual environment is required.
- **`secret-tool`** — system keyring access for the connect token.
- **`nmcli`** (optional) — read-only lookup of the current Wi-Fi network name
  used by the local-network URL gate. If it is missing, the plugin fails
  closed: the local URL is never used and the overlay shows no network
  suggestion.

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