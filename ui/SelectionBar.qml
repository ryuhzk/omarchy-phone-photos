import QtQuick
import qs.Commons
import "Layout.js" as Layout

// Rises from the bottom edge while anything is selected.
Rectangle {
  id: bar

  property int count: 0
  property real bytes: 0
  property bool allSelected: false
  property bool deleting: false

  signal selectAll()
  signal clearSelection()
  signal download()
  signal remove()

  readonly property bool shown: count > 0

  width: Math.min(parent ? parent.width - Style.space(40) : 800, content.implicitWidth + Style.space(36))
  height: Style.space(56)
  radius: Style.cornerRadius
  color: Color.popups.background
  border.width: 1
  border.color: Util.alpha(Color.popups.text, 0.22)
  anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
  y: parent ? (shown ? parent.height - height - Style.space(18) : parent.height + Style.space(12)) : 0
  opacity: shown ? 1 : 0
  Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
  Behavior on opacity { NumberAnimation { duration: 200 } }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(10)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "󰅖"
      color: Util.alpha(Color.popups.text, 0.7)
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      MouseArea {
        anchors.fill: parent
        anchors.margins: -Style.space(6)
        cursorShape: Qt.PointingHandCursor
        onClicked: bar.clearSelection()
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(implicitWidth, Style.space(118))
      Text {
        textFormat: Text.PlainText
        text: bar.count + " selected"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: Layout.formatBytes(bar.bytes)
        color: Util.alpha(Color.popups.text, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 1
      height: Style.space(28)
      color: Util.alpha(Color.popups.text, 0.14)
    }

    ActionButton {
      anchors.verticalCenter: parent.verticalCenter
      glyph: "󰒆"
      label: bar.allSelected ? "All selected" : "Select all"
      enabled: !bar.allSelected
      onClicked: bar.selectAll()
    }
    ActionButton {
      anchors.verticalCenter: parent.verticalCenter
      glyph: "󰇚"
      label: "Download"
      onClicked: bar.download()
    }
    ActionButton {
      anchors.verticalCenter: parent.verticalCenter
      glyph: "󰆴"
      label: "Delete"
      variant: "danger"
      busy: bar.deleting
      onClicked: bar.remove()
    }
  }
}
