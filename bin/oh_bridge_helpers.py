"""Pure helpers for bin/oh-bridge, split out so tests can import them.

Nothing here touches network I/O except current_wifi_ssid(), which is only
consulted when a local URL is actually configured (see network_trusted).
"""

import re
import subprocess


def redact_for_log(text):
    """Keep anything that looks like a token or key out of logs."""
    if not isinstance(text, str):
        return text
    text = re.sub(r"Bearer\s+\S+", "Bearer [redacted]", text)
    text = re.sub(r"(token|key|secret)['\"]?\s*[:=]\s*['\"]?[^\s,'\"]+",
                  r"\1=[redacted]", text, flags=re.IGNORECASE)
    return text


def parse_wifi_ssid(text):
    """Parse nmcli -t -f ACTIVE,SSID output into the active SSID or ''.

    nmcli's terse output separates fields with ':' and escapes a literal ':'
    inside a field as '\\:'. We split on the first unescaped colon per line.
    """
    for line in text.splitlines():
        idx = -1
        for c, ch in enumerate(line):
            if ch == ":" and (c == 0 or line[c - 1] != "\\"):
                idx = c
                break
        if idx == -1:
            continue
        active = line[:idx]
        ssid = line[idx + 1:].replace("\\:", ":").replace("\\\\", "\\")
        if active == "yes" and ssid:
            return ssid
    return ""


def trusted_network_list(value):
    return [name.strip() for name in (value or "").split(",") if name.strip()]


def current_wifi_ssid(timeout_ms=4000):
    """Active Wi-Fi SSID, or '' on any failure. Fail closed: no NetworkManager,
    an nmcli error/timeout, or no active connection all read as "not trusted".
    """
    try:
        proc = subprocess.run(["nmcli", "-t", "-f", "ACTIVE,SSID", "device", "wifi"],
                              capture_output=True, text=True,
                              timeout=(timeout_ms / 1000.0))
        if proc.returncode != 0:
            return ""
        return parse_wifi_ssid(proc.stdout or "")
    except Exception:
        return ""


def network_trusted(local_url, trusted_network):
    """Gate for the optional local URL. localUrl is only ever tried on a
    network the user explicitly trusted; every failure path falls back to the
    primary URL rather than guessing."""
    if not (local_url or "").strip():
        return False
    trusted = trusted_network_list(trusted_network)
    if not trusted:
        return False
    ssid = current_wifi_ssid()
    return bool(ssid and ssid in trusted)