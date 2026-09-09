.pragma library

// Item state, index, and the Location->Equipment->Point projection built from
// the openHAB semantic model. Pure JavaScript (no Qt types) for Node tests;
// QML passes Model.js in via convertToJsValue.
//
// Semantic model: an item's metadata.semantics.value is "Point_*" for points
// (config.isPointOf names its equipment), "Equipment_*" for equipment groups
// (config.hasLocation and config.hasPoint), and "Location_*" for location
// groups. Instances that do not use the semantic model fall back to a flat
// "Other" section. Only the control types the panel renders (lights) get
// projected.

function makeStore(Model) {
  // items: name -> { name, type, label, category, tags, groupNames, group,
  //                  state, pointOf, locationFromConfig, semantics }
  // states: name -> { state, type } as pushed by the tracked-states SSE map.
  // Prototype-free: item names are server-controlled identifiers.
  var items = Object.create(null)
  var states = Object.create(null)

  function cleaned(value) {
    if (typeof value !== "string") return ""
    var trimmed = value.trim()
    return trimmed.length ? trimmed : ""
  }

  function semanticsOf(raw) {
    var semantics = raw.metadata && raw.metadata.semantics
    var value = cleaned(semantics && semantics.value)
    var config = (semantics && semantics.config) ? semantics.config : {}
    return { value: value, config: config }
  }

  function isPoint(raw) {
    return semanticsOf(raw).value.indexOf("Point_") === 0
  }

  function isLocation(raw) {
    return semanticsOf(raw).value.indexOf("Location_") === 0
  }

  var lastNames = []

  function reset() {
    items = {}
    states = {}
    lastNames = []
  }

  // Accept the unvalidated inventory array from the bridge: store without
  // trusting untagged fields. Returns added/removed/names vs the previous
  // inventory (tracked internally, or the explicit `prev` param if given).
  function applyInventory(rawItems, prev) {
    var incoming = Array.isArray(rawItems) ? rawItems : []
    var previousNames = prev && prev.names ? prev.names : lastNames
    var added = []
    var removed = []
    var seen = {}

    for (var i = 0; i < incoming.length; i++) {
      var raw = incoming[i]
      if (!raw || typeof raw.name !== "string" || !raw.name) continue
      var validated = {
        name: raw.name,
        type: cleaned(raw.type),
        label: cleaned(raw.label),
        category: cleaned(raw.category),
        tags: Array.isArray(raw.tags) ? raw.tags.filter(function(t) { return typeof t === "string" }) : [],
        groupNames: Array.isArray(raw.groupNames) ? raw.groupNames.filter(function(g) { return typeof g === "string" }) : [],
        group: raw.type === "Group",
        state: "",
        semantics: semanticsOf(raw),
        pointOf: "",
        locationFromConfig: ""
      }
      var pointOf = typeof validated.semantics.config.isPointOf === "string" ? validated.semantics.config.isPointOf : ""
      var locationFromConfig = typeof validated.semantics.config.hasLocation === "string" ? validated.semantics.config.hasLocation : ""
      validated.pointOf = pointOf
      validated.locationFromConfig = locationFromConfig
      items[validated.name] = validated
      seen[validated.name] = true
      if (previousNames.indexOf(validated.name) === -1) added.push(validated.name)
    }
    for (var n = 0; n < previousNames.length; n++) {
      if (!seen[previousNames[n]]) {
        delete items[previousNames[n]]
        removed.push(previousNames[n])
      }
    }
    lastNames = Object.keys(items)
    return { added: added, removed: removed, names: lastNames }
  }

  function pushStates(map) {
    var names = []
    if (!map || typeof map !== "object") return names
    for (var name in map) {
      var dto = map[name]
      var item = items[name]
      if (!item) continue
      if (dto && typeof dto.state === "string") {
        item.state = dto.state
        states[name] = { state: dto.state, type: cleaned(dto.type) }
      } else if (typeof dto === "string") {
        // A plain "name":"state" frame (stricter/older servers).
        item.state = dto
        states[name] = { state: dto, type: "" }
      }
      names.push(name)
    }
    return names
  }

  function item(name) {
    return items[name] ? items[name] : null
  }

  function count() {
    return Object.keys(items).length
  }

  // A semantic point inherits its equipment's label; otherwise its own.
  function displayNameFor(item) {
    if (!item) return ""
    if (item.pointOf && items[item.pointOf]) {
      var equipmentLabel = cleaned(items[item.pointOf].label)
      if (equipmentLabel) return equipmentLabel
    }
    return cleaned(item.label) || item.name
  }

  function areaNameFor(item) {
    if (!item) return ""
    var fromEquipment = ""
    if (item.pointOf && items[item.pointOf]) {
      fromEquipment = items[item.pointOf].locationFromConfig
    }
    return cleaned(fromEquipment || item.locationFromConfig)
  }

  function labelFor(item) {
    return cleaned(item.label) || item.name
  }

  // Ordered locations (labeled groups first, by label). Equipment or point
  // references to non-location groups are folded in as their label.
  function orderedLocations() {
    var names = {}
    var keys = Object.keys(items)
    for (var i = 0; i < keys.length; i++) {
      var item = items[keys[i]]
      if (isLocation(item)) names[item.name] = labelFor(item)
    }
    for (var j = 0; j < keys.length; j++) {
      var area = areaNameFor(items[keys[j]])
      if (area && !names[area] && items[area] && !isLocation(items[area])) {
        names[area] = labelFor(items[area])
      }
    }
    var out = []
    for (var n in names) out.push({ name: n, label: names[n] })
    return out.sort(function(a, b) { return a.label.localeCompare(b.label) })
  }

  function hasSemantics() {
    var keys = Object.keys(items)
    for (var i = 0; i < keys.length; i++) {
      if (items[keys[i]].semantics.value) return true
    }
    return false
  }

  // Display order, rebuilt only when the *set* of items changes: sorting per
  // keystroke is what made the settings search lag.
  function sortedItemNames() {
    var keys = Object.keys(items)
    return keys.filter(function(name) {
      var item = items[name]
      return item && !item.group && Model.isLightsViewItem(item)
    }).sort(function(a, b) {
      return displayNameFor(items[a]).toLowerCase()
        .localeCompare(displayNameFor(items[b]).toLowerCase())
    })
  }

  // The tab model backing the favorites-first panel. `pickedItemNames` is the
  // persisted panel order (ConfigStore has already deduped and validated it).
  // With grouping off the single Favorites tab carries everything; with it on
  // the picked items are bucketed by area, "Other" last.
  function computeTabs(pickedItemNames, groupByArea, areaLabels, areaForItem) {
    var picked = Array.isArray(pickedItemNames) ? pickedItemNames.slice() : []
    var favoritesTab = {
      id: "favorites", title: "Favorites", itemNames: picked
    }
    if (!groupByArea || picked.length === 0) return [favoritesTab]

    var buckets = {}
    var titles = {}
    var other = []
    for (var i = 0; i < picked.length; i++) {
      var itemName = picked[i]
      var area = areaForItem ? areaForItem(itemName) : ""
      var label = area ? (areaLabels || {})[area] : ""
      if (area && label) {
        if (!buckets[area]) buckets[area] = []
        buckets[area].push(itemName)
        titles[area] = label
      } else {
        other.push(itemName)
      }
    }

    var areaNames = Object.keys(buckets).sort(function(a, b) {
      return String(titles[a]).toLowerCase()
        .localeCompare(String(titles[b]).toLowerCase())
    })
    var grouped = []
    for (var n = 0; n < areaNames.length; n++) {
      var id = areaNames[n]
      grouped.push({ id: "area:" + id, title: titles[id], itemNames: buckets[id] })
    }
    if (other.length > 0) {
      grouped.push({ id: "other", title: "Other", itemNames: other })
    }
    return grouped.length ? [favoritesTab].concat(grouped) : [favoritesTab]
  }

  return {
    items: items,
    reset: reset,
    item: item,
    count: count,
    displayNameFor: displayNameFor,
    areaNameFor: areaNameFor,
    orderedLocations: orderedLocations,
    hasSemantics: hasSemantics,
    sortedItemNames: sortedItemNames,
    computeTabs: computeTabs,
    applyInventory: applyInventory,
    pushStates: pushStates
  }
}