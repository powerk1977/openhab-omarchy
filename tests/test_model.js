// Node tests for Model.js (openHAB display/capability mapping).
// Run: node tests/test_model.js

const fs = require("fs")
const path = require("path")
const vm = require("vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*\n?/, "")
const sandbox = { Qt: undefined, console: { log: () => {}, warn: () => {} } }
vm.createContext(sandbox)
vm.runInContext(source, sandbox)
const M = sandbox // Model.js exposes functions on the sandbox global

let passed = 0
let failed = 0

function check(name, cond, detail) {
  if (cond) { passed++; console.log("ok   - " + name) }
  else { failed++; console.log("FAIL - " + name + (detail ? " :: " + detail : "")) }
}

function item(type, state, extra) {
  return Object.assign({ name: "X", type: type, state: state, label: "X" }, extra || {})
}

// --- type/state helpers
check("typeOf returns string", M.typeOf({ type: "Switch" }) === "Switch")
check("cleaned trims", M.cleaned(" ON ") === "ON")
check("brightnessOf Dimmer", M.brightnessOf(item("Dimmer", "60")) === 60)
check("brightnessOf Dimmer OFF", M.brightnessOf(item("Dimmer", "0")) === 0)
check("brightnessOf Color", M.brightnessOf(item("Color", "200,100,80")) === 80)
check("brightnessOf Color bad", M.brightnessOf(item("Color", "200,100")) === -1)
check("brightnessOf Color 0", M.brightnessOf(item("Color", "0,0,0")) === 0)

// --- isOn semantics
check("isOn Switch ON", M.isOn(item("Switch", "ON")) === true)
check("isOn Switch OFF", M.isOn(item("Switch", "OFF")) === false)
check("isOn Dimmer 60", M.isOn(item("Dimmer", "60")) === true)
check("isOn Dimmer 0", M.isOn(item("Dimmer", "0")) === false)
check("isOn Color b0", M.isOn(item("Color", "200,100,0")) === false)
check("isOn Player PLAY", M.isOn(item("Player", "PLAY")) === true)
check("isOn Player PAUSE", M.isOn(item("Player", "PAUSE")) === false)
check("isOn Contact OPEN", M.isOn(item("Contact", "OPEN")) === true)

// --- availability
check("unavailable on NULL", M.isUnavailable(item("Dimmer", "NULL")) === true)
check("unavailable on UNDEF", M.isUnavailable(item("Dimmer", "UNDEF")) === true)
check("unavailable on empty", M.isUnavailable(item("Dimmer", "")) === true)
check("unavailable on real", M.isUnavailable(item("Dimmer", "33")) === false)
check("isLightsViewItem Switch", M.isLightsViewItem(item("Switch", "ON")) === true)
check("isLightsViewItem Dimmer", M.isLightsViewItem(item("Dimmer", "33")) === true)
check("isLightsViewItem Color", M.isLightsViewItem(item("Color", "0,0,0")) === true)
check("isLightsViewItem Rollershutter", M.isLightsViewItem(item("Rollershutter", "50")) === false)
check("isLightsViewItem Group", M.isLightsViewItem(item("Group", "ON")) === false)

// --- toggle commands
check("toggleCommand switch on -> OFF", M.toggleCommand(item("Switch", "ON"), true) === "OFF")
check("toggleCommand switch off -> ON", M.toggleCommand(item("Switch", "OFF"), false) === "ON")
check("toggleCommand dimmer -> OFF/ON", M.toggleCommand(item("Dimmer", "40"), true) === "OFF")
check("brightnessCommand 0 -> OFF", M.brightnessCommand(item("Dimmer", "40"), 0) === "OFF")
check("brightnessCommand 42 -> 42", M.brightnessCommand(item("Dimmer", "40"), 42) === "42")
check("brightnessCommand clamp 150 -> 100", M.brightnessCommand(item("Dimmer", "40"), 150) === "100")
check("brightnessCommand Color -> percent", M.brightnessCommand(item("Color", "0,0,0"), 75) === "75")

// --- display
check("displayState Switch", M.displayState(item("Switch", "ON")) === "On")
check("displayState Dimmer 60", M.displayState(item("Dimmer", "60")) === "60%")
check("displayState Dimmer 0", M.displayState(item("Dimmer", "0")) === "Off")
check("displayState Contact", M.displayState(item("Contact", "OPEN")) === "Open")
check("displayState Number UoM", M.displayState(item("Number:Temperature", "21.5 °C")) === "21.5 °C")
check("displayState unavailable", M.displayState(item("Dimmer", "NULL")) === "Unavailable")
check("badgeText Color", M.badgeText(item("Color", "200,100,80")) === "80%")

// --- capabilities
let cap = M.capabilitiesFor(item("Dimmer", "60"))
check("caps Dimmer: controllable+toggle+bright", cap.controllable && cap.toggle && cap.brightness)
check("caps Dimmer: not color", cap.color === false)
check("caps Color: color", M.capabilitiesFor(item("Color", "0,0,0")).color === true)
check("caps N/A when unavailable", M.capabilitiesFor(item("Dimmer", "NULL")).controllable === false)
check("caps Switch: no brightness", M.capabilitiesFor(item("Switch", "ON")).brightness === false)
check("controlKind Dimmer toggle", M.controlKind(item("Dimmer", "60")) === "toggle")
check("controlKind Rollershutter none", M.controlKind(item("Rollershutter", "50")) === "none")

// --- redaction
check("redactState Image", M.redactState(item("Image", "http://cam/snapshot?token=abc")) === "[redacted]")
check("redactState password item", M.redactState({ name: "Secret_ApiKey", type: "String", state: "abc123" }) === "[redacted]")
check("redactState normal", M.redactState(item("Switch", "ON")) === "ON")

console.log("\npython-style summary: %d passed, %d failed", passed, failed)
process.exit(failed ? 1 : 0)