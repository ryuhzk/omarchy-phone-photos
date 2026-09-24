import QtQuick
import QtQuick.Effects
import qs.Commons

// One photo or video in the grid. Position and size come from the layout;
// moving to a new place animates, so a delete closes the gap instead of
// jumping.
Item {
  id: tile

  property string itemId: ""
  property string thumb: ""
  property string kind: "photo"
  // True once the sidecar has said there is no thumbnail to be had.
  property bool missing: false
  property bool selected: false
  property bool selecting: false
  property bool removing: false
  property bool animateMoves: false
  property bool focused: false

  signal activated(var mouse)
  signal toggled(var mouse)

  readonly property color accent: Color.accent
  readonly property color text: Color.popups.text

  Behavior on x { enabled: tile.animateMoves; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  Behavior on y { enabled: tile.animateMoves; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

  // A hovered tile grows a little; draw it above its neighbours so they do
  // not paint over its rounded edge.
  z: hover.hovered ? 2 : 0
  opacity: removing ? 0 : 1
  scale: removing ? 0.6 : 1
  Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
  Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

  // The picture sits inside a frame that shrinks when selected, the way a
  // photo lifts off the page; the frame's edge takes the accent colour.
  Item {
    id: frame
    anchors.fill: parent
    scale: tile.selected ? 0.86 : (hover.hovered ? 1.01 : 1)
    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

    Rectangle {
      id: placeholder
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Util.alpha(tile.text, 0.06)
      visible: picture.status !== Image.Ready
      clip: true

      // A soft band sweeping across while the thumbnail is on its way.
      Rectangle {
        width: parent.width * 0.6
        height: parent.height * 2
        y: -parent.height * 0.5
        rotation: 20
        visible: !tile.missing && (tile.thumb === "" || picture.status === Image.Loading)
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.5; color: Util.alpha(tile.text, 0.07) }
          GradientStop { position: 1.0; color: "transparent" }
        }
        NumberAnimation on x {
          from: -placeholder.width
          to: placeholder.width * 1.4
          duration: 1400
          loops: Animation.Infinite
          running: placeholder.visible
        }
      }

      Text {
        anchors.centerIn: parent
        visible: tile.missing
        text: tile.kind === "video" ? "󰕧" : "󰋩"
        color: Util.alpha(tile.text, 0.35)
        font.family: Style.font.family
        font.pixelSize: Style.font.display
      }
    }

    Image {
      id: picture
      anchors.fill: parent
      source: tile.thumb !== "" ? "file://" + tile.thumb : ""
      asynchronous: true
      cache: true
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: Math.ceil(tile.width * 1.25)
      sourceSize.height: Math.ceil(tile.height * 1.25)
      opacity: status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
      // With a rounded theme, cut the picture to the same corners as its
      // frame; square themes skip the extra layer.
      layer.enabled: Style.cornerRadius > 0
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: roundedMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
    }

    Item {
      id: roundedMask
      anchors.fill: parent
      visible: false
      layer.enabled: Style.cornerRadius > 0
      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        antialiasing: true
      }
    }

    // Darken a little on hover and when picked, so the check mark reads.
    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: "black"
      opacity: tile.selected ? 0.18 : (hover.hovered ? 0.08 : 0)
      Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: "transparent"
      border.width: tile.selected ? Math.max(2, Style.space(2)) : (tile.focused ? 1 : 0)
      border.color: tile.selected ? tile.accent : Util.alpha(tile.text, 0.6)
    }

    // Video marker, bottom left.
    Rectangle {
      visible: tile.kind === "video"
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(6)
      width: videoGlyph.implicitWidth + Style.space(10)
      height: videoGlyph.implicitHeight + Style.space(4)
      radius: Style.cornerRadius
      color: Util.alpha("black", 0.55)
      Text {
        id: videoGlyph
        anchors.centerIn: parent
        text: "󰐊"
        color: "white"
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  // The check circle: shown on hover, while selecting, and on selected tiles.
  Rectangle {
    id: check
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: Style.space(7)
    width: Style.space(20)
    height: width
    radius: width / 2
    color: tile.selected ? tile.accent : Util.alpha("black", 0.35)
    border.width: tile.selected ? 0 : 1.5
    border.color: Util.alpha("white", 0.9)
    opacity: tile.selected || tile.selecting || hover.hovered ? 1 : 0
    scale: tile.selected ? 1 : (checkHover.hovered ? 1.12 : 0.92)
    Behavior on opacity { NumberAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
    Behavior on color { ColorAnimation { duration: 140 } }

    Text {
      anchors.centerIn: parent
      text: "󰄬"
      visible: tile.selected
      color: Color.popups.background
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    HoverHandler { id: checkHover }
    TapHandler {
      acceptedModifiers: Qt.KeyboardModifierMask
      onTapped: tile.toggled({ modifiers: point.modifiers })
    }
  }

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

  MouseArea {
    anchors.fill: parent
    z: -1
    acceptedButtons: Qt.LeftButton
    onClicked: function(mouse) {
      if (tile.selecting || (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) tile.toggled(mouse)
      else tile.activated(mouse)
    }
  }
}
