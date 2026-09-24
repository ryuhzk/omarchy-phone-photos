import QtQuick
import qs.Commons

// A text button in three weights: "primary" (accent), "danger" (urgent) and
// the plain default. An optional Nerd Font glyph leads the label.
Rectangle {
  id: button

  property string label: ""
  property string glyph: ""
  property string variant: "plain"
  property bool busy: false
  signal clicked()

  readonly property color tone: variant === "danger" ? Color.urgent : (variant === "primary" ? Color.accent : Color.popups.text)
  readonly property bool filled: variant === "primary" || variant === "danger"

  implicitWidth: content.implicitWidth + Style.space(28)
  implicitHeight: Style.space(34)
  radius: Style.cornerRadius
  opacity: enabled ? 1 : 0.4
  color: filled
    ? (area.pressed ? Qt.darker(tone, 1.25) : (area.containsMouse ? Qt.lighter(tone, 1.12) : tone))
    : (area.pressed ? Util.alpha(tone, 0.18) : (area.containsMouse ? Util.alpha(tone, 0.1) : "transparent"))
  border.width: filled ? 0 : 1
  border.color: Util.alpha(tone, 0.28)
  scale: area.pressed ? 0.97 : 1

  Behavior on color { ColorAnimation { duration: 120 } }
  Behavior on scale { NumberAnimation { duration: 90 } }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(7)

    Text {
      visible: button.glyph !== "" || button.busy
      anchors.verticalCenter: parent.verticalCenter
      text: button.busy ? "󰑓" : button.glyph
      color: button.filled ? Color.popups.background : button.tone
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      RotationAnimation on rotation {
        running: button.busy
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: button.label
      color: button.filled ? Color.popups.background : button.tone
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: button.filled
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    enabled: button.enabled && !button.busy
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
