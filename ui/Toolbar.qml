import QtQuick
import QtQuick.Controls
import qs.Commons
import "Layout.js" as Layout

// The top of the window: which phone, what is on it, and the filters.
Item {
  id: toolbar

  property string deviceLabel: ""
  property var devices: []
  property string currentDevice: ""
  property var summary: ({ total: 0, photos: 0, videos: 0, albums: [] })
  property string kind: "all"
  property string album: ""
  property alias searchText: search.text
  property bool busy: false

  signal kindPicked(string kind)
  signal albumPicked(string album)
  signal devicePicked(string id)
  signal rescan()

  function focusSearch() { search.forceActiveFocus(); search.selectAll() }

  implicitHeight: column.implicitHeight + Style.space(28)

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Style.space(20)
    anchors.rightMargin: Style.space(20)
    anchors.topMargin: Style.space(18)
    spacing: Style.space(14)

    // Title row: phone name and counts on the left, search on the right.
    Item {
      width: parent.width
      height: Math.max(titleBlock.implicitHeight, search.implicitHeight)

      Row {
        id: titleBlock
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(12)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰉏"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.display
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Row {
            spacing: Style.space(6)
            Text {
              id: deviceName
              textFormat: Text.PlainText
              text: toolbar.deviceLabel || "Phone Photos"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title + 2
              font.bold: true
            }
            // More than one phone plugged in: the name switches between them.
            Text {
              visible: toolbar.devices.length > 1
              anchors.verticalCenter: deviceName.verticalCenter
              text: "󰅀"
              color: Util.alpha(Color.popups.text, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                cursorShape: Qt.PointingHandCursor
                onClicked: deviceMenu.open()
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            text: toolbar.summary.total > 0
              ? Layout.formatCount(toolbar.summary.photos, "photo", "photos") + "  ·  "
                + Layout.formatCount(toolbar.summary.videos, "video", "videos")
              : (toolbar.busy ? "Reading the phone…" : "")
            color: Util.alpha(Color.popups.text, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      Menu {
        id: deviceMenu
        y: titleBlock.height
        Repeater {
          model: toolbar.devices
          MenuItem {
            required property var modelData
            text: modelData.label
            checkable: true
            checked: modelData.id === toolbar.currentDevice
            onTriggered: toolbar.devicePicked(modelData.id)
          }
        }
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Rectangle {
          id: searchBox
          width: Math.min(Style.space(320), toolbar.width * 0.34)
          height: Style.space(34)
          radius: Style.cornerRadius
          color: Util.alpha(Color.popups.text, search.activeFocus ? 0.09 : 0.05)
          border.width: 1
          border.color: search.activeFocus ? Color.accent : Util.alpha(Color.popups.text, 0.12)
          Behavior on color { ColorAnimation { duration: 140 } }
          Behavior on border.color { ColorAnimation { duration: 140 } }

          Text {
            id: searchGlyph
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍉"
            color: Util.alpha(Color.popups.text, 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          TextField {
            id: search
            anchors.left: searchGlyph.right
            anchors.right: clear.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(6)
            placeholderText: "Search names, albums, 2026-08…"
            placeholderTextColor: Util.alpha(Color.popups.text, 0.4)
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            background: null
            selectByMouse: true
            Keys.onEscapePressed: function(event) {
              if (text !== "") text = ""
              else event.accepted = false
            }
          }

          Text {
            id: clear
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅖"
            opacity: search.text !== "" ? 0.7 : 0
            visible: opacity > 0
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            Behavior on opacity { NumberAnimation { duration: 120 } }
            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              cursorShape: Qt.PointingHandCursor
              onClicked: search.text = ""
            }
          }
        }

        ActionButton {
          glyph: "󰑐"
          label: ""
          busy: toolbar.busy
          implicitWidth: Style.space(34)
          onClicked: toolbar.rescan()
        }
      }
    }

    // Filters: a segmented kind switch with a sliding marker, then albums.
    Item {
      width: parent.width
      height: Style.space(32)

      Rectangle {
        id: segments
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: segmentRow.width + Style.space(6)
        height: Style.space(32)
        radius: Style.cornerRadius
        color: Util.alpha(Color.popups.text, 0.05)

        readonly property var options: [
          { key: "all", label: "All" },
          { key: "photo", label: "Photos" },
          { key: "video", label: "Videos" }
        ]

        Rectangle {
          id: marker
          // By the Repeater's own index: Row.children also holds the Repeater,
          // which would put the marker one segment behind.
          property Item target: segmentRepeater.count > 0
            ? segmentRepeater.itemAt(Math.max(0, segments.options.map(function(o) { return o.key }).indexOf(toolbar.kind)))
            : null
          x: target ? target.x + Style.space(3) : 0
          y: Style.space(3)
          width: target ? target.width : 0
          height: parent.height - Style.space(6)
          radius: Style.cornerRadius
          color: Color.accent
          Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
          Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }

        Row {
          id: segmentRow
          x: Style.space(3)
          anchors.verticalCenter: parent.verticalCenter
          Repeater {
            id: segmentRepeater
            model: segments.options
            Item {
              required property var modelData
              width: segmentLabel.implicitWidth + Style.space(26)
              height: Style.space(26)
              Text {
                id: segmentLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: parent.modelData.label
                color: toolbar.kind === parent.modelData.key ? Color.popups.background : Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: toolbar.kind === parent.modelData.key
                Behavior on color { ColorAnimation { duration: 180 } }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: toolbar.kindPicked(parent.modelData.key)
              }
            }
          }
        }
      }

      ListView {
        id: albums
        anchors.left: segments.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(30)
        orientation: ListView.Horizontal
        spacing: Style.space(6)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: [{ name: "", count: toolbar.summary.total }].concat(toolbar.summary.albums || [])
        delegate: Rectangle {
          required property var modelData
          readonly property bool active: toolbar.album === modelData.name
          height: Style.space(30)
          width: chipRow.implicitWidth + Style.space(22)
          radius: Style.cornerRadius
          color: active ? Util.alpha(Color.accent, 0.18) : (chipArea.containsMouse ? Util.alpha(Color.popups.text, 0.08) : "transparent")
          border.width: 1
          border.color: active ? Color.accent : Util.alpha(Color.popups.text, 0.14)
          Behavior on color { ColorAnimation { duration: 140 } }
          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Style.space(6)
            Text {
              textFormat: Text.PlainText
              text: modelData.name === "" ? "All albums" : modelData.name
              color: active ? Color.accent : Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              textFormat: Text.PlainText
              text: String(modelData.count)
              color: Util.alpha(active ? Color.accent : Color.popups.text, 0.55)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }
          MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: toolbar.albumPicked(modelData.name)
          }
        }
        WheelHandler {
          orientation: Qt.Vertical
          onWheel: function(event) { albums.flick(event.angleDelta.y * 8, 0) }
        }
      }
    }
  }
}
