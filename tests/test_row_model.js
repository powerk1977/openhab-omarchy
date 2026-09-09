// Node tests for EntityStore.js semantic-model store + computeTabs + RowModel.
// Run: node tests/test_row_model.js

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

const M = load("Model.js")
const E = load("EntityStore.js")
const R = load("RowModel.js")

// A fixture shaped like a trimmed openHAB inventory (the shape the bridge
// drains from /rest/items?recursive=false).
const INVENTORY = [
  { name: "gLights", type: "Group", label: "Lights", tags: [], groupNames: [],
    metadata: { semantics: { value: "Group" } } },
  { name: "LivingRoom", type: "Group", label: "Living Room",
    metadata: { semantics: { value: "Location_Indoor" } }, groupNames: [] },
  { name: "LivingRoom_Ceiling", type: "Group", label: "Ceiling",
    metadata: { semantics: { value: "Equipment_LightSource_Bulb",
                             config: { hasLocation: "LivingRoom" } } }, groupNames: [] },
  { name: "LivingRoom_Ceiling_Dimmer", type: "Dimmer", label: "Ceiling Lamp",
    metadata: { semantics: { value: "Point_Control_Percentage",
                             config: { isPointOf: "LivingRoom_Ceiling" } } }, groupNames: [] },
  { name: "Outside", type: "Group", label: "Outdoor",
    metadata: { semantics: { value: "Location_Indoor" } }, groupNames: [] },
  { name: "Outside_Flood", type: "Group", label: "Flood",
    metadata: { semantics: { value: "Equipment_LightSource_FloodLight",
                             config: { hasLocation: "Outside" } } }, groupNames: [] },
  { name: "Outside_Flood_Switch", type: "Switch", label: "Flood Light",
    metadata: { semantics: { value: "Point_Control_OnOff",
                             config: { isPointOf: "Outside_Flood" } } }, groupNames: [] },
  { name: "CoffeeMaker", type: "Switch", label: "Coffee Maker", groupNames: [],
    metadata: {} },
  { name: "Boiler_Temp", type: "Number:Temperature", label: "Boiler Temp", groupNames: [],
    metadata: {} },
]

const STATES = {
  "LivingRoom_Ceiling_Dimmer": { state: "70", type: "Percent" },
  "Outside_Flood_Switch": { state: "ON", type: "OnOff" },
  "CoffeeMaker": { state: "OFF", type: "OnOff" },
  "Boiler_Temp": { state: "65.3 °C", type: "Quantity" }
}

let passed = 0
let failed = 0
function check(name, cond, detail) {
  if (cond) { passed++; console.log("ok   - " + name) }
  else { failed++; console.log("FAIL - " + name + (detail ? " :: " + detail : "")) }
}

// --- inventory
const store = E.makeStore(M)
let inv = store.applyInventory(INVENTORY)
check("inventory counts 9", store.count() === 9)
check("inventory added 9", inv.added.length === 9)
const reapply = store.applyInventory(INVENTORY)
check("reapply no additions", reapply.added.length === 0 && reapply.removed.length === 0)
const inv2 = store.applyInventory(INVENTORY.slice(0, 5))
check("removed detected", inv2.removed.length === 4, inv2.removed.join(","))
store.applyInventory(INVENTORY)

// --- states merge onto items
store.pushStates(STATES)
check("state merged onto item", store.item("LivingRoom_Ceiling_Dimmer").state === "70")
check("state merged switch", store.item("Outside_Flood_Switch").state === "ON")
check("unknown state ignored", store.item("Unknown") === null)
check("pushStates returns touched names", store.pushStates({ "Outside_Flood_Switch": { state: "OFF", type: "OnOff" } }).join() === "Outside_Flood_Switch")

// --- display name inheritance
check("point inherits equipment label", store.displayNameFor(store.item("LivingRoom_Ceiling_Dimmer")) === "Ceiling")
check("non-semantic uses own label", store.displayNameFor(store.item("CoffeeMaker")) === "Coffee Maker")
check("areaName via point->equipment->location", store.areaNameFor(store.item("Outside_Flood_Switch")) === "Outside")
check("unplaced area empty", store.areaNameFor(store.item("CoffeeMaker")) === "")

// --- semantic detection
check("hasSemantics true", store.hasSemantics() === true)

// --- computeTabs (favorites-first panel)
const tabs = store.computeTabs(
  ["LivingRoom_Ceiling_Dimmer", "Outside_Flood_Switch", "CoffeeMaker"],
  false, {}, function(n) { return n })
check("grouping off -> single favorites tab", tabs.length === 1 && tabs[0].id === "favorites")
check("favorites tab preserves picked order", tabs[0].itemNames.join(",") ===
      "LivingRoom_Ceiling_Dimmer,Outside_Flood_Switch,CoffeeMaker")

const areaLabels = store.orderedLocations().reduce(function(m, l) {
  m[l.name] = l.label; return m
}, {})
function areaFor(name) {
  if (name.indexOf("LivingRoom") === 0) return "LivingRoom"
  if (name.indexOf("Outside") === 0) return "Outside"
  return ""
}
const grouped = store.computeTabs(
  ["LivingRoom_Ceiling_Dimmer", "Outside_Flood_Switch", "CoffeeMaker"],
  true, areaLabels, areaFor)
check("grouping on -> favorites first", grouped[0].id === "favorites")
check("grouping on -> area tabs sorted by label", grouped[1].id === "area:LivingRoom"
      && grouped[2].id === "area:Outside", grouped.map(function(t) { return t.id }).join(","))
check("grouping on -> unplaced land in other last", grouped[grouped.length - 1].id === "other"
      && grouped[grouped.length - 1].itemNames.join(",") === "CoffeeMaker")
const living = grouped.filter(function(t) { return t.id === "area:LivingRoom" })[0]
check("area tab title from label", living.title === "Living Room", living.title)
check("area tab carries its items in order", living.itemNames.join(",") === "LivingRoom_Ceiling_Dimmer")
check("empty picks -> favorites only even when grouped", store.computeTabs([], true, {}, function() { return "" }).length === 1)

// --- RowModel projection
const projected = R.project({
  rowKind: "entity", itemName: "LivingRoom_Ceiling_Dimmer", name: "Ceiling",
  subtitle: "70%", badge: "", icon: "x", type: "Dimmer", isOn: true,
  pending: false, available: true, controlKind: "toggle",
  brightness: true, brightnessValue: 70, color: false,
  areaName: "LivingRoom", equipmentName: "LivingRoom_Ceiling"
})
check("rowmodel carries fields", projected.itemName === "LivingRoom_Ceiling_Dimmer" && projected.name === "Ceiling")
check("rowmodel flag coercion", projected.brightness === true && projected.isOn === true)

// --- non-semantic store still indexes control items
const store3 = E.makeStore(M)
store3.applyInventory([
  { name: "Desk_Lamp", type: "Switch", label: "Desk Lamp", groupNames: [], metadata: {} }
])
store3.pushStates({ "Desk_Lamp": { state: "ON", type: "OnOff" } })
check("fallback entity indexed", store3.item("Desk_Lamp") !== null)
check("fallback sorted index includes it", store3.sortedItemNames().join(",") === "Desk_Lamp")

console.log("\npython-style summary: %d passed, %d failed", passed, failed)
process.exit(failed ? 1 : 0)