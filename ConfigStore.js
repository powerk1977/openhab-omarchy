.pragma library

// openHAB item names are arbitrary strings; unlike hass entity ids they carry
// no enforced lowercase-letter domain prefix. Every persisted list is still
// validated so a hand-edited config.json can never smuggle junk in.
var KEYS = [
  "baseUrl", "localUrl", "trustedNetwork", "demoMode",
  "favorites", "demoFavorites", "panelOrder", "demoPanelOrder",
  "groupByArea", "selectedTab",
  "expandedEquipment"
]

function itemName(value) {
  if (typeof value !== "string" || !value) return ""
  if (value.length > 200) return ""
  if (!/^[A-Za-z0-9_#:\-\.\s]+$/.test(value)) return ""
  return value
}

function itemList(value) {
  if (!Array.isArray(value)) return []
  var out = []
  var seen = {}
  for (var i = 0; i < value.length; i++) {
    var id = itemName(value[i])
    if (!id || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

// The panel order may only reference starred items (ghosts never survive a
// config edit). Validated entries keep their relative order; favorites the
// order does not mention are appended — old configs had no order at all.
function normalizedOrder(value, favorites) {
  var selected = {}
  for (var f = 0; f < favorites.length; f++) selected[favorites[f]] = true
  var requested = itemList(value)
  var out = []
  var included = {}
  for (var i = 0; i < requested.length; i++) {
    if (selected[requested[i]]) {
      out.push(requested[i])
      included[requested[i]] = true
    }
  }
  for (var n = 0; n < favorites.length; n++) {
    if (!included[favorites[n]]) out.push(favorites[n])
  }
  return out
}

// The demo house's pickup, so demo mode shows a panel the first time it runs
// instead of an empty "nothing pinned" hint. Live instances start bare.
function parse(text, demoDefaults) {
  var raw = {}
  var error = ""
  try {
    raw = text ? JSON.parse(text) : {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      raw = {}
      error = "config.json must contain a JSON object"
    }
  } catch (exception) {
    raw = {}
    error = "config.json is not valid JSON"
  }

  var favorites = itemList(raw.favorites)
  // An explicitly empty demoFavorites stays empty (the user cleared it); the
  // demo defaults only seed a config that never defined the key.
  var hasDemoFavorites = raw && Object.prototype.hasOwnProperty.call(raw, "demoFavorites")
  var demoFavorites = hasDemoFavorites ? itemList(raw.demoFavorites)
    : (Array.isArray(demoDefaults) ? demoDefaults.slice() : [])

  return {
    error: error,
    config: {
      baseUrl: typeof raw.baseUrl === "string" ? raw.baseUrl : "",
      // Optional alternate address for the same openHAB instance — a LAN
      // address, say — tried first, but only on trustedNetwork. Shares
      // baseUrl's credential; never a separate keyring origin.
      localUrl: typeof raw.localUrl === "string" ? raw.localUrl : "",
      // The Wi-Fi network name localUrl requires a match against before it is
      // ever tried. See bin/oh-bridge's current_wifi_ssid.
      trustedNetwork: typeof raw.trustedNetwork === "string" ? raw.trustedNetwork : "",
      demoMode: raw.demoMode === true,
      favorites: favorites,
      demoFavorites: demoFavorites,
      panelOrder: normalizedOrder(raw.panelOrder, favorites),
      demoPanelOrder: normalizedOrder(raw.demoPanelOrder, demoFavorites),
      groupByArea: raw.groupByArea === true,
      selectedTab: typeof raw.selectedTab === "string" && raw.selectedTab
        ? raw.selectedTab : "favorites",
      expandedEquipment: itemList(raw.expandedEquipment)
    }
  }
}

function merge(current, patch) {
  var result = {}
  for (var i = 0; i < KEYS.length; i++) {
    var key = KEYS[i]
    result[key] = current[key]
  }
  for (var p = 0; p < KEYS.length; p++) {
    var patchKey = KEYS[p]
    if (Object.prototype.hasOwnProperty.call(patch || {}, patchKey)) {
      result[patchKey] = patch[patchKey]
    }
  }
  return result
}

function serialize(config) {
  return JSON.stringify(config, null, 2) + "\n"
}