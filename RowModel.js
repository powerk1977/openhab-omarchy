.pragma library

// Projection from an EntityStore entity descriptor into a QML ListModel row,
// mirroring the reference plugin's RowModel so Panel.qml rows stay familiar.
// Pure data: every field is a string or bool the UI binds to.

// Row requirements at a glance (kept in sync with Panel.qml):
//   location row: rowKind "location", areaName, label
//   entity row:   rowKind "entity", itemName, name, subtitle, icon, isOn,
//                 pending, available, controlKind, brightness, brightnessValue,
//                 areaName

function project(entity) {
  var row = {
    rowKind: entity.rowKind || "entity",
    areaName: entity.areaName || "",
    label: entity.label || "",
    itemName: entity.itemName || "",
    name: entity.name || "",
    subtitle: entity.subtitle || "",
    icon: entity.icon || "",
    isOn: !!entity.isOn,
    pending: !!entity.pending,
    available: !!entity.available,
    controlKind: entity.controlKind || "none",
    brightness: !!entity.brightness,
    brightnessValue: typeof entity.brightnessValue === "number" ? entity.brightnessValue : -1
  }
  return row
}

// Build the grouped panel list order (groupByArea mode). Given the picked
// items and an area resolver, return groups of `{ rowKind: "location",
// areaName, label, itemNames }` in a stable order: locations that exist in
// `orderedLocations` first (in that order), any remaining areas after them
// sorted by label, and the `otherArea` pseudo-group (items with no mapped
// location) last. Within a group items keep their picked order. Pure data, so
// Service.rebuildRows stays unit-testable outside the shell.
function groupPanelItems(itemNames, areaFor, orderedLocations, areaLabelFor, otherArea) {
  var picked = Array.isArray(itemNames) ? itemNames.slice() : []
  if (picked.length === 0) return []

  var buckets = {}
  var order = []
  for (var i = 0; i < picked.length; i++) {
    var area = areaFor ? areaFor(picked[i]) : ""
    if (!buckets[area]) { buckets[area] = []; order.push(area) }
    buckets[area].push(picked[i])
  }

  var known = Array.isArray(orderedLocations) ? orderedLocations : []
  var knownOrder = []
  var seen = {}
  for (var k = 0; k < known.length; k++) {
    if (buckets[known[k]] && !seen[known[k]]) { knownOrder.push(known[k]); seen[known[k]] = true }
  }

  var rest = []
  for (var r = 0; r < order.length; r++) {
    if (!seen[order[r]]) rest.push(order[r])
  }
  rest.sort(function (a, b) {
    return String(areaLabelFor ? areaLabelFor(a) : a).toLowerCase()
      .localeCompare(String(areaLabelFor ? areaLabelFor(b) : b).toLowerCase())
  })
  if (otherArea !== undefined && otherArea !== null) {
    var otherIndex = rest.indexOf(otherArea)
    if (otherIndex !== -1) { rest.splice(otherIndex, 1); rest.push(otherArea) }
  }

  var groups = []
  function push(area) {
    groups.push({
      rowKind: "location",
      areaName: area,
      label: areaLabelFor ? areaLabelFor(area) : area,
      itemNames: buckets[area]
    })
  }
  for (var n = 0; n < knownOrder.length; n++) push(knownOrder[n])
  for (var m = 0; m < rest.length; m++) push(rest[m])
  return groups
}