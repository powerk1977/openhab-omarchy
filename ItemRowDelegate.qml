import QtQuick
import qs.Ui
import qs.Commons

// One settings item row, shared by the browser and the "in the panel" list.
// `panelItemRow` picks the reorder-controls variant.
SettingsItemRow {
  required property var modelData
  property bool panelItemRow: false
  property var serviceRef: null
  width: parent ? parent.width : 0
  itemName: modelData.itemName
  name: modelData.name
  detail: modelData.available ? modelData.state : "Unavailable"
  favorite: modelData.favorite
  available: modelData.available
  panelItem: panelItemRow
  service: serviceRef
}