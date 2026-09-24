import QtQuick
import QtQuick.Effects
import qs.Commons
import "Layout.js" as Layout

// The second step before anything leaves the phone. Deleting over USB is
// permanent, so the dialog says so, shows what is going, and puts focus on
// Cancel.
Item {
  id: dialog

  property int count: 0
  property real bytes: 0
  property string deviceLabel: "the phone"
  property var previews: []   // up to three thumbnail paths
  property bool shown: false

  signal confirmed()
  signal cancelled()

  function show() {
    shown = true
    cancelButton.forceActiveFocus()
  }
  function hide() { shown = false }

  anchors.fill: parent
  visible: opacity > 0
  opacity: shown ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 180 } }
  z: 50

  Rectangle {
    anchors.fill: parent
    color: "black"
    opacity: 0.55
    MouseArea {
      anchors.fill: parent
      onClicked: dialog.cancelled()
    }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(48), Style.space(430))
    height: body.implicitHeight + Style.space(44)
    radius: Style.cornerRadius
    color: Color.popups.background
    border.width: 1
    border.color: Util.alpha(Color.urgent, 0.55)
    scale: dialog.shown ? 1 : 0.92
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

    MouseArea { anchors.fill: parent }

    Column {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(22)
      spacing: Style.space(16)

      // A small fan of what is about to go.
      Item {
        width: parent.width
        height: Style.space(92)
        visible: dialog.previews.length > 0
        Repeater {
          model: dialog.previews
          Rectangle {
            required property string modelData
            required property int index
            readonly property int n: dialog.previews.length
            width: Style.space(76)
            height: Style.space(76)
            anchors.verticalCenter: parent.verticalCenter
            x: (parent.width - width) / 2 + (index - (n - 1) / 2) * Style.space(34)
            rotation: (index - (n - 1) / 2) * 7
            z: index === Math.floor(n / 2) ? 3 : 1
            radius: Style.cornerRadius
            color: Util.alpha(Color.popups.text, 0.08)
            border.width: 2
            border.color: Color.popups.background
            clip: true
            Image {
              anchors.fill: parent
              anchors.margins: 2
              source: modelData !== "" ? "file://" + modelData : ""
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              sourceSize.width: 160
              sourceSize.height: 160
              layer.enabled: Style.cornerRadius > 0
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: fanMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
              }
            }
            Item {
              id: fanMask
              anchors.fill: parent
              anchors.margins: 2
              visible: false
              layer.enabled: Style.cornerRadius > 0
              Rectangle {
                anchors.fill: parent
                radius: Math.max(0, Style.cornerRadius - 2)
                antialiasing: true
              }
            }
          }
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: "Delete " + Layout.formatCount(dialog.count, "item", "items") + "?"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title + 2
        font.bold: true
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: Layout.formatBytes(dialog.bytes) + " will be removed from " + dialog.deviceLabel
          + " permanently. Phones have no trash over USB, so this cannot be undone."
        color: Util.alpha(Color.popups.text, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        lineHeight: 1.2
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(10)
        ActionButton {
          id: cancelButton
          label: "Cancel"
          focus: true
          Keys.onReturnPressed: dialog.cancelled()
          Keys.onEscapePressed: dialog.cancelled()
          onClicked: dialog.cancelled()
        }
        ActionButton {
          glyph: "󰆴"
          label: "Delete " + Layout.formatCount(dialog.count, "item", "items")
          variant: "danger"
          onClicked: dialog.confirmed()
        }
      }
    }
  }
}
