import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ui"
import "ui/Layout.js" as Layout

Panel {
  id: root

  moduleName: "ryuhzk.phone-photos"
  ipcTarget: "ryuhzk.phone-photos"

  // --- what the sidecar has told us ------------------------------------
  property bool sidecarReady: false
  property var devices: []
  property string currentDevice: ""
  property string phase: "none"
  property string phaseMessage: ""
  property string deviceLabel: ""
  property var summary: ({ total: 0, photos: 0, videos: 0, albums: [] })
  property int libraryVersion: 0

  // --- what the window shows -------------------------------------------
  property var items: []
  property int total: 0
  property bool pageLoading: false
  property int pageSeq: 0
  property var thumbs: ({})
  property var missing: ({})
  property var monthCounts: ({})
  property string kind: "all"
  property string album: ""
  property string searchText: ""

  property var selected: ({})
  property int selectedCount: 0
  property real selectedBytes: 0
  property bool allSelected: false
  property int anchorIndex: -1
  property var pendingDelete: []
  property bool deleting: false
  property int viewerIndex: -1
  property string viewerPreview: ""

  // Whether deleting also puts a copy in this computer's Trash. Kept in the
  // widget's own entry in shell.json, so the last choice is the next default.
  readonly property bool trashCopies: setting("trashCopies", false) === true

  function setTrashCopies(value) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return
    var entry = { id: moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.trashCopies = value === true
    bar.shell.updateEntryInline(moduleName, entry)
  }

  readonly property bool connected: devices.length > 0
  // Built when a request goes out, not bound: a change handler can run before
  // a binding on the same property catches up, which sent the previous filter.
  function currentQuery() { return { kind: kind, album: album, text: searchText } }

  // Shown on the bar only while a phone is plugged in.
  visible: connected
  implicitWidth: connected ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  // --- the sidecar -----------------------------------------------------
  readonly property string backendPath: decodeURIComponent(
    String(Qt.resolvedUrl("backend/phone_photos.py")).replace(/^file:\/\//, ""))
  readonly property var sidecarEnvironment: {
    var names = ["HOME", "USER", "LANG", "LC_ALL", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS",
      "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME"]
    var env = { PATH: "/usr/bin:/bin" }
    for (var i = 0; i < names.length; i++) {
      var value = Quickshell.env(names[i])
      if (value) env[names[i]] = String(value)
    }
    return env
  }

  function send(message) {
    if (!sidecar.running) return
    sidecar.write(JSON.stringify(message) + "\n")
  }

  Process {
    id: sidecar
    running: true
    stdinEnabled: true
    clearEnvironment: true
    environment: root.sidecarEnvironment
    command: ["/usr/bin/python3", "-I", root.backendPath]
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { if (line.trim() !== "") console.warn("phone-photos sidecar:", line) }
    }
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        var event
        try { event = JSON.parse(line) } catch (error) { return }
        root.handle(event)
      }
    }
    onExited: function(code) {
      root.sidecarReady = false
      root.devices = []
      restart.restart()
    }
  }

  // A sidecar that dies comes back, but not in a tight loop.
  Timer {
    id: restart
    interval: 3000
    onTriggered: sidecar.running = true
  }

  function handle(event) {
    switch (event.event) {
    case "ready":
      sidecarReady = true
      send({ op: "hello" })
      break
    case "devices":
      devices = event.devices || []
      currentDevice = event.current || ""
      if (devices.length === 0) resetLibrary()
      break
    case "state":
      phase = event.phase
      phaseMessage = event.message || ""
      if (event.device) deviceLabel = event.device
      break
    case "library":
      summary = event
      libraryVersion = event.version
      deviceLabel = event.device || deviceLabel
      clearSelection()
      reload()
      break
    case "page":
      if (event.seq !== pageSeq) return
      pageLoading = false
      total = event.total
      var incoming = event.items.map(function(item) {
        if (item.thumb) thumbs[item.id] = item.thumb
        else if (thumbs[item.id]) item.thumb = thumbs[item.id]
        return item
      })
      if (event.months) monthCounts = event.months
      items = event.offset === 0 ? incoming : items.concat(incoming)
      break
    case "thumb":
      if (event.path) thumbs[event.id] = event.path
      else missing[event.id] = true
      for (var i = 0; i < items.length; i++) if (items[i].id === event.id) { items[i].thumb = event.path || ""; break }
      gallery.setThumb(event.id, event.path)
      break
    case "preview":
      if (viewerIndex >= 0 && items[viewerIndex] && items[viewerIndex].id === event.id) viewerPreview = event.path || ""
      break
    case "ids":
      if (event.seq !== pageSeq) return
      var all = {}
      for (var j = 0; j < event.ids.length; j++) all[event.ids[j]] = true
      selected = all
      selectedCount = event.ids.length
      selectedBytes = event.bytes
      allSelected = true
      break
    case "deleting":
      toast.running(event.trash ? "Moving to Trash…" : "Deleting…", event.done + " of " + event.total,
        event.done / Math.max(1, event.total))
      break
    case "deleted":
      finishDelete(event)
      break
    case "downloading":
      toast.running("Downloading " + (event.done + 1) + " of " + event.count, event.name,
        event.bytes / Math.max(1, event.total))
      break
    case "downloaded":
      downloadedFolder = event.folder
      var parts = []
      if (event.saved) parts.push(Layout.formatCount(event.saved, "file", "files") + " saved")
      if (event.skipped) parts.push(event.skipped + " already there")
      if (event.failed.length) parts.push(event.failed.length + " failed")
      toast.flash(event.cancelled ? "Download stopped" : "Download finished",
        parts.join(" · ") + "  →  " + event.folder, event.failed.length > 0, "Open folder")
      break
    case "error":
      toast.flash("Something went wrong", event.message, true)
      break
    }
  }

  property string downloadedFolder: ""

  // --- paging and filters ----------------------------------------------
  function resetLibrary() {
    items = []
    total = 0
    summary = { total: 0, photos: 0, videos: 0, albums: [] }
    thumbs = {}
    missing = {}
    clearSelection()
    viewerIndex = -1
  }

  function reload() {
    pageSeq++
    pageLoading = true
    send({ op: "page", seq: pageSeq, query: currentQuery(), offset: 0, limit: 180 })
    gallery.scrollToTop()
  }

  function loadMore() {
    if (pageLoading || items.length >= total) return
    pageLoading = true
    send({ op: "page", seq: pageSeq, query: currentQuery(), offset: items.length, limit: 240 })
  }

  onKindChanged: { clearSelection(); reload() }
  onAlbumChanged: { clearSelection(); reload() }

  Timer {
    id: searchDebounce
    interval: 220
    onTriggered: { root.clearSelection(); root.reload() }
  }

  // --- selection -------------------------------------------------------
  function clearSelection() {
    selected = {}
    selectedCount = 0
    selectedBytes = 0
    allSelected = false
    anchorIndex = -1
  }

  function setSelected(ids, on) {
    var next = Object.assign({}, selected)
    var count = selectedCount
    var bytes = selectedBytes
    var byId = {}
    for (var i = 0; i < items.length; i++) byId[items[i].id] = items[i]
    for (var k = 0; k < ids.length; k++) {
      var id = ids[k]
      var was = next[id] === true
      if (on && !was) { next[id] = true; count++; bytes += byId[id] ? byId[id].size : 0 }
      if (!on && was) { delete next[id]; count--; bytes -= byId[id] ? byId[id].size : 0 }
    }
    selected = next
    selectedCount = count
    selectedBytes = Math.max(0, bytes)
    allSelected = count > 0 && count === total
  }

  function toggleAt(index, mouse) {
    var item = items[index]
    if (!item) return
    if (mouse && (mouse.modifiers & Qt.ShiftModifier) && anchorIndex >= 0) {
      setSelected(Layout.rangeIds(items, anchorIndex, index), true)
    } else {
      setSelected([item.id], selected[item.id] !== true)
      anchorIndex = index
    }
    gallery.focusIndex = index
  }

  function selectAll() {
    send({ op: "ids", seq: pageSeq, query: currentQuery() })
  }

  function selectedIds() {
    return Object.keys(selected)
  }

  // --- delete ----------------------------------------------------------
  function askDelete(ids) {
    if (ids.length === 0) return
    pendingDelete = ids
    var shown = []
    for (var i = 0; i < ids.length && shown.length < 3; i++) if (thumbs[ids[i]]) shown.push(thumbs[ids[i]])
    confirm.previews = shown
    confirm.count = ids.length
    var bytes = 0
    if (ids === selectedIds() || ids.length === selectedCount) bytes = selectedBytes
    else for (var j = 0; j < items.length; j++) if (ids.indexOf(items[j].id) >= 0) bytes += items[j].size
    confirm.bytes = bytes
    confirm.show()
  }

  function confirmDelete() {
    confirm.hide()
    deleting = true
    send({ op: "delete", ids: pendingDelete, trash: trashCopies })
  }

  function finishDelete(event) {
    deleting = false
    var gone = {}
    for (var i = 0; i < event.ids.length; i++) gone[event.ids[i]] = true
    // Fade the tiles out first, then close the gaps.
    gallery.removing = gone
    removeLater.gone = gone
    removeLater.restart()
    summary = Object.assign({}, summary, { total: event.total, photos: event.photos, videos: event.videos, albums: event.albums })
    libraryVersion = event.version
    if (event.failed.length > 0) {
      toast.flash("Could not delete " + Layout.formatCount(event.failed.length, "item", "items"),
        event.failed[0].name + ": " + event.failed[0].message, true)
    } else {
      toast.flash((event.trash ? "Moved to Trash: " : "Deleted ") + Layout.formatCount(event.ids.length, "item", "items"),
        event.trash ? "Removed from " + deviceLabel + "; restore them from this computer's Trash" : "Removed from " + deviceLabel)
    }
  }

  Timer {
    id: removeLater
    property var gone: ({})
    interval: 230
    onTriggered: {
      var kept = root.items.filter(function(item) { return gone[item.id] !== true })
      root.total = Math.max(0, root.total - (root.items.length - kept.length))
      root.clearSelection()
      gallery.animateNext = true
      root.items = kept
      gallery.removing = {}
      if (root.viewerIndex >= 0) {
        if (kept.length === 0) root.viewerIndex = -1
        else root.showViewer(Math.min(root.viewerIndex, kept.length - 1))
      }
      root.loadMore()
    }
  }

  // --- download --------------------------------------------------------
  function download(ids) {
    if (ids.length === 0) return
    toast.running("Starting download…", "", 0)
    send({ op: "download", ids: ids })
  }

  function openFolder(path) {
    if (!path) return
    Quickshell.execDetached({
      command: ["/usr/bin/xdg-open", path],
      clearEnvironment: true,
      environment: root.sidecarEnvironment
    })
  }

  // Arrow keys walk the grid; up and down keep the column where the month
  // allows it.
  function moveFocus(key) {
    if (items.length === 0) return
    var index = gallery.focusIndex
    if (index < 0) { gallery.focusIndex = 0; gallery.ensureVisible(0); return }
    var tiles = gallery.laid.tiles
    var here = tiles[index]
    var next = index
    if (key === Qt.Key_Left) next = index - 1
    else if (key === Qt.Key_Right) next = index + 1
    else {
      var down = key === Qt.Key_Down
      var best = -1
      for (var i = index + (down ? 1 : -1); i >= 0 && i < tiles.length; i += down ? 1 : -1) {
        if (tiles[i].y === here.y) continue
        if (best >= 0 && tiles[i].y !== tiles[best].y) break
        if (best < 0 || Math.abs(tiles[i].x - here.x) < Math.abs(tiles[best].x - here.x)) best = i
      }
      if (best >= 0) next = best
    }
    next = Math.max(0, Math.min(items.length - 1, next))
    gallery.focusIndex = next
    gallery.ensureVisible(next)
    if (next >= items.length - gallery.laid.columns * 3) loadMore()
  }

  // --- viewer ----------------------------------------------------------
  function showViewer(index) {
    if (index < 0 || index >= items.length) return
    viewerIndex = index
    viewerPreview = ""
    gallery.focusIndex = index
    gallery.ensureVisible(index)
    if (items[index].kind === "photo") send({ op: "preview", id: items[index].id })
    if (index >= items.length - 3) loadMore()
    viewer.forceActiveFocus()
  }

  function closeViewer() {
    viewerIndex = -1
    viewerPreview = ""
    grid.forceActiveFocus()
  }

  onOpenedChanged: {
    if (opened && sidecarReady && phase === "ready") send({ op: "rescan" })
  }

  // --- bar button --------------------------------------------------------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰋩"
    tooltipText: root.opened ? "" : (root.deviceLabel || "Phone") + " — photos"
    onPressed: function(buttonCode) { root.toggle() }
  }

  // --- the window --------------------------------------------------------
  readonly property var firstScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

  FloatingWindow {
    id: window
    title: "Phone Photos"
    color: Color.popups.background
    implicitWidth: root.firstScreen ? Math.round(root.firstScreen.width * 0.7) : 1200
    implicitHeight: root.firstScreen ? Math.round(root.firstScreen.height * 0.8) : 820
    minimumSize: Qt.size(640, 460)
    visible: root.opened

    onVisibleChanged: {
      if (!visible && root.opened) root.close()
      if (visible) Qt.callLater(function() { grid.forceActiveFocus() })
    }

    Item {
      anchors.fill: parent

      Toolbar {
        id: toolbar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        deviceLabel: root.deviceLabel
        devices: root.devices
        currentDevice: root.currentDevice
        summary: root.summary
        kind: root.kind
        album: root.album
        busy: root.phase === "scanning" || root.phase === "mounting"
        onKindPicked: function(value) { root.kind = value }
        onAlbumPicked: function(value) { root.album = value }
        onDevicePicked: function(id) { root.send({ op: "device", id: id }) }
        onRescan: root.send({ op: "rescan" })
        onSearchTextChanged: {
          root.searchText = searchText.trim()
          searchDebounce.restart()
        }
      }

      Rectangle {
        id: rule
        anchors.top: toolbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Util.alpha(Color.popups.text, 0.08)
      }

      FocusScope {
        id: grid
        anchors.top: rule.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        focus: true

        Keys.onPressed: function(event) {
          var ctrl = event.modifiers & Qt.ControlModifier
          if (ctrl && event.key === Qt.Key_A) { root.selectAll(); event.accepted = true }
          else if (ctrl && event.key === Qt.Key_F) { toolbar.focusSearch(); event.accepted = true }
          else if (event.key === Qt.Key_Escape) {
            if (root.selectedCount > 0) root.clearSelection()
            else root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Delete && root.selectedCount > 0) {
            root.askDelete(root.selectedIds()); event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
              || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            root.moveFocus(event.key); event.accepted = true
          } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && gallery.focusIndex >= 0) {
            root.showViewer(gallery.focusIndex); event.accepted = true
          } else if (event.key === Qt.Key_Space && gallery.focusIndex >= 0) {
            root.toggleAt(gallery.focusIndex, { modifiers: event.modifiers }); event.accepted = true
          }
        }

        Gallery {
          id: gallery
          anchors.fill: parent
          visible: root.phase === "ready" && root.items.length > 0
          opacity: visible ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 220 } }
          items: root.items
          total: root.total
          selected: root.selected
          selectedCount: root.selectedCount
          loading: root.pageLoading
          missing: root.missing
          monthCounts: root.monthCounts
          onNeedMore: root.loadMore()
          onWantThumbs: function(ids) { root.send({ op: "thumbs", ids: ids }) }
          onOpen: function(index) { root.selectedCount > 0 ? root.toggleAt(index, null) : root.showViewer(index) }
          onToggle: function(index, mouse) { root.toggleAt(index, mouse) }
        }

        StatusView {
          anchors.fill: parent
          visible: !gallery.visible
          phase: root.phase === "ready"
            ? (root.pageLoading ? "scanning" : (root.summary.total === 0 ? "empty" : "nomatch"))
            : (root.connected ? root.phase : "none")
          message: root.phaseMessage
          query: root.searchText
          deviceLabel: root.deviceLabel
          onRetry: root.send({ op: "rescan" })
        }

        SelectionBar {
          count: root.selectedCount
          bytes: root.selectedBytes
          allSelected: root.allSelected
          deleting: root.deleting
          onSelectAll: root.selectAll()
          onClearSelection: root.clearSelection()
          onDownload: root.download(root.selectedIds())
          onRemove: root.askDelete(root.selectedIds())
        }
      }

      Viewer {
        id: viewer
        shown: root.viewerIndex >= 0
        item: root.viewerIndex >= 0 ? root.items[root.viewerIndex] : null
        preview: root.viewerPreview
        hasPrevious: root.viewerIndex > 0
        hasNext: root.viewerIndex >= 0 && root.viewerIndex < root.items.length - 1
        onClosed: root.closeViewer()
        onPrevious: root.showViewer(root.viewerIndex - 1)
        onNext: root.showViewer(root.viewerIndex + 1)
        onDownload: if (viewer.item) root.download([viewer.item.id])
        onRemove: if (viewer.item) root.askDelete([viewer.item.id])
      }

      ConfirmDelete {
        id: confirm
        deviceLabel: root.deviceLabel
        keepCopy: root.trashCopies
        onKeepCopyToggled: function(value) { root.setTrashCopies(value) }
        onConfirmed: root.confirmDelete()
        onCancelled: {
          confirm.hide()
          if (root.viewerIndex >= 0) viewer.forceActiveFocus()
          else grid.forceActiveFocus()
        }
      }

      Toast {
        id: toast
        onAction: root.openFolder(root.downloadedFolder)
      }
    }
  }
}
