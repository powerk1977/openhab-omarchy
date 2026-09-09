.pragma library

// Projection from an EntityStore entity descriptor into a QML ListModel row,
// mirroring the reference plugin's RowModel so Panel.qml rows stay familiar.
// Pure data: every field is a string or bool the UI binds to.

// Row requirements at a glance (kept in sync with Panel.qml):
//   location row: rowKind "location", areaName, label
//   entity row:   rowKind "entity", itemName, name, subtitle, badge, icon,
//                 type, isOn, pending, available, controlKind, brightness,
//                 brightnessValue, color, areaName, equipmentName

function project(entity, context) {
  var row = {
    rowKind: entity.rowKind || "entity",
    areaName: entity.areaName || "",
    label: entity.label || "",
    itemName: entity.itemName || "",
    name: entity.name || "",
    subtitle: entity.subtitle || "",
    badge: entity.badge || "",
    icon: entity.icon || "",
    type: entity.type || "",
    isOn: !!entity.isOn,
    pending: !!entity.pending,
    available: !!entity.available,
    controlKind: entity.controlKind || "none",
    brightness: !!entity.brightness,
    brightnessValue: typeof entity.brightnessValue === "number" ? entity.brightnessValue : -1,
    color: !!entity.color,
    equipmentName: entity.equipmentName || ""
  }
  return row
}