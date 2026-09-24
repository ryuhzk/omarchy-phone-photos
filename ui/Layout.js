.pragma library

// Where every tile and month heading goes. Pure functions, no QML, so the
// gallery can be tested and re-laid-out without touching the scene.

// The number of columns for a width, keeping tiles near `target` pixels.
function columnsFor(width, target, gap) {
  if (width <= 0) return 1
  return Math.max(2, Math.min(12, Math.round((width + gap) / (target + gap))))
}

// Lay `items` (newest first, each with a `month` like "2026-09") out in
// rows under one heading per month. Returns tiles and headers in content
// coordinates and the total height.
function layout(items, width, target, gap, headerHeight) {
  var columns = columnsFor(width, target, gap)
  var size = Math.floor((width - gap * (columns - 1)) / columns)
  var tiles = []
  var headers = []
  var y = 0
  var column = 0
  var month = null
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (item.month !== month) {
      if (column !== 0) y += size + gap
      column = 0
      month = item.month
      headers.push({ month: month, y: y, count: 0 })
      y += headerHeight
    }
    headers[headers.length - 1].count++
    tiles.push({ id: item.id, index: i, x: column * (size + gap), y: y, size: size })
    column++
    if (column === columns) {
      column = 0
      y += size + gap
    }
  }
  if (column !== 0) y += size + gap
  return { tiles: tiles, headers: headers, height: y, size: size, columns: columns }
}

// The tiles whose rows overlap [top, bottom]. Tiles are in row order, so
// a binary search finds the first one.
function visibleRange(tiles, top, bottom) {
  var lo = 0
  var hi = tiles.length
  while (lo < hi) {
    var mid = (lo + hi) >> 1
    if (tiles[mid].y + tiles[mid].size < top) lo = mid + 1
    else hi = mid
  }
  var end = lo
  while (end < tiles.length && tiles[end].y <= bottom) end++
  return { first: lo, end: end }
}

// "2026-09" -> "September 2026".
var MONTHS = ["January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"]

function monthLabel(month) {
  var match = /^(\d{4})-(\d{2})$/.exec(String(month || ""))
  if (!match) return "Undated"
  var index = Number(match[2]) - 1
  return (MONTHS[index] || match[2]) + " " + match[1]
}

function formatBytes(bytes) {
  var value = Number(bytes) || 0
  var units = ["B", "KB", "MB", "GB", "TB"]
  var unit = 0
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000
    unit++
  }
  return (unit === 0 ? String(Math.round(value)) : value.toFixed(value < 10 ? 1 : 0)) + " " + units[unit]
}

function formatCount(count, one, many) {
  return count + " " + (count === 1 ? one : many)
}

// The ids between two indices, inclusive, in either order: shift-click.
function rangeIds(items, from, to) {
  var start = Math.max(0, Math.min(from, to))
  var stop = Math.min(items.length - 1, Math.max(from, to))
  var ids = []
  for (var i = start; i <= stop; i++) ids.push(items[i].id)
  return ids
}

if (typeof module !== "undefined") {
  module.exports = {
    columnsFor: columnsFor, layout: layout, visibleRange: visibleRange,
    monthLabel: monthLabel, formatBytes: formatBytes, formatCount: formatCount, rangeIds: rangeIds
  }
}
