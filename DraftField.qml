import QtQuick
import QtQuick.Controls
import qs.Commons

// The label + input + (optional http:// warning) column repeated by the
// connection form. `draft` aliases the field's text; instances wire it back
// to their root draft property with onDraftChanged.
Column {
  id: draftField
  property alias draft: field.text
  property string labelText: ""
  property string placeholderText: ""
  property bool passwordField: false
  property bool fieldVisible: true
  property string warningText: ""

  visible: fieldVisible
  width: parent ? parent.width : 0
  spacing: Style.spacing.sm

  Text {
    textFormat: Text.PlainText
    visible: draftField.labelText.length > 0
    text: draftField.labelText
    color: Color.muted
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.bodySmall
  }

  TextField {
    id: field
    width: parent.width
    echoMode: draftField.passwordField ? TextInput.Password : TextInput.Normal
    placeholderText: draftField.placeholderText
  }

  Text {
    textFormat: Text.PlainText
    visible: draftField.warningText.length > 0
      && draft.trim().toLowerCase().startsWith("http://")
    width: parent.width
    text: draftField.warningText
    color: Color.muted
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}