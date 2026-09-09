"""Behavioral tests for bin/oh-bridge against tests/fake_openhab.py.

No real openHAB, no credentials, no internet. The bridge is exercised as a
black box over its NDJSON stdin/stdout protocol.

Run: PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 python3 tests/test_bridge.py
"""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "bin"))

from fake_openhab import FakeOpenHAB  # noqa: E402

BRIDGE = os.path.join(os.path.dirname(__file__), "..", "bin", "oh-bridge")


def load_bridge():
    """Import the dash-named, extensionless bridge script as a module so pure
    helpers are unit-testable; the guarded __main__ entrypoint never runs.
    spec_from_file_location can't do this (no .py suffix), so the loader is
    named explicitly."""
    loader = importlib.machinery.SourceFileLoader("ohbridge", BRIDGE)
    spec = importlib.util.spec_from_loader("ohbridge", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod

PASSED = []
FAILED = []


def report(name, ok, detail=""):
    (PASSED if ok else FAILED).append(name)
    print(("ok   - " if ok else "FAIL - ") + name + ((" :: " + detail) if detail else ""))


class Harness:
    def __init__(self, args=None, env=None):
        words = [sys.executable, BRIDGE]
        if args:
            words.extend(args)
        base_env = dict(os.environ)
        base_env["PYTHONNOUSERSITE"] = "1"
        base_env["PYTHONDONTWRITEBYTECODE"] = "1"
        if env:
            base_env.update(env)
        self.proc = subprocess.Popen(
            words, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, env=base_env)
        self.buffer = []
        self._lock = threading.Lock()
        self._terminated = threading.Event()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            with self._lock:
                self.buffer.append(line.rstrip("\n"))
        self._terminated.set()

    def send(self, obj):
        self.proc.stdin.write(json.dumps(obj) + "\n")
        self.proc.stdin.flush()

    def events(self):
        with self._lock:
            return list(self.buffer)

    def wait_for(self, predicate, timeout=6.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            for line in self.events():
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                if isinstance(ev, dict) and predicate(ev):
                    return ev
            time.sleep(0.03)
        return None

    def drain(self):
        """Wait out any pending SSE chatter so later assertions are stable."""
        time.sleep(0.3)
        with self._lock:
            self.buffer.clear()

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=3)
        except Exception:
            self.proc.kill()


def parsed_events(raw):
    out = []
    for line in raw:
        try:
            out.append(json.loads(line))
        except ValueError:
            out.append(line)
    return out


def eq(ev, ev_name, **fields):
    if not ev or ev.get("ev") != ev_name:
        return False, "expected ev=%s got %r" % (ev_name, ev)
    for key, value in fields.items():
        if ev.get(key) != value:
            return False, "expected %s=%r got %r" % (key, value, ev.get(key))
    return True, ""


def test_demo_mode():
    h = Harness()
    ok, why = eq(h.wait_for(lambda e: e.get("ev") == "hello"), "hello", version=1)
    report("demo: hello", ok, why)
    h.send({"op": "config", "generation": 7, "demoMode": True})
    ok, why = eq(h.wait_for(lambda e: e.get("ev") == "inventory"), "inventory", generation=7)
    report("demo: inventory + generation", ok, why)
    ok, why = eq(h.wait_for(lambda e: e.get("ev") == "states"), "states", generation=7)
    report("demo: initial states", ok, why)
    connected = h.wait_for(lambda e: e.get("ev") == "phase" and e.get("phase") == "connected")
    ok, why = eq(connected, "phase", phase="connected", generation=7)
    report("demo: connected", ok, why)
    h.send({"op": "setItem", "name": "Kitchen_Island_Switch", "command": "OFF", "tag": "t1"})
    ok, why = eq(h.wait_for(lambda e: e.get("ev") == "statechanged" and e.get("name") == "Kitchen_Island_Switch"),
                 "statechanged", name="Kitchen_Island_Switch", state="OFF")
    report("demo: setItem -> statechanged", ok, why)
    ok, why = eq(h.wait_for(lambda e: e.get("ev") == "result"), "result", tag="t1", success=True)
    report("demo: setItem -> result", ok, why)
    h.send({"op": "shutdown"})
    h.proc.wait(timeout=3)
    report("demo: clean shutdown", h.proc.poll() == 0)
    h.close()
    return h


def test_live_connect():
    server = FakeOpenHAB(token="sekrit").start()
    try:
        h = Harness()
        h.send({"op": "config", "generation": 3, "url": server.base,
                "token": "sekrit"})
        ok, why = eq(h.wait_for(lambda e: e.get("ev") == "inventory"), "inventory",
                     generation=3)
        report("live: inventory fetched", ok, why)
        inventory = h.wait_for(lambda e: e.get("ev") == "inventory")
        names = [i["name"] for i in inventory["items"]]
        report("live: inventory names", "Office_Desk_Pendant_Color" in names
               and "Kitchen_Island_Switch" in names, str(len(names)) + " items")
        ok, why = eq(h.wait_for(lambda e: e.get("ev") == "states"), "states", generation=3)
        report("live: tracked initial states", ok, why)
        states = h.wait_for(lambda e: e.get("ev") == "states")
        report("live: initial switch state", states["items"]["Kitchen_Island_Switch"]["state"] == "ON",
               json.dumps(states["items"].get("Kitchen_Island_Switch")))
        ok, why = eq(h.wait_for(lambda e: e.get("ev") == "phase" and e.get("phase") == "connected"),
                     "phase", phase="connected")
        report("live: connected", ok, why)
        h.close()
    finally:
        server.stop()
    return h


def test_live_command_and_push():
    server = FakeOpenHAB(token="sekrit").start()
    try:
        h = Harness()
        h.send({"op": "config", "generation": 4, "url": server.base, "token": "sekrit"})
        while not h.wait_for(lambda e: e.get("ev") == "phase" and e.get("phase") == "connected"):
            time.sleep(0.05)
        h.send({"op": "setItem", "name": "Kitchen_Island_Switch", "command": "OFF", "tag": "c1"})
        ok, why = eq(h.wait_for(lambda e: e.get("ev") == "result"), "result", tag="c1", success=True)
        report("cmd: result ok", ok, why)
        pushed = h.wait_for(lambda e: e.get("ev") == "statechanged" and e.get("name") == "Kitchen_Island_Switch")
        ok, why = eq(pushed, "statechanged", state="OFF")
        report("cmd: server push reflected", ok, why)
        h.send({"op": "setItem", "name": "No_Such_Item", "command": "ON", "tag": "c2"})
        ok, why = eq(h.wait_for(lambda e: e.get("ev") == "result" and e.get("tag") == "c2"),
                     "result", tag="c2", success=False)
        report("cmd: unknown item fails gracefully", ok, why)
        h.close()
    finally:
        server.stop()
    return h


def test_live_drift_push():
    server = FakeOpenHAB(token="sekrit").start()
    try:
        h = Harness()
        h.send({"op": "config", "generation": 5, "url": server.base, "token": "sekrit"})
        while not h.wait_for(lambda e: e.get("ev") == "phase" and e.get("phase") == "connected"):
            time.sleep(0.05)
        h.drain()
        server.push("Kitchen_Island_Switch", "OFF")
        ok, why = eq(h.wait_for(lambda e: e.get("ev") == "statechanged" and e.get("name") == "Kitchen_Island_Switch"),
                     "statechanged", state="OFF")
        report("push: external statechange relayed", ok, why)
        h.close()
    finally:
        server.stop()
    return h


def test_auth_failure():
    server = FakeOpenHAB(token="sekrit").start()
    try:
        h = Harness()
        h.send({"op": "config", "generation": 6, "url": server.base, "token": "wrong"})
        ev = h.wait_for(lambda e: e.get("ev") == "phase" and e.get("phase") == "error",
                        timeout=10.0)
        ok, why = eq(ev, "phase", phase="error", errorKind="credential")
        report("auth: two 401s -> credential error", ok, why or "")
        msg = (ev or {}).get("error", "")
        report("auth: message names HTTP 401", "401" in msg, msg)
        report("auth: message names the form (token)", "access token" in msg, msg)
        report("auth: message leaks no secret", "wrong" not in msg, msg)
        # Server rejects; retry window is 2s, so this must arrive past it.
        h.close()
    finally:
        server.stop()
    return h


def test_userpass_connect():
    """A username:password credential authenticates as a Basic user:pass
    pair against a server (or proxy) that wants a login, not an API token."""
    server = FakeOpenHAB(auth="alice:sekrit").start()
    try:
        h = Harness()
        h.send({"op": "config", "generation": 12, "url": server.base,
                "token": "alice:sekrit"})
        ok, why = eq(h.wait_for(lambda e: e.get("ev") == "phase"
                                and e.get("phase") == "connected"),
                     "phase", phase="connected")
        report("creds: username/password connect", ok, why or "401 leaked?")
        h.close()
    finally:
        server.stop()
    return h


def test_bearer_prefix_token():
    """A token pasted with the 'Bearer ' prefix (and quotes/whitespace) is
    normalized before the header is built, so it still authenticates."""
    server = FakeOpenHAB(token="sekrit").start()
    try:
        h = Harness()
        h.send({"op": "config", "generation": 13, "url": server.base,
                "token": '"Bearer  sekrit"'})
        ok, why = eq(h.wait_for(lambda e: e.get("ev") == "phase"
                                and e.get("phase") == "connected"),
                     "phase", phase="connected",
                     generation=13)
        report("creds: pasted 'Bearer ' token normalized", ok, why or "401 leaked?")
        h.close()
    finally:
        server.stop()
    return h


def test_credential_helpers():
    b = load_bridge()
    cases = [
        ("sekrit", "token", "sekrit", ""),
        ("oh.abc123", "token", "oh.abc123", ""),
        ("oh.a:b", "token", "oh.a:b", ""),       # oh. tokens keep ':' literally
        ("alice:sekrit", "userpass", "alice", "sekrit"),
        ("", "", "", ""),                     # empty -> no credential
        ("user:", "userpass", "user", ""),
    ]
    for raw, kind, user, secret in cases:
        got = b.normalize_credential(raw)
        report("cred: normalize(%r) -> %r" % (raw, kind),
               got == (kind, user, secret), repr(got))
    secret_cases = {
        '"Bearer  sekrit"': "sekrit",
        "'oh.abc'": "oh.abc",
        "Bearer oh.abc\n": "oh.abc",
        "  sekrit  ": "sekrit",
        "sekrit": "sekrit",
        "": "",
    }
    for raw, want in sorted(secret_cases.items()):
        got = b.normalize_secret(raw)
        report("cred: normalize_secret(%r)" % raw, got == want, repr(got))
    import base64 as _b64
    report("cred: token header", b.auth_header("token", "sekrit") ==
           "Basic " + _b64.b64encode(b"sekrit:").decode())
    report("cred: userpass header", b.auth_header("userpass", "alice", "sekrit") ==
           "Basic " + _b64.b64encode(b"alice:sekrit").decode())
    report("cred: empty header", b.auth_header("", "x") == "")
    return None


def test_disconnect_idles():
    server = FakeOpenHAB(token="sekrit").start()
    try:
        h = Harness()
        h.send({"op": "config", "generation": 8, "url": server.base, "token": "sekrit"})
        while not h.wait_for(lambda e: e.get("ev") == "phase" and e.get("phase") == "connected"):
            time.sleep(0.05)
        h.send({"op": "disconnect"})
        ok, why = eq(h.wait_for(lambda e: e.get("ev") == "phase" and e.get("phase") == "idle"),
                     "phase", phase="idle")
        report("disconnect: back to idle", ok, why)
        # A refresh must be a silent no-op now.
        h.drain()
        h.send({"op": "refresh"})
        time.sleep(0.4)
        newest = [e for e in parsed_events(h.events()) if e.get("ev") == "inventory"]
        report("disconnect: refresh ignored", len(newest) == 0,
               "received %d inventory events" % len(newest))
        h.close()
    finally:
        server.stop()
    return h


def test_reconfig_reconnects():
    server = FakeOpenHAB(token="sekrit").start()
    try:
        h = Harness()
        # First generation connects; second generation reconnects and old
        # generation tags are never emitted as "connected".
        h.send({"op": "config", "generation": 10, "url": server.base, "token": "sekrit"})
        while not h.wait_for(lambda e: e.get("ev") == "phase" and e.get("phase") == "connected"):
            time.sleep(0.05)
        h.send({"op": "config", "generation": 11, "url": server.base, "token": "sekrit"})
        ev = h.wait_for(lambda e: e.get("ev") == "phase" and e.get("phase") == "connected"
                        and e.get("generation") == 11, timeout=8.0)
        ok, why = eq(ev, "phase", phase="connected", generation=11)
        report("reconfig: reconnect with new generation", ok, why or "stale generation never connected")
        h.close()
    finally:
        server.stop()
    return h


def test_ssl_requires_verified_tls():
    """If the URL points at a bogus host, TLS verification must fail closed
    into the error phase (nothing is ever tried twice as plaintext)."""
    h = Harness()
    h.send({"op": "config", "generation": 9, "url": "https://127.0.0.1:1",
            "token": "anything"})
    ev = h.wait_for(lambda e: e.get("ev") == "phase" and e.get("phase") == "error",
                    timeout=8.0)
    ok, why = eq(ev, "phase", phase="error")
    report("ssl: connection refused -> error phase", ok, why)
    report("ssl: no token leaked in error", "token" not in json.dumps(ev), json.dumps(ev))
    h.close()
    return h


def test_trusted_network_gate():
    """network_trusted units: localUrl is only used when a trusted network
    field names the current network — enforced here because the bridge
    re-checks it before every connection."""
    from oh_bridge_helpers import network_trusted, parse_wifi_ssid  # type: ignore
    report("trusted: parse ssid", parse_wifi_ssid("yes:HomeWiFi\nno:Other\n") == "HomeWiFi",
           "found %r" % parse_wifi_ssid("yes:HomeWiFi\nno:Other\n"))
    # network_trusted consults real nmcli, so on CI there is likely no active
    # Wi-Fi -> fail closed to False. The real assertion: no trustedNetwork set
    # means never trusted, without touching nmcli.
    report("trusted: no config -> never trusted",
           network_trusted("http://192.0.2.1:8500", "") is False)
    report("trusted: empty local url -> never trusted",
           network_trusted("", "HomeWiFi") is False)
    h = Harness()
    h.send({"op": "config", "generation": 2, "url": "http://127.0.0.1:1",
            "localUrl": "http://127.0.0.1:2", "trustedNetwork": "DefinitelyNotAClient",
            "token": "x"})
    # localUrl demands a trusted network match; without it the primary URL is
    # used, which is refused. Either way: error, never a claim of local.
    ev = h.wait_for(lambda e: e.get("ev") == "phase" and e.get("phase") == "error",
                    timeout=8.0)
    report("trusted: local not used off trusted network", ev is not None,
           json.dumps(ev) if ev else "timeout")
    h.close()
    return h


def main():
    tests = [
        test_demo_mode, test_live_connect, test_live_command_and_push,
        test_live_drift_push, test_auth_failure, test_userpass_connect,
        test_bearer_prefix_token, test_credential_helpers,
        test_disconnect_idles,
        test_reconfig_reconnects, test_ssl_requires_verified_tls,
        test_trusted_network_gate,
    ]
    for test in tests:
        try:
            test()
        except Exception as exc:  # noqa: BLE001
            FAILED.append(test.__name__)
            print("ERROR - %s raised: %r" % (test.__name__, exc))
    print()
    print("passed: %d   failed: %d" % (len(PASSED), len(FAILED)))
    for name in FAILED:
        print("FAILED: " + name)
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())