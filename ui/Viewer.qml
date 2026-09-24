import QtQuick
import qs.Commons
import "Layout.js" as Layout

// One photo, large. The thumbnail shows at once and the full picture fades in
// over it when it arrives.
Item {
  id: viewer

  property var item: null
  property string preview: ""
  property bool shown: false
  property bool hasPrevious: false
  property bool hasNext: false

  signal closed()
  signal previous()
  signal next()
  signal download()
  signal remove()

  anchors.fill: parent
  visible: opacity > 0
  opacity: shown ? 1 : 0
  z: 30
  Behavior on opacity { NumberAnimation { duration: 180 } }

  Keys.onEscapePressed: viewer.closed()
  Keys.onLeftPressed: if (viewer.hasPrevious) viewer.previous()
  Keys.onRightPressed: if (viewer.hasNext) viewer.next()
  Keys.onDeletePressed: viewer.remove()

  Rectangle {
    anchors.fill: parent
    color: Qt.darker(Color.popups.background, 1.6)
    opacity: 0.97
  }

  MouseArea {
    anchors.fill: parent
    onClicked: viewer.closed()
  }

  Item {
    id: stage
    anchors.fill: parent
    anchors.topMargin: Style.space(56)
    anchors.bottomMargin: Style.space(72)
    anchors.leftMargin: Style.space(72)
    anchors.rightMargin: Style.space(72)
    scale: viewer.shown ? 1 : 0.94
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Image {
      id: low
      anchors.fill: parent
      source: viewer.item && viewer.item.thumb ? "file://" + viewer.item.thumb : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      opacity: high.status === Image.Ready ? 0 : 1
    }

    Image {
      id: high
      anchors.fill: parent
      source: viewer.preview !== "" ? "file://" + viewer.preview : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      opacity: status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 260 } }
    }

    // Still decoding the full picture.
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: Style.space(120)
      height: Style.space(3)
      radius: height / 2
      visible: viewer.item && viewer.item.kind === "photo" && high.status !== Image.Ready
      color: Util.alpha(Color.popups.text, 0.1)
      clip: true
      Rectangle {
        width: parent.width * 0.35
        height: parent.height
        radius: parent.radius
        color: Color.accent
        NumberAnimation on x {
          from: -parent.width * 0.35
          to: parent.width
          duration: 900
          loops: Animation.Infinite
          running: parent.visible
        }
      }
    }

    Text {
      anchors.centerIn: parent
      visible: viewer.item && viewer.item.kind === "video"
      text: "󰐊"
      color: "white"
      style: Text.Outline
      styleColor: Util.alpha("black", 0.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.display * 3
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(90)
    visible: viewer.item && viewer.item.kind === "video"
    textFormat: Text.PlainText
    text: "Download the video to play it"
    color: Util.alpha(Color.popups.text, 0.7)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  // Previous / next.
  Repeater {
    model: [{ side: "left", glyph: "󰅁" }, { side: "right", glyph: "󰅂" }]
    Rectangle {
      required property var modelData
      readonly property bool enabledSide: modelData.side === "left" ? viewer.hasPrevious : viewer.hasNext
      anchors.verticalCenter: parent.verticalCenter
      x: modelData.side === "left" ? Style.space(16) : viewer.width - width - Style.space(16)
      width: Style.space(44)
      height: width
      radius: width / 2
      visible: enabledSide
      color: arrowArea.containsMouse ? Util.alpha(Color.popups.text, 0.16) : Util.alpha(Color.popups.text, 0.07)
      Behavior on color { ColorAnimation { duration: 120 } }
      Text {
        anchors.centerIn: parent
        text: modelData.glyph
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title + 4
      }
      MouseArea {
        id: arrowArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: modelData.side === "left" ? viewer.previous() : viewer.next()
      }
    }
  }

  // What it is, and what can be done with it.
  Item {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Style.space(64)

    Column {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(24)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        textFormat: Text.PlainText
        text: viewer.item ? viewer.item.name : ""
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: viewer.item
          ? viewer.item.album + "  ·  " + new Date(viewer.item.mtime * 1000).toLocaleString(Qt.locale(), "d MMM yyyy, HH:mm")
            + "  ·  " + Layout.formatBytes(viewer.item.size)
          : ""
        color: Util.alpha(Color.popups.text, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(24)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)
      ActionButton { glyph: "󰇚"; label: "Download"; onClicked: viewer.download() }
      ActionButton { glyph: "󰆴"; label: "Delete"; variant: "danger"; onClicked: viewer.remove() }
      ActionButton { glyph: "󰅖"; label: ""; implicitWidth: Style.space(34); onClicked: viewer.closed() }
    }
  }
}
