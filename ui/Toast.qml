import QtQuick
import qs.Commons

// A notice in the bottom-right corner: progress while something runs, then
// the outcome, which fades away on its own.
Rectangle {
  id: toast

  property string text: ""
  property string detail: ""
  property real progress: -1       // 0..1 while running, -1 for none
  property string actionLabel: ""
  property bool error: false
  property bool shown: false

  signal action()

  function flash(message, extra, isError, label) {
    text = message
    detail = extra || ""
    error = isError === true
    actionLabel = label || ""
    progress = -1
    shown = true
    hideLater.restart()
  }

  function running(message, extra, fraction) {
    text = message
    detail = extra || ""
    error = false
    actionLabel = ""
    progress = fraction
    shown = true
    hideLater.stop()
  }

  width: Math.min(Style.space(380), (parent ? parent.width : 400) - Style.space(40))
  height: column.implicitHeight + Style.space(24)
  radius: Style.cornerRadius
  color: Color.popups.background
  border.width: 1
  border.color: error ? Color.urgent : Util.alpha(Color.popups.text, 0.16)
  anchors.right: parent ? parent.right : undefined
  anchors.rightMargin: Style.space(20)
  y: parent ? (shown ? parent.height - height - Style.space(20) : parent.height + Style.space(10)) : 0
  opacity: shown ? 1 : 0
  z: 40
  Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  Behavior on opacity { NumberAnimation { duration: 200 } }

  Timer {
    id: hideLater
    interval: 5000
    onTriggered: toast.shown = false
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: Style.space(14)
    spacing: Style.space(6)

    Row {
      width: parent.width
      spacing: Style.space(8)
      Text {
        width: parent.width - (actionText.visible ? actionText.width + Style.space(8) : 0)
        textFormat: Text.PlainText
        text: toast.text
        color: toast.error ? Color.urgent : Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        id: actionText
        visible: toast.actionLabel !== ""
        textFormat: Text.PlainText
        text: toast.actionLabel
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.underline: actionArea.containsMouse
        MouseArea {
          id: actionArea
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: toast.action()
        }
      }
    }

    Text {
      visible: toast.detail !== ""
      width: parent.width
      textFormat: Text.PlainText
      text: toast.detail
      color: Util.alpha(Color.popups.text, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }

    Rectangle {
      visible: toast.progress >= 0
      width: parent.width
      height: Style.space(3)
      radius: height / 2
      color: Util.alpha(Color.popups.text, 0.1)
      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, toast.progress))
        height: parent.height
        radius: parent.radius
        color: Color.accent
        Behavior on width { NumberAnimation { duration: 200 } }
      }
    }
  }
}
