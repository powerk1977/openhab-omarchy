.pragma library

// Stateless view logic: raw openHAB items in, drawable values out. No QML
// types and no side effects, so it is testable outside the shell.
//
// openHAB item states are strings. A Switch is "ON"/"OFF", a Dimmer is a
// 0-100 percent, a Color is "h,s,b" (each 0-100), a Rollershutter a percent,
// a Player is PLAY/PAUSE/NEXT/PREVIOUS/REWIND/FASTFORWARD, a Contact is
// OPEN/CLOSED. Number items (and UoM variants) carry the unit in the state
// itself ("21.5 °C"), so display needs no unit plumbing from the server.

// The control types the P1 panel renders as lights. Rollershutter/Player get
// their rows in a later phase.
var LIGHT_TYPES = ["Switch", "Dimmer", "Color"]

// Demo house pickup for the favorites-first panel: one point per location,
// in a sensible panel order, so demo mode shows content on first run. See
// bin/oh-bridge DEMO_INVENTORY. Seeded only when config.json never defined
// demoFavorites (ConfigStore.parse).
var DEMO_DEFAULT_FAVORITES = [
  "Living_Room_Ceiling_Dimmer",
  "Kitchen_Island_Switch",
  "Office_Desk_Pendant_Color"
]

function cleaned(value) {
  if (typeof value !== "string") return ""
  var trimmed = value.trim()
  return trimmed.length ? trimmed : ""
}

function typeOf(item) {
  return item && typeof item.type === "string" ? item.type : ""
}

function itemOf(state, items) {
  var text = String(state || "")
  return items && items[text] ? items[text] : null
}

function isUnavailable(item) {
  if (!item) return false
  var state = cleaned(item.state)
  return state === "" || state === "NULL" || state === "UNDEF"
}

function isAvailable(item) {
  return !!item && !isUnavailable(item)
}

// An item with no readable size — contact, group switch state — answers
// "unavailable" by state name only.
function isLightsViewItem(item) {
  return isAvailable(item) && LIGHT_TYPES.indexOf(typeOf(item)) !== -1
}

function isOn(item) {
  if (!item) return false
  var type = typeOf(item)
  var state = cleaned(item.state)
  if (type === "Switch") return state === "ON"
  if (type === "Player") return state === "PLAY"
  if (type === "Dimmer" || type === "Color") return brightnessOf(item) > 0
  if (type === "Rollershutter") {
    var position = Number(state)
    return typeof position === "number" && isFinite(position) && position > 0
  }
  if (type === "Contact") return state === "OPEN"
  return false
}

// Dimmer: the state is the 0-100 percent. Color: "h,s,b", brightness is the
// third field. Unavailable or OFF returns 0.
function brightnessOf(item) {
  if (!item) return -1
  var type = typeOf(item)
  var state = cleaned(item.state)
  if (type === "Dimmer") {
    var value = Number(state)
    return isFinite(value) ? Math.min(Math.max(value, 0), 100) : -1
  }
  if (type === "Color") {
    var parts = state.split(",")
    if (parts.length < 3) return -1
    var b = Number(parts[2])
    return isFinite(b) ? Math.min(Math.max(b, 0), 100) : -1
  }
  return -1
}

function hsColor(item) {
  if (!item || typeOf(item) !== "Color") return null
  var parts = cleaned(item.state).split(",")
  if (parts.length < 3) return null
  var hue = Number(parts[0])
  var saturation = Number(parts[1])
  if (!isFinite(hue) || !isFinite(saturation)) return null
  return {
    hue: Math.min(Math.max(hue, 0), 360),
    saturation: Math.min(Math.max(saturation, 0), 100)
  }
}

// The command string a toggle sends for the current state.
function toggleCommand(item, currentlyOn) {
  var type = typeOf(item)
  if (type === "Switch") return currentlyOn ? "OFF" : "ON"
  // Dimmer/Color OFF is a brightness command? No — openHAB dimmers accept
  // ON/OFF/0-100; sending ON/OFF is always safe and keeps the last level.
  return currentlyOn ? "OFF" : "ON"
}

function brightnessCommand(item, percent) {
  var type = typeOf(item)
  var clamped = Math.min(Math.max(Math.round(Number(percent) || 0), 0), 100)
  if (clamped <= 0) return "OFF"
  if (type === "Dimmer" || type === "Color") return String(clamped)
  return "ON"
}

// ---------------------------------------------------------------- display

function capitalize(value) {
  var text = String(value || "")
  return text.length ? text.charAt(0).toUpperCase() + text.slice(1) : ""
}

function displayState(item) {
  if (!item) return ""
  if (isUnavailable(item)) return "Unavailable"
  var type = typeOf(item)
  var state = cleaned(item.state)
  if (type === "Switch") return state === "ON" ? "On" : "Off"
  if (type === "Dimmer") {
    var level = brightnessOf(item)
    return level < 0 ? state : (level <= 0 ? "Off" : Math.round(level) + "%")
  }
  if (type === "Color") {
    var b = brightnessOf(item)
    return b < 0 ? state : (b <= 0 ? "Off" : Math.round(b) + "%")
  }
  if (type === "Contact") return state === "OPEN" ? "Open" : "Closed"
  if (type === "Player") {
    if (state === "PLAY") return "Playing"
    if (state === "PAUSE") return "Paused"
    return state
  }
  if (type === "Rollershutter") {
    var position = Number(state)
    if (isFinite(position)) return Math.round(position) + " %"
    return state
  }
  // Number (incl. UoM), String, DateTime: the state already reads right.
  return state
}

// The summary line under a row's name (hass calls it the subtitle).
function subtitle(item) {
  if (!item || isUnavailable(item)) return ""
  var type = typeOf(item)
  if (type === "Contact") return displayState(item)
  if (LIGHT_TYPES.indexOf(type) !== -1) return displayState(item)
  return ""
}

function badgeText(item) {
  if (!item) return "Unavailable"
  if (isUnavailable(item)) return "Unavailable"
  var type = typeOf(item)
  if (type === "Player") return displayState(item)
  if (LIGHT_TYPES.indexOf(type) !== -1) return displayState(item)
  if (type === "Contact") return displayState(item)
  return displayState(item)
}

// ------------------------------------------------------------ capabilities

function capabilitiesFor(item) {
  if (!item) {
    return {
      controllable: false, toggle: false, brightness: false, color: false,
      available: false, type: ""
    }
  }
  var type = typeOf(item)
  var available = isAvailable(item)
  var controllable = available && LIGHT_TYPES.indexOf(type) !== -1
  return {
    controllable: controllable,
    toggle: controllable,
    brightness: controllable && (type === "Dimmer" || type === "Color"),
    color: controllable && type === "Color",
    available: available,
    type: type
  }
}

function controlKind(item) {
  return capabilitiesFor(item).toggle ? "toggle" : "none"
}

// ---------------------------------------------------------------- icons

// Material Design Icons as Nerd Font glyphs, same codepoints the hass plugin
// uses (read by glyph name from the Nerd Font; a wrong one renders as a box).
// openHAB items have no per-item device_class, so the mapping is by item type
// with a state-aware lightbulb reading for lights. The bar mark itself is the
// openHAB logo drawn by OpenHabIcon, not a font glyph.
var FALLBACK_ICON = "󰾰" // md-devices

function iconFor(item) {
  var type = typeOf(item)
  if (LIGHT_TYPES.indexOf(type) !== -1) return "󰌵" // md-lightbulb (tinted vs dimmed by row)
  if (type === "Player") return "󰝚"                // md-music
  if (type === "Contact") return "󰠚"               // md-door
  return "󰾰"                                       // md-devices
}

// ---------------------------------------------------------------- redaction

// Item state that can carry a signed URL (camera snapshot) or a service
// credential must never reach IPC or logs.
function redactState(item) {
  if (!item || typeOf(item) === "Image") return "[redacted]"
  var name = cleaned(item.name).toLowerCase()
  if (["password", "secret", "token", "api_key", "apikey", "pin"].some(
      function(needle) { return name.indexOf(needle) !== -1 })) {
    return "[redacted]"
  }
  return String(item.state || "")
}