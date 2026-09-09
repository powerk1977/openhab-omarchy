# Security Policy

## Reporting a vulnerability

If you find a security issue in this plugin, report it privately rather than
opening a public issue. Use one of:

- **GitHub private vulnerability reporting** — _Security_ → _Report a vulnerability_
  (preferred; notifies the maintainer directly).
- **Email fallback** — contact the maintainer via the address listed on the
  repository profile with `[SECURITY]` in the subject line.

Please include: the openHAB and omarchy versions involved, the plugin version,
a description of the issue, and (if possible) steps to reproduce. Do not
include your live API token or real connection details.

## Scope

This plugin is a client of the openHAB REST API. Security-sensitive areas are:

- **Credential handling** — the API token / username-password pair in the
  system keyring, its transport to the bridge over stdin, and its absence from
  config files, process arguments, logs, IPC output, and fixtures.
- **The local-network URL gate** — the `localUrl` / `trustedNetwork` Wi-Fi
  check that prevents a token from being sent to an untrusted network.
- **Transport hardening** — TLS verification, proxy bypass, and explicit
  plaintext `http://` warnings.
- **The REST/SSE surface consumed** — inventory, tracked-states stream, and
  item commands.

Issues in the openHAB server itself do not belong here; report those to the
openHAB project.

## Supported versions

Security fixes are applied to the latest release. Older versions are not
maintained; if a fix matters to you, upgrade.

## Disclosure

We aim to acknowledge reports within 5 business days and will coordinate a fix
and public disclosure with the reporter.