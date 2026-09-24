import QtQuick
import QtQuick.Controls
import qs.Commons
import "Layout.js" as Layout

// The grid of photos and videos, grouped by month.
//
// Only the tiles near the viewport exist. The layout of every loaded item is
// computed up front (cheap), and a model of the visible ones is reconciled by
// id as the view scrolls, so a tile that stays on screen is never rebuilt and
// can animate to its new place when something before it is removed.
Item {
  id: gallery

  // Loaded items, newest first: {id, name, album, kind, size, mtime, month, thumb}
  property var items: []
  property int total: 0
  property var selected: ({})
  property int selectedCount: 0
  property bool loading: false
  property var removing: ({})
  property var missing: ({})
  // Items per month across every page, not just the loaded ones.
  property var monthCounts: ({})
  property int focusIndex: -1

  readonly property real gap: Style.space(8)
  readonly property real headerHeight: Style.space(46)
  readonly property real target: Style.space(168)
  readonly property bool selecting: selectedCount > 0

  signal needMore()
  signal wantThumbs(var ids)
  signal open(int index)
  signal toggle(int index, var mouse)

  property var laid: Layout.layout([], 1, 1, 1, 1)
  property bool animateMoves: false

  function relayout(animated) {
    gallery.animateMoves = animated === true
    laid = Layout.layout(items, Math.max(1, flick.width), target, gap, headerHeight)
    syncVisible()
    if (animated) settle.restart()
  }

  function scrollToTop() { flick.contentY = 0 }

  function ensureVisible(index) {
    if (index < 0 || index >= laid.tiles.length) return
    var tile = laid.tiles[index]
    if (tile.y < flick.contentY) flick.contentY = Math.max(0, tile.y - headerHeight)
    else if (tile.y + tile.size > flick.contentY + flick.height)
      flick.contentY = tile.y + tile.size - flick.height + gap
  }

  // Refresh one tile's thumbnail if it is on screen.
  function setThumb(id, path) {
    for (var i = 0; i < tiles.count; i++) {
      if (tiles.get(i).itemId === id) {
        tiles.setProperty(i, "thumb", path || "")
        tiles.setProperty(i, "missing", !path)
        return
      }
    }
  }

  function syncVisible() {
    var buffer = Math.max(flick.height, 400)
    var range = Layout.visibleRange(laid.tiles, flick.contentY - buffer, flick.contentY + flick.height + buffer)
    var wanted = {}
    for (var i = range.first; i < range.end; i++) wanted[laid.tiles[i].id] = i

    // Drop what scrolled away, move what stayed, add what arrived.
    for (var j = tiles.count - 1; j >= 0; j--) {
      var id = tiles.get(j).itemId
      if (!(id in wanted)) tiles.remove(j)
    }
    var present = {}
    for (var k = 0; k < tiles.count; k++) {
      var row = tiles.get(k)
      var index = wanted[row.itemId]
      var place = laid.tiles[index]
      present[row.itemId] = true
      if (row.px !== place.x || row.py !== place.y || row.size !== place.size || row.at !== index)
        tiles.set(k, { px: place.x, py: place.y, size: place.size, at: index })
    }
    var need = []
    for (var n = range.first; n < range.end; n++) {
      var t = laid.tiles[n]
      if (present[t.id]) continue
      var item = items[n]
      tiles.append({
        itemId: t.id, at: n, px: t.x, py: t.y, size: t.size,
        kind: item.kind, thumb: item.thumb || "", missing: gallery.missing[t.id] === true
      })
      if (!item.thumb && gallery.missing[t.id] !== true) need.push(t.id)
    }
    // Ask for what is actually on screen first, then the buffer around it.
    var screen = Layout.visibleRange(laid.tiles, flick.contentY, flick.contentY + flick.height)
    var ordered = []
    for (var s = screen.first; s < screen.end; s++) {
      var candidate = items[s]
      if (candidate && !candidate.thumb && gallery.missing[candidate.id] !== true) ordered.push(candidate.id)
    }
    for (var r = 0; r < need.length; r++) if (ordered.indexOf(need[r]) === -1) ordered.push(need[r])
    if (ordered.length > 0) {
      thumbAsk.pending = ordered
      thumbAsk.restart()
    }

    headerModel.clear()
    for (var h = 0; h < laid.headers.length; h++) {
      var header = laid.headers[h]
      if (header.y + headerHeight < flick.contentY - buffer || header.y > flick.contentY + flick.height + buffer) continue
      var count = gallery.monthCounts[header.month]
      headerModel.append({ month: header.month, py: header.y, count: count !== undefined ? count : header.count })
    }

    if (!loading && items.length < total && flick.contentY + flick.height > laid.height - flick.height * 1.5)
      gallery.needMore()
  }

  // Set just before `items` changes when the change should animate (a delete).
  property bool animateNext: false
  onItemsChanged: {
    relayout(animateNext)
    animateNext = false
  }

  Timer {
    id: settle
    interval: 320
    onTriggered: gallery.animateMoves = false
  }

  // Scrolling fast asks for many screens' worth of thumbnails; only the
  // screen the scroll settles on matters.
  Timer {
    id: thumbAsk
    property var pending: []
    interval: 60
    onTriggered: gallery.wantThumbs(pending)
  }

  ListModel { id: tiles }
  ListModel { id: headerModel }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.leftMargin: Style.space(20)
    anchors.rightMargin: Style.space(20)
    contentWidth: width
    contentHeight: laid.height + Style.space(96)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    maximumFlickVelocity: 5000
    onContentYChanged: gallery.syncVisible()
    onHeightChanged: gallery.syncVisible()
    onWidthChanged: gallery.relayout(false)

    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Repeater {
      model: headerModel
      delegate: Item {
        readonly property string month: model.month
        readonly property int count: model.count
        x: 0
        y: model.py
        width: flick.width
        height: gallery.headerHeight
        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(10)
          textFormat: Text.PlainText
          text: Layout.monthLabel(parent.month)
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(14)
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(11)
          textFormat: Text.PlainText
          text: Layout.formatCount(parent.count, "item", "items")
          color: Util.alpha(Color.popups.text, 0.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }

    Repeater {
      model: tiles
      delegate: Tile {
        x: model.px
        y: model.py
        width: model.size
        height: model.size
        itemId: model.itemId
        kind: model.kind
        thumb: model.thumb
        missing: model.missing
        animateMoves: gallery.animateMoves
        selected: gallery.selected[model.itemId] === true
        selecting: gallery.selecting
        removing: gallery.removing[model.itemId] === true
        focused: gallery.focusIndex === model.at
        onActivated: function(mouse) { gallery.open(model.at) }
        onToggled: function(mouse) { gallery.toggle(model.at, mouse) }
      }
    }

    // More is on its way: a quiet row of dots under the last tile.
    Row {
      visible: gallery.items.length < gallery.total
      y: laid.height + Style.space(24)
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(6)
      Repeater {
        model: 3
        Rectangle {
          required property int index
          width: Style.space(6)
          height: width
          radius: width / 2
          color: Util.alpha(Color.popups.text, 0.5)
          SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: parent.visible
            PauseAnimation { duration: index * 140 }
            NumberAnimation { from: 0.2; to: 1; duration: 380 }
            NumberAnimation { from: 1; to: 0.2; duration: 380 }
            PauseAnimation { duration: (2 - index) * 140 }
          }
        }
      }
    }
  }

  // The month under the top edge, floating while scrolling.
  Rectangle {
    id: monthPill
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Style.space(10)
    width: pillText.implicitWidth + Style.space(24)
    height: pillText.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: Util.alpha(Color.popups.background, 0.92)
    border.width: 1
    border.color: Util.alpha(Color.popups.text, 0.15)
    opacity: flick.moving && flick.contentY > gallery.headerHeight ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }

    readonly property string month: {
      var headers = gallery.laid.headers
      var current = ""
      for (var i = 0; i < headers.length; i++) {
        if (headers[i].y <= flick.contentY + gallery.headerHeight) current = headers[i].month
        else break
      }
      return current
    }

    Text {
      id: pillText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: Layout.monthLabel(monthPill.month)
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
}
