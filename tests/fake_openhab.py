"""A stdlib-only fake openHAB REST/SSE server for bridge tests.

Speaks the exact contract this plugin consumes:

  GET  /rest/items?recursive=false        -> inventory array
  GET  /rest/events/states                -> SSE stream (ready then tracked maps)
  POST /rest/events/states/{connId}       -> start tracking a list of items
  POST /rest/items/{name}                 -> command (body = command string)

Basic auth with the username-form API token (`token:`). Pass `auth="user:pass"`
to demand a real username/password pair instead. A mismatched credential
returns 401 everywhere. 404 on unknown items/paths.
"""

import base64
import http.server
import json
import socket
import socketserver
import threading
import urllib.parse

BASE_CONTENT = [
    {"name": "Living_Room", "type": "Group", "label": "Living Room", "state": "",
     "metadata": {"semantics": {"value": "Location_Indoor"}}, "groupNames": []},
    {"name": "Living_Room_Ceiling", "type": "Group", "label": "Ceiling", "state": "",
     "metadata": {"semantics": {"value": "Equipment_LightSource_Bulb",
                                "config": {"hasLocation": "Living_Room"}}}, "groupNames": []},
    {"name": "Living_Room_Ceiling_Dimmer", "type": "Dimmer", "label": "Ceiling Lamp",
     "state": "60",
     "metadata": {"semantics": {"value": "Point_Control_Percentage",
                                "config": {"isPointOf": "Living_Room_Ceiling"}}}, "groupNames": []},
    {"name": "Kitchen_Island_Switch", "type": "Switch", "label": "Island Lights",
     "state": "ON",
     "metadata": {"semantics": {"value": "Point_Control_OnOff"}}, "groupNames": []},
    {"name": "Office_Desk_Pendant_Color", "type": "Color", "label": "Desk Pendant",
     "state": "200,100,80",
     "metadata": {"semantics": {"value": "Point_Control_Color"}}, "groupNames": []},
]


def state_type(item_type):
    mapping = {"Dimmer": "Percent", "Color": "Color"}
    return mapping.get(item_type, item_type)


class FakeOpenHAB:
    def __init__(self, token="sekrit", items=None, authed=True, auth=None):
        self.token = token
        self.authed = authed
        # auth="user:pass" demands the username/password form; None demands
        # the username-form API token (token:).
        self.auth = auth
        self.items = {i["name"]: dict(i) for i in (items or BASE_CONTENT)}
        self.conn_events = {}
        self.conn_count = 0
        self.last_event_type = None
        self.accept_tracking = True  # fail a POST /rest/events/states/{id}
        self.huge_sse_line = False  # send an over-long SSE line (no newline first)

    def push(self, name, state):
        """Simulate openHAB pushing a state change out the tracked stream."""
        conn = self.conn_events.get("stream")
        if conn:
            conn.send_frame({name: {"state": state, "type": state_type(self.items[name]["type"])}})

    def http_thread_factory(self):
        server = self
        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *args):
                pass

            def _authed(self):
                if not server.authed:
                    return True
                if server.auth is not None:
                    user, _, secret = server.auth.partition(":")
                    expected = "Basic " + base64.b64encode(
                        ("%s:%s" % (user, secret)).encode()).decode()
                else:
                    expected = "Basic " + base64.b64encode(
                        ("%s:" % server.token).encode()).decode()
                return self.headers.get("Authorization") == expected

            def _respond(self, code, body=None, ctype="application/json",
                         headers=None, stream=False):
                self.send_response(code)
                self.send_header("Content-Type", ctype)
                for key, value in (headers or {}).items():
                    self.send_header(key, value)
                raw = body if isinstance(body, bytes) else (json.dumps(body).encode() if body is not None else b"")
                if not stream:
                    self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                if raw and not stream:
                    self.wfile.write(raw)
                if stream:
                    return
                remaining = int(self.headers.get("Content-Length") or 0)
                if remaining:
                    self.rfile.read(remaining)

            def do_GET(self):
                parsed = urllib.parse.urlsplit(self.path)
                if not self._authed():
                    self._respond(401, {"error": "unauthorized"})
                    return
                if parsed.path == "/rest/items":
                    if urllib.parse.parse_qs(parsed.query).get("recursive") == ["false"]:
                        self._respond(200, list(server.items.values()))
                    else:
                        self._respond(200, list(server.items.values()))
                    return
                if parsed.path == "/rest/events/states":
                    self._sse()
                    return
                self._respond(404, {"error": "not found"})

            def do_POST(self):
                if not self._authed():
                    self._respond(401, {"error": "unauthorized"})
                    return
                parsed = urllib.parse.urlsplit(self.path)
                if parsed.path.startswith("/rest/events/states/"):
                    if not server.accept_tracking:
                        self._respond(500, {"error": "boom"})
                        return
                    conn_id = urllib.parse.unquote(parsed.path[len("/rest/events/states/"):])
                    length = int(self.headers.get("Content-Length") or 0)
                    try:
                        names = json.loads(self.rfile.read(length).decode())
                    except ValueError:
                        self._respond(400, {"error": "bad json"})
                        return
                    if conn_id in server.conn_events:
                        server.conn_events[conn_id].set_tracked(names)
                    self._respond(200, "OK")
                    return
                if parsed.path.startswith("/rest/items/"):
                    name = urllib.parse.unquote(parsed.path[len("/rest/items/"):])
                    item = server.items.get(name)
                    if item is None:
                        self._respond(404, {"error": "no item"})
                        return
                    length = int(self.headers.get("Content-Length") or 0)
                    command = self.rfile.read(length).decode().strip()
                    if item["type"] == "Switch" and command in ("ON", "OFF"):
                        item["state"] = command
                    elif item["type"] in ("Dimmer",) and (command.isdigit() or command in ("ON", "OFF")):
                        item["state"] = "OFF" if command == "OFF" else command
                    else:
                        item["state"] = command
                    server.push(name, item["state"])
                    self._respond(200, "OK")
                    return
                self._respond(404, {"error": "not found"})

            def _sse(self):
                conn_id = "fake-%d" % server.conn_count
                server.conn_count += 1
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Connection", "keep-alive")
                self.send_header("X-Accel-Buffering", "no")
                self.end_headers()
                if server.huge_sse_line:
                    self.wfile.write(b"x" * 262200 + b"\n")
                    self.wfile.flush()
                # ready frame
                self.wfile.write(b"event: ready\ndata: " + conn_id.encode() + b"\n\n")
                self.wfile.flush()
                conn = SSEConnection(server, conn_id, self)
                server.conn_events[conn_id] = conn
                server.conn_events["stream"] = conn
                conn.serve()
                server.conn_events.pop(conn_id, None)
                if server.conn_events.get("stream") is conn:
                    server.conn_events.pop("stream", None)

        return Handler

    def start(self, port=0):
        handler = self.http_thread_factory()
        self.httpd = socketserver.ThreadingTCPServer(("127.0.0.1", port), handler)
        self.httpd.daemon_threads = True
        self.port = self.httpd.server_address[1]
        self.base = "http://127.0.0.1:%d" % self.port
        self._thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self._thread.start()
        return self

    def stop(self):
        if hasattr(self, "httpd"):
            self.httpd.shutdown()
            self.httpd.server_close()


class SSEConnection:
    """Back half of the SSE handler: holds the tracked set and can push maps."""

    def __init__(self, server, conn_id, handler):
        self.server = server
        self.conn_id = conn_id
        self.handler = handler
        self._lock = threading.Lock()
        self._closed = threading.Event()
        self._tracked = []

    def set_tracked(self, names):
        with self._lock:
            self._tracked = list(names)
            snapshot = {}
            for name in names:
                item = self.server.items.get(name)
                if item is not None:
                    snapshot[name] = {"state": item["state"],
                                      "type": state_type(item["type"])}
        if snapshot:
            self.send_frame(snapshot)

    def send_frame(self, payload):
        with self._lock:
            if self._closed.is_set():
                return False
            try:
                data = json.dumps(payload).encode()
                self.handler.wfile.write(b"data: " + data + b"\n\n")
                self.handler.wfile.flush()
                return True
            except (BrokenPipeError, OSError):
                self._closed.set()
                return False

    def serve(self):
        conn = self.handler.connection
        conn.settimeout(0.4)
        while not self._closed.is_set():
            try:
                chunk = conn.recv(1024, socket.MSG_PEEK)
            except (socket.timeout, BlockingIOError):
                continue
            except OSError:
                break
            if not chunk:
                break
        self._closed.set()