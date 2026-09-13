import QtQuick
import qs.Commons

// An empty-state note that collapses to zero height when hidden (via a
// wrapper, so the Text's height is never bound to its own implicitHeight).
Item {
  property bool noteVisible: false
  property string noteText: ""
  visible: noteVisible
  height: visible ? body.implicitHeight : 0

  Text {
    textFormat: Text.PlainText
    id: body
    anchors.fill: parent
    visible: parent.visible
    text: noteText
    color: Color.muted
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.bodySmall
  }
}