import QtQuick
import qs.Ui
import qs.Commons

// Scene action strip: a SCENES caption plus one rectangular chip per scene
// rule tagged `Scene` on the server (openHAB Settings -> Scenes). It sits
// above the items filter chips and runs a scene through the service, which
// owns the pending/ack state — a chip spins while its scene is dispatching.
// Disabled scenes are dimmed and unclickable; hovering one shows the reason.
//
// The strip is presentational: the PanelBody owns the shared cursor column,
// passes activeIndex/cursorOn to paint which chip is keyboard-selected, and
// reacts to chipHovered/chipActivated (mouse mirrors).
Item {
  id: root

  required property var oh
  property QtObject bar: null

  // Palette mirrors the body's fallbacks so the pop-out window (no bar)
  // still reads correctly.
  property color foreground: bar ? bar.foreground : Color.foreground
  property color foregroundDim: Qt.darker(root.foreground, 1.4)
  property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Which chip the shared panel cursor is parked on, and whether the strip
  // currently owns it (index -1 of the body's cursor column).
  property int activeIndex: 0
  property bool cursorOn: false

  signal chipHovered(int index)
  signal chipActivated(int index)

  implicitWidth: column.implicitWidth
  implicitHeight: column.implicitHeight
  height: column.implicitHeight

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.sm

    PanelSectionHeader {
      id: caption
      width: parent.width
      text: "SCENES"
      foreground: root.foregroundDim
      fontFamily: root.fontFamily
    }

    Flow {
      id: chips
      width: parent.width
      spacing: Style.spacing.sm

      Repeater {
        // A JS array model binds each element as `modelData`.
        model: root.oh ? root.oh.scenes : []

        Button {
          required property int index
          required property var modelData

          property bool sceneActive: root.cursorOn && index === root.activeIndex
          // pendingScenes is a var mutated in place, which QML cannot observe;
          // depend on the monotonic revision so set/clear/sweep re-evaluate.
          property bool scenePending: root.oh && root.oh.scenePending(modelData.uid)
              && root.oh.pendingSceneRevision >= 0

          iconText: "󰐊"     // md-play
          text: modelData.name
          tooltipText: modelData.enabled ? "" : "Disabled in openHAB"
          iconSize: Style.font.caption
          fontSize: Style.font.caption
          iconSpinning: scenePending
          foreground: modelData.enabled ? root.foreground : Qt.darker(root.foreground, 1.6)
          fontFamily: root.fontFamily
          bordered: true
          selected: sceneActive
          // The kit Button keeps its MouseArea live when disabled, so hover
          // (and the disabled tooltip) still work; only activation is gated.
          enabled: modelData.enabled && !scenePending

          onClicked: if (modelData.enabled) root.chipActivated(index)
          onHovered: function (isHovered) {
            if (isHovered) root.chipHovered(index)
          }
        }
      }
    }
  }
}