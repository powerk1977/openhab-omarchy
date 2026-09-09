import QtQuick
import qs.Ui
import qs.Commons

// One line in the settings item browser: add or remove a favorite, and for
// rows already in the panel, move it up or down.
CursorSurface {
  id: row

  required property string itemName
  required property string name
  required property string detail
  required property bool favorite
  required property bool available
  // True when the row renders the "in the panel" column and gets reorder
  // controls; the browser column still gets the star (to remove).
  property bool panelItem: false
  property var service: null
  property string family: Style.font.menuFamily

  implicitHeight: content.implicitHeight + Style.space(8)

  HoverHandler {
    id: hover
    onHoveredChanged: row.hasCursor = hovered
  }

  Item {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    implicitHeight: Math.max(labels.implicitHeight, actions.implicitHeight)

    Column {
      id: labels
      anchors.left: parent.left
      anchors.right: actions.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: row.name
        color: row.available ? Color.menu.text : Color.muted
        font.family: row.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: row.detail.length > 0
        text: row.detail
        color: Color.muted
        font.family: row.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Row {
      id: actions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      PanelActionButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: row.panelItem
        iconText: "󰅃"                       // md-chevron_up
        tooltipText: "Move up"
        foreground: Color.muted
        fontFamily: row.family
        onClicked: if (row.service) row.service.movePanelItem(row.itemName, -1)
      }

      PanelActionButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: row.panelItem
        iconText: "󰅀"                       // md-chevron_down
        tooltipText: "Move down"
        foreground: Color.muted
        fontFamily: row.family
        onClicked: if (row.service) row.service.movePanelItem(row.itemName, 1)
      }

      PanelActionButton {
        anchors.verticalCenter: parent.verticalCenter
        // A filled star for a favorite, an outline for everything else, so
        // the state is legible without relying on colour alone.
        iconText: row.favorite ? "󰓎" : "󰓒"   // md-star / md-star_outline
        tooltipText: row.favorite
          ? "Remove from panel" : "Add to panel"
        foreground: row.favorite ? Color.menu.text : Color.muted
        fontFamily: row.family
        onClicked: if (row.service) row.service.toggleFavorite(row.itemName)
      }
    }
  }
}