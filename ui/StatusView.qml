import QtQuick
import qs.Commons

// Whatever stands between the window and a grid of photos: no phone, a locked
// phone, a phone still being read, or nothing to show.
Item {
  id: status

  // "none", "mounting", "locked", "scanning", "error", "empty", "nomatch"
  property string phase: "none"
  property string message: ""
  property string query: ""
  property string deviceLabel: ""

  signal retry()

  readonly property var copy: ({
    none: {
      glyph: "󰄜",
      title: "Connect your phone",
      body: "Plug it in with a USB cable and unlock it.",
      steps: ["Connect the phone with a USB cable", "Unlock the phone",
        "In the USB notification, choose File transfer"]
    },
    mounting: { glyph: "󰄜", title: "Connecting to " + (deviceLabel || "the phone") + "…", body: "", steps: [] },
    locked: {
      glyph: "󰌾",
      title: "Unlock " + (deviceLabel || "the phone"),
      body: "The phone is connected but keeps its files closed while locked.",
      steps: ["Unlock the phone", "If it asks, allow access to phone data",
        "In the USB notification, make sure File transfer is chosen"]
    },
    scanning: { glyph: "󰋩", title: "Reading " + (deviceLabel || "the phone") + "…", body: "Finding photos and videos.", steps: [] },
    error: { glyph: "󰀦", title: "The phone could not be read", body: message, steps: [] },
    empty: { glyph: "󰋩", title: "No photos or videos", body: "Nothing in DCIM, Pictures or Movies on this phone.", steps: [] },
    nomatch: { glyph: "󰍉", title: "Nothing matches", body: query !== "" ? "No photo or video matches “" + query + "”." : "Try another filter.", steps: [] }
  })
  readonly property var current: copy[phase] || copy.none
  readonly property bool busy: phase === "mounting" || phase === "scanning"

  Column {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(40), Style.space(440))
    spacing: Style.space(14)

    Item {
      width: parent.width
      height: glyph.implicitHeight + Style.space(20)

      // A slow pulse behind the glyph while something is happening.
      Rectangle {
        anchors.centerIn: glyph
        width: glyph.implicitWidth * 2.2
        height: width
        radius: width / 2
        color: Util.alpha(Color.accent, 0.12)
        visible: status.busy
        SequentialAnimation on scale {
          running: status.busy
          loops: Animation.Infinite
          NumberAnimation { from: 0.8; to: 1.15; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { from: 1.15; to: 0.8; duration: 900; easing.type: Easing.InOutSine }
        }
      }

      Text {
        id: glyph
        anchors.centerIn: parent
        text: status.current.glyph
        color: status.phase === "error" ? Color.urgent : Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.display * 2
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: status.current.title
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.title + 4
      font.bold: true
      wrapMode: Text.WordWrap
    }

    Text {
      visible: text !== ""
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: status.current.body
      color: Util.alpha(Color.popups.text, 0.65)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }

    Column {
      visible: status.current.steps.length > 0
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(8)
      topPadding: Style.space(6)
      Repeater {
        model: status.current.steps
        Row {
          required property string modelData
          required property int index
          spacing: Style.space(10)
          Rectangle {
            width: Style.space(22)
            height: width
            radius: width / 2
            color: Util.alpha(Color.accent, 0.16)
            Text {
              anchors.centerIn: parent
              text: String(index + 1)
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: modelData
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }
    }

    ActionButton {
      visible: status.phase === "error"
      anchors.horizontalCenter: parent.horizontalCenter
      glyph: "󰑐"
      label: "Try again"
      variant: "primary"
      onClicked: status.retry()
    }
  }
}
