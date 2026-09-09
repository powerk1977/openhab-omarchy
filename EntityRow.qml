import QtQuick
import qs.Ui
import qs.Commons

// One item row in the panel lights list. A switch for toggleable points, with
// an expandable brightness slider for dimmers/colours. The switch owns its own
// click; the body opens the controls on an expandable row.
CursorSurface {
  id: row

  required property string itemName
  required property string name
  required property string subtitle
  required property string icon
  required property bool isOn
  required property bool pending
  required property bool available
  required property string controlKind
  required property bool brightness
  required property int brightnessValue
  required property string rowKind
  required property string areaName
  required property string label

  property var service: null
  property QtObject bar: null
  property color fill: Color.foreground
  property color currentFill: Color.foreground
  property bool showIcon: true

  signal expandToggled()
  signal cursorRequested()

  property bool expanded: false

  foreground: fg
  current: expanded
  implicitHeight: Math.max(layout.implicitHeight, Style.space(40))

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color inactive: Qt.darker(fg, 1.5)

  readonly property bool locationHeader: row.rowKind === "location"
  readonly property bool togglable: row.controlKind === "toggle"
  readonly property bool expandable: row.brightness

  readonly property string actionTooltip: {
    if (!togglable && !expandable) return ""
    if (expandable) return row.expanded ? "Collapse" : "Show controls"
    return isOn ? "Turn off" : "Turn on"
  }

  function bodyClicked() {
    if (locationHeader || !service || !available) return
    if (expandable) expandToggled()
    else activate()
  }

  // Keyboard Enter. Stays on/off, because `e` already expands.
  function activate() {
    if (locationHeader || !service || !available) return
    if (togglable) service.toggleItem(row.itemName)
    else if (expandable) expandToggled()
  }

  HoverHandler { id: rowHover }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: row.locationHeader ? Qt.ArrowCursor : Qt.PointingHandCursor
    onContainsMouseChanged: if (containsMouse && !locationHeader) row.cursorRequested()
    onClicked: row.bodyClicked()
  }

  PanelToolTip {
    visible: !row.locationHeader && row.actionTooltip !== "" && rowMouse.containsMouse
    text: row.actionTooltip
    fontFamily: row.family
  }

  Column {
    id: layout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.xl
    anchors.rightMargin: Style.spacing.xl
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.lg

    // ---------- location header ----------
    PanelSectionHeader {
      visible: row.locationHeader
      width: parent.width
      text: row.label.toUpperCase()
      foreground: row.dim
      fontFamily: row.family
    }

    // ---------- item line ----------
    Item {
      visible: !row.locationHeader
      height: visible ? implicitHeight : 0
      width: parent.width
      implicitHeight: Math.max(glyph.implicitHeight, labels.implicitHeight,
                               controlSlot.implicitHeight)

      Text {
        textFormat: Text.PlainText
        id: glyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: row.showIcon ? implicitWidth : 0
        text: row.icon
        color: row.available && row.isOn ? row.fg : row.inactive
        font.family: row.family
        font.pixelSize: Style.font.heading
      }

      Column {
        id: labels
        anchors.left: glyph.right
        anchors.leftMargin: row.showIcon ? Style.spacing.xl : 0
        anchors.right: controlSlot.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: row.name
          color: row.available ? row.fg : row.inactive
          font.family: row.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: row.subtitle.length > 0
          text: row.subtitle
          color: row.dim
          font.family: row.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        id: controlSlot
        anchors.right: expanderSlot.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.md

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          visible: !row.togglable && !row.expandable
          text: row.brightness
            ? row.brightnessValue + "%"
            : (row.isOn ? "On" : "Off")
          color: row.dim
          font.family: row.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        ToggleSwitch {
          anchors.verticalCenter: parent.verticalCenter
          visible: row.togglable
          checked: row.isOn
          busy: row.pending
          interactive: true
          cursorRing: false
          foreground: row.fg
          onToggled: {
            if (!row.service || !row.available) return
            row.service.toggleItem(row.itemName)
          }
        }
      }

      PanelActionButton {
        id: expanderSlot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: row.expandable
        iconText: row.expanded ? "󰅃" : "󰅀"   // md-chevron_up / md-chevron_down
        tooltipText: row.expanded ? "Collapse" : "Show controls"
        foreground: row.dim
        fontFamily: row.family
        onClicked: row.expandToggled()
      }
    }

    PanelSeparator {
      width: parent.width
      visible: expansion.active
      foreground: row.fg
    }

    // ---------- expanded brightness ----------
    Loader {
      id: expansion
      width: parent.width
      visible: active
      // Loaded only while expanded so the slider does not emit while hidden.
      active: row.expanded && row.brightness && !row.locationHeader
        && (row.service !== null)

      sourceComponent: Component {
        Item {
          implicitHeight: Math.max(slider.implicitHeight, hint.implicitHeight)
          width: parent.width

          PanelSlider {
            id: slider
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            bar: row.bar
            minimum: 0
            maximum: 100
            step: 1
            integer: true
            tickCount: 11
            value: row.available ? row.brightnessValue : 0
            enabled: row.available
            // Command on release, not on every movement.
            onReleased: function(value) {
              if (row.service && row.available && value !== row.brightnessValue) {
                row.service.setBrightness(row.itemName, value)
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            id: hint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(slider.value) + "%"
            color: row.dim
            font.family: row.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}