.pragma library

// Pure connection and credential identity helpers. Keeping URL normalization
// outside Service.qml makes the security boundary testable with Node as well
// as usable by the QML service.

// Mirrors bin/oh-bridge's Bridge.trusted_network_list: a comma-separated list
// of Wi-Fi network names, since a router commonly broadcasts more than one
// (separate 2.4GHz/5GHz SSIDs). Kept here so the settings UI's notion of "is
// a trusted network actually configured" cannot drift from the bridge's — a
// field containing only commas or whitespace must count as empty in both.
function trustedNetworkList(value) {
  return String(value || "").split(",")
    .map(function(name) { return name.trim() })
    .filter(function(name) { return name.length > 0 })
}

// Mirrors bin/oh-bridge's current_wifi_ssid line parsing: nmcli -t's terse
// output is "active:ssid" per line, with a literal ':' inside a field escaped
// as '\:'. Settings.qml uses this only to suggest a value for the trusted
// network field — the bridge is the actual security boundary and re-checks
// the current network independently in Python before ever using a local URL.
function parseNmcliActiveSsid(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var splitAt = -1
    for (var c = 0; c < line.length; c++) {
      if (line[c] === ":" && line[c - 1] !== "\\") { splitAt = c; break }
    }
    if (splitAt === -1) continue
    if (line.slice(0, splitAt) !== "yes") continue
    var ssid = line.slice(splitAt + 1).replace(/\\:/g, ":").replace(/\\\\/g, "\\")
    if (ssid) return ssid
  }
  return ""
}

function preparedUrl(value) {
  var text = String(value || "").trim()
  if (!text) return ""
  if (text.indexOf("://") === -1) text = "https://" + text.replace(/^\/+/, "")
  return text
}

function normalizeOrigin(value) {
  var text = preparedUrl(value)
  if (!text || /\s/.test(text)) return ""

  var schemeEnd = text.indexOf("://")
  if (schemeEnd <= 0) return ""
  var inputScheme = text.slice(0, schemeEnd).toLowerCase()
  var secure = inputScheme === "https"
  var plain = inputScheme === "http"
  if (!secure && !plain) return ""

  var rest = text.slice(schemeEnd + 3)
  var boundary = rest.search(/[\/?#]/)
  var authority = boundary === -1 ? rest : rest.slice(0, boundary)
  if (!authority || authority.indexOf("@") !== -1) return ""

  var host = ""
  var portText = ""
  if (authority.charAt(0) === "[") {
    var close = authority.indexOf("]")
    if (close <= 1) return ""
    host = authority.slice(0, close + 1).toLowerCase()
    if (!/^\[[0-9a-f:.]+\]$/.test(host) || host.indexOf(":") === -1) return ""
    var suffix = authority.slice(close + 1)
    if (suffix) {
      if (suffix.charAt(0) !== ":") return ""
      portText = suffix.slice(1)
      if (!portText) return ""
    }
  } else {
    if (authority.indexOf(":") !== authority.lastIndexOf(":")) return ""
    var colon = authority.lastIndexOf(":")
    host = (colon === -1 ? authority : authority.slice(0, colon)).toLowerCase()
    portText = colon === -1 ? "" : authority.slice(colon + 1)
    if (colon !== -1 && !portText) return ""
    if (!/^[a-z0-9._\-]+$/.test(host)) return ""
  }

  if (!host) return ""
  var port = portText ? Number(portText) : (secure ? 443 : 80)
  if (!/^\d*$/.test(portText) || !Number.isInteger(port) || port < 1 || port > 65535) {
    return ""
  }

  return (secure ? "https" : "http") + "://" + host + ":" + port
}

// Which connection the bridge is running for, as reconciliation compares it.
// Same semantics as the hass reference: the origin is the credential scope,
// but the bridge connects to the whole URL, so the signature folds in the
// raw URL and the local/trusted fields.
function signature(demoMode, value, localValue, trustedNetwork) {
  if (demoMode) return "demo"
  var origin = normalizeOrigin(value)
  if (!origin) return ""
  var text = origin + "|" + String(value || "").trim()
  var local = String(localValue || "").trim()
  if (local) text += "|" + local
  var trust = String(trustedNetwork || "").trim()
  if (trust) text += "|" + trust
  return text
}

function acceptsGeneration(activeGeneration, eventGeneration) {
  return typeof eventGeneration === "number"
    && Number.isInteger(eventGeneration)
    && eventGeneration === activeGeneration
}

function reducePhase(state, event) {
  var current = state || { phase: "idle", error: "", errorKind: "" }
  if (!event || event.ev !== "phase"
      || !acceptsGeneration(current.generation, event.generation)) {
    return { accepted: false, state: current }
  }
  var phase = String(event.phase || "")
  if (["idle", "connecting", "connected", "error"].indexOf(phase) === -1) {
    return { accepted: false, state: current }
  }
  return {
    accepted: true,
    state: {
      generation: current.generation,
      phase: phase,
      error: typeof event.error === "string" ? event.error : "",
      errorKind: typeof event.errorKind === "string" ? event.errorKind : ""
    }
  }
}