// Node tests for Connection.js (URL normalization, signatures, gating).
// Run: node tests/test_connection.js

const fs = require("fs")
const path = require("path")
const vm = require("vm")

function load(name) {
  const source = fs.readFileSync(path.join(__dirname, "..", name), "utf8")
    .replace(/^\.pragma library\s*\n?/, "")
  const sandbox = { Qt: undefined, console: { log: () => {}, warn: () => {} } }
  vm.createContext(sandbox)
  vm.runInContext(source, sandbox)
  return sandbox
}

const C = load("Connection.js")

let passed = 0
let failed = 0
function check(name, cond, detail) {
  if (cond) { passed++; console.log("ok   - " + name) }
  else { failed++; console.log("FAIL - " + name + (detail ? " :: " + detail : "")) }
}

// --- preparedUrl
check("prepared http", C.preparedUrl("http://192.0.2.1:8080") === "http://192.0.2.1:8080")
check("prepared missing scheme", C.preparedUrl("192.0.2.1:8080") === "https://192.0.2.1:8080")
check("prepared trims", C.preparedUrl("  https://openhab.home  ") === "https://openhab.home")

// --- normalizeOrigin
check("origin http host:port", C.normalizeOrigin("http://192.0.2.1:8080") === "http://192.0.2.1:8080")
check("origin https default port", C.normalizeOrigin("https://openhab.home") === "https://openhab.home:443")
check("origin http default port", C.normalizeOrigin("http://openhab.home") === "http://openhab.home:80")
check("origin strips path", C.normalizeOrigin("http://openhab.home/some/path?q=1") === "http://openhab.home:80")
check("origin lowercases host", C.normalizeOrigin("http://OpenHAB.HOME:8123/") === "http://openhab.home:8123")
check("origin rejects userinfo", C.normalizeOrigin("http://user:pw@host:80") === "")
check("origin rejects ftp scheme", C.normalizeOrigin("ftp://host:21") === "")
check("origin rejects whitespace", C.normalizeOrigin("http://ho st:1") === "")
check("origin rejects bad port", C.normalizeOrigin("http://host:99999") === "")
check("origin rejects garbage", C.normalizeOrigin("://no") === "")
check("origin rejects empty", C.normalizeOrigin("") === "")

// --- signature
check("sig demo flag ignores url", C.signature(true, "http://a:1", "", "") === "demo")
check("sig empty when unset", C.signature(false, "", "", "") === "")
check("sig folds local + trusted", C.signature(false, "http://a:1", "http://b:2", "Wifi") !==
      C.signature(false, "http://a:1", "", ""))
check("sig same for same inputs", C.signature(false, "http://a:1", "", "") === C.signature(false, "http://a:1", "", ""))

// --- generation filter
check("acceptsGeneration ok", C.acceptsGeneration(7, 7) === true)
check("acceptsGeneration rejects float", C.acceptsGeneration(7, 7.5) === false)
check("acceptsGeneration rejects stale", C.acceptsGeneration(7, 6) === false)
check("acceptsGeneration rejects non-number", C.acceptsGeneration(7, "7") === false)

// --- phase reducer
let s = C.reducePhase({ generation: 1, phase: "idle", error: "", errorKind: "" },
                      { ev: "phase", phase: "connecting", generation: 1 })
check("reducePhase records phase", s.accepted && s.state.phase === "connecting")
s = C.reducePhase({ generation: 1, phase: "connecting", error: "", errorKind: "" },
                  { ev: "phase", phase: "error", generation: 1, error: "boom", errorKind: "network" })
check("reducePhase error details", s.accepted && s.state.errorKind === "network")
s = C.reducePhase({ generation: 2, phase: "connected", error: "", errorKind: "" },
                  { ev: "phase", phase: "error", generation: 1 })
check("reducePhase stale gen rejected", !s.accepted && s.state.phase === "connected")
s = C.reducePhase({ generation: 1, phase: "connected", error: "", errorKind: "" },
                  { ev: "phase", phase: "bogus", generation: 1 })
check("reducePhase rejects bogus phase", !s.accepted && s.state.phase === "connected")

// --- trusted network list
check("trustedNetworkList parses", C.trustedNetworkList("HomeWiFi, Tenda_5G ,,  ") .join("|") === "HomeWiFi|Tenda_5G")
check("trustedNetworkList empty", C.trustedNetworkList(" , , ") .length === 0)

// --- nmcli parse
const nmcliOut = "yes:HomeWiFi\nno:Other\\:2.4G\n"
check("parseNmcliActiveSsid", C.parseNmcliActiveSsid(nmcliOut) === "HomeWiFi")

console.log("\npython-style summary: %d passed, %d failed", passed, failed)
process.exit(failed ? 1 : 0)