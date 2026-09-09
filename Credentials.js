.pragma library

// Pure credential helpers. The keyring holds exactly one canonical string per
// origin: an API token verbatim (`oh.…`), or a `username:password` pair.
// Mirrors bin/oh-bridge's normalize_secret/normalize_credential so the two
// sides can never disagree about what a stored string means. No secrets ever
// end up in config.json — this only classifies, encodes and cleans in-memory
// values near the keyring/store boundary.

// Clean paste artifacts off a secret: stray whitespace, surrounding quotes,
// and a pasted `Bearer ` prefix (docs and copy-paste often include it).
function normalizeSecret(raw) {
  var v = String(raw == null ? "" : raw)
  v = v.replace(/[\r\n\x00]/g, "")
  v = v.trim().replace(/^['"]+|['"]+$/g, "")
  if (!v) return v
  if (v.toLowerCase().indexOf("bearer ") === 0) {
    v = v.slice("Bearer ".length).trim().replace(/^['"]+|['"]+$/g, "")
  }
  return v.trim()
}

// What flavor of credential a stored string is. '' for empty, 'token' for an
// API token, 'userpass' for a `user:password` pair. openHAB API tokens start
// with `oh.` and never contain ':', so a ':' marks a username/password pair.
function classify(stored) {
  var v = normalizeSecret(stored)
  if (!v) return ""
  var cut = v.indexOf(":")
  if (cut > 0 && v.toLowerCase().indexOf("oh.") !== 0) return "userpass"
  return "token"
}

// Encode the three settings fields into the single stored credential string,
// or set error when the input can't become one. Filling both forms is a
// no-op: the access token silently wins. Returns {value, form, error}.
function encode(parts) {
  var token = normalizeSecret(parts.token || "")
  if (token) return { value: token, form: "token", error: "" }
  var username = String(parts.username == null ? "" : parts.username).trim()
  var password = String(parts.password || "")
  if (!username && !password) return { value: "", form: "", error: "" }
  if (!username || !password) {
    return { value: "", form: "", error: "Fill in both a username and a password." }
  }
  if (username.indexOf(":") !== -1) {
    return { value: "", form: "", error: "Usernames can't contain ':' — use an access token instead." }
  }
  password = password.replace(/[\r\n\x00]/g, "")
  if (password.indexOf(":") !== -1) {
    return { value: "", form: "", error: "openHAB logins can't carry ':' inside a password — use an access token instead." }
  }
  return { value: username + ":" + password, form: "userpass",
           username: username, error: "" }
}