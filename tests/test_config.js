// Node tests for ConfigStore.js (config normalization + serialization).
// Run: node tests/test_config.js

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

const C = load("ConfigStore.js")

let passed = 0
let failed = 0
function check(name, cond, detail) {
  if (cond) { passed++; console.log("ok   - " + name) }
  else { failed++; console.log("FAIL - " + name + (detail ? " :: " + detail : "")) }
}

// parse: default
let r = C.parse(null)
check("parse null -> empty config", r.config.baseUrl === "" && r.config.demoMode === false)
check("parse null -> no error", r.error === "")

// parse: malformed
r = C.parse("not valid json {{{")
check("parse garbage -> error", r.error.indexOf("JSON") !== -1)
check("parse garbage -> empty baseUrl", r.config.baseUrl === "")
check("parse garbage -> safe defaults", Array.isArray(r.config.expandedEquipment) && r.config.expandedEquipment.length === 0)

// parse: valid
r = C.parse(JSON.stringify({
  baseUrl: "http://192.0.2.1:8080",
  localUrl: "http://192.168.1.10:8080",
  trustedNetwork: "HomeWiFi, Tenda_5G",
  demoMode: true,
  expandedEquipment: ["Living_Room_Ceiling", "Kitchen_Island"]
}))
check("parse valid: baseUrl", r.config.baseUrl === "http://192.0.2.1:8080")
check("parse valid: trustedNetwork", r.config.trustedNetwork === "HomeWiFi, Tenda_5G")
check("parse valid: demo", r.config.demoMode === true)
check("parse valid: expanded list", r.config.expandedEquipment.length === 2)

// full JSON array is a shape error
r = C.parse("[1,2,3]")
check("parse array -> error", r.error !== "")

// merge: patch only touched keys
const base = { baseUrl: "a", localUrl: "", trustedNetwork: "", demoMode: false, expandedEquipment: [] }
const merged = C.merge(base, { baseUrl: "b", demoMode: true })
check("merge keeps untouched keys", merged.localUrl === "" && merged.trustedNetwork === "")
check("merge applies patch", merged.baseUrl === "b" && merged.demoMode === true)
check("merge returns detached object", merged !== base)

// itemName sanitizer
check("itemName clean", C.itemName("Living_Room_Ceiling_Dimmer") === "Living_Room_Ceiling_Dimmer")
check("itemName allows spaces", C.itemName("Bathroom Light") === "Bathroom Light")
check("itemName rejects script chars", C.itemName("Foo;rm -rf /") === "")
check("itemName rejects empty", C.itemName("") === "")
check("itemName rejects 201 chars", C.itemName("a".repeat(201)) === "")

// itemList
check("itemList strips junk + dedupes", C.itemList(["a", "b;c", "a", "", 7]).join(",") === "a")

// favorites / panel order
r = C.parse(JSON.stringify({
  favorites: ["Living_Room_Ceiling", "Kitchen_Island", "Bad;Name", "Living_Room_Ceiling"],
  panelOrder: ["Missing", "Kitchen_Island", "Living_Room_Ceiling"]
}))
check("favorites deduped + junk-scrubbed, stale kept", r.config.favorites.join(",") === "Living_Room_Ceiling,Kitchen_Island")
check("panelOrder keeps only favorites, in order", r.config.panelOrder.join(",") === "Kitchen_Island,Living_Room_Ceiling")

// favorites defaulting to empty, panelOrder empty default
r = C.parse("{}")
check("no favorites default empty", r.config.favorites.length === 0)
check("no panelOrder default empty", r.config.panelOrder.length === 0)
check("groupByArea defaults off", r.config.groupByArea === false)
check("selectedTab defaults favorites", r.config.selectedTab === "favorites")

// demo favorites seeding (first run) vs explicit empty (user cleared)
const DEFAULTS = ["Demo_A", "Demo_B"]
r = C.parse(null, DEFAULTS)
check("demoFavorites seeded from defaults when key absent", r.config.demoFavorites.join(",") === "Demo_A,Demo_B")
r = C.parse(JSON.stringify({ demoFavorites: [] }), DEFAULTS)
check("explicit empty demoFavorites stays empty", r.config.demoFavorites.length === 0)
r = C.parse(JSON.stringify({ demoFavorites: ["X"], demoPanelOrder: ["Y", "X"] }), DEFAULTS)
check("demoPanelOrder normalized against demoFavorites", r.config.demoPanelOrder.join(",") === "X")

// groupByArea + selectedTab round-trip
r = C.parse(JSON.stringify({ groupByArea: "yes", selectedTab: "area:Kitchen" }))
check("groupByArea strict bool", r.config.groupByArea === false)
check("selectedTab parsed", r.config.selectedTab === "area:Kitchen")
r = C.parse(JSON.stringify({ groupByArea: true }))
check("groupByArea true", r.config.groupByArea === true)

// serialize round-trips
const s = C.serialize({ baseUrl: "x", localUrl: "", trustedNetwork: "", demoMode: true, expandedEquipment: [] })
const back = C.parse(s)
check("serialize round-trip", back.config.baseUrl === "x" && back.config.demoMode === true)

// merge carries the new keys
const mbase = { baseUrl: "a", demoMode: false, favorites: [], panelOrder: [],
                demoFavorites: [], demoPanelOrder: [], groupByArea: false,
                selectedTab: "favorites", localUrl: "", trustedNetwork: "",
                expandedEquipment: [] }
const m = C.merge(mbase, { groupByArea: true })
check("merge applies new key", m.groupByArea === true && m.selectedTab === "favorites")

console.log("\npython-style summary: %d passed, %d failed", passed, failed)
process.exit(failed ? 1 : 0)