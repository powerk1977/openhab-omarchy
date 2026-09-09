// Node tests for Credentials.js (credential normalization + classification).
// Run: node tests/test_credentials.js

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

const C = load("Credentials.js")

let passed = 0
let failed = 0
function check(name, cond, detail) {
  if (cond) { passed++; console.log("ok   - " + name) }
  else { failed++; console.log("FAIL - " + name + (detail ? " :: " + detail : "")) }
}

// normalizeSecret: paste artifacts
check("norm: plain token", C.normalizeSecret("sekrit") === "sekrit")
check("norm: surrounding whitespace", C.normalizeSecret("  sekrit  ") === "sekrit")
check("norm: double-quoted", C.normalizeSecret('"sekrit"') === "sekrit")
check("norm: single-quoted", C.normalizeSecret("'sekrit'") === "sekrit")
check("norm: quoted with spaces", C.normalizeSecret('  "  sekrit  "  ') === "sekrit")
check("norm: bearer prefix", C.normalizeSecret("Bearer sekrit") === "sekrit")
check("norm: Bearer case + extra space", C.normalizeSecret("bEaReR   sekrit") === "sekrit")
check("norm: quoted bearer", C.normalizeSecret('"Bearer  sekrit"') === "sekrit")
check("norm: trailing newline", C.normalizeSecret("sekrit\n") === "sekrit")
check("norm: empty -> empty", C.normalizeSecret("") === "")
check("norm: blank -> empty", C.normalizeSecret("   ") === "")
check("norm: bearer on its own stays", C.normalizeSecret("Bearer") === "Bearer")

// classify: which form a stored string is
check("classify: oh. token", C.classify("oh.abc123") === "token")
check("classify: oh. token keeps ':'", C.classify("oh.a:b") === "token")
check("classify: plain token", C.classify("sekrit") === "token")
check("classify: user:pass", C.classify("alice:s3cret") === "userpass")
check("classify: user with empty pass", C.classify("alice:") === "userpass")
check("classify: bearer-pasted token", C.classify("Bearer oh.abc") === "token")
check("classify: empty -> ''", C.classify("") === "")
check("classify: blank -> ''", C.classify("   ") === "")

// encode: three settings fields -> one stored string
let e = C.encode({ token: "oh.abc", username: "alice", password: "x" })
check("encode: token wins when both filled", e.value === "oh.abc" && e.form === "token")
e = C.encode({ token: "Bearer oh.abc", username: "alice", password: "x" })
check("encode: token normalized before winning", e.value === "oh.abc" && e.form === "token")
e = C.encode({ token: "", username: "alice", password: "s3cret" })
check("encode: userpass pair", e.value === "alice:s3cret" && e.form === "userpass")
check("encode: no error", e.error === "")
e = C.encode({ token: "", username: " alice ", password: "s3cret" })
check("encode: username trimmed", e.value === "alice:s3cret" && e.form === "userpass")
e = C.encode({ token: "", username: "alice", password: "s3cret\n" })
check("encode: password newline stripped", e.value === "alice:s3cret")
e = C.encode({ token: "", username: "", password: "" })
check("encode: all blank -> keep stored", e.value === "" && e.form === "" && e.error === "")
e = C.encode({})
check("encode: empty input -> keep stored", e.value === "" && e.form === "" && e.error === "")
e = C.encode({ token: "", username: "alice", password: "" })
check("encode: username only -> error", e.error.indexOf("both") !== -1)
e = C.encode({ token: "", username: "", password: "x" })
check("encode: password only -> error", e.error.indexOf("both") !== -1)
e = C.encode({ token: "", username: "alice", password: "s:cret" })
check("encode: ':' in password rejected", e.error.indexOf(":") !== -1 && e.error.indexOf("token") !== -1)
e = C.encode({ token: "", username: "al:i", password: "x" })
check("encode: ':' in username rejected", e.error.indexOf("token") !== -1)

console.log()
console.log("passed: " + passed + "   failed: " + failed)
process.exit(failed ? 1 : 0)