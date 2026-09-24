import { describe, expect, test } from "bun:test"
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs"
import { createRequire } from "node:module"
import { tmpdir } from "node:os"
import { join } from "node:path"

// Layout.js is a QML JavaScript library. Load the shipped file with its pragma
// line removed, so the file under test is the file that ships.
const shipped = readFileSync(join(import.meta.dir, "..", "ui", "Layout.js"), "utf8")
const copy = join(mkdtempSync(join(tmpdir(), "layout-")), "Layout.cjs")
writeFileSync(copy, shipped.replace(/^\.pragma library\s*$/m, ""))
const Layout = createRequire(import.meta.url)(copy)

const items = (months) => months.map((month, i) => ({ id: `id${i}`, month }))

describe("layout", () => {
  test("one heading per month, rows restart under each", () => {
    const result = Layout.layout(items(["2026-09", "2026-09", "2026-09", "2026-08"]), 310, 100, 5, 40)
    expect(result.columns).toBe(3)
    expect(result.size).toBe(100)
    expect(result.headers.map((h) => [h.month, h.y, h.count])).toEqual([["2026-09", 0, 3], ["2026-08", 145, 1]])
    expect(result.tiles.map((t) => [t.x, t.y])).toEqual([[0, 40], [105, 40], [210, 40], [0, 185]])
    expect(result.height).toBe(290)
  })

  test("empty", () => {
    expect(Layout.layout([], 500, 100, 4, 40)).toMatchObject({ tiles: [], headers: [], height: 0 })
  })

  test("columns stay between 2 and 12", () => {
    expect(Layout.columnsFor(50, 180, 4)).toBe(2)
    expect(Layout.columnsFor(100000, 180, 4)).toBe(12)
  })
})

describe("visibleRange", () => {
  const { tiles } = Layout.layout(items(Array(30).fill("2026-09")), 310, 100, 5, 40)
  test("finds the rows in view", () => {
    expect(Layout.visibleRange(tiles, 0, 50)).toEqual({ first: 0, end: 3 })
    expect(Layout.visibleRange(tiles, 200, 300)).toEqual({ first: 3, end: 9 })
    expect(Layout.visibleRange(tiles, 99999, 100000)).toEqual({ first: 30, end: 30 })
  })
})

describe("labels", () => {
  test("months", () => {
    expect(Layout.monthLabel("2026-09")).toBe("September 2026")
    expect(Layout.monthLabel("unknown")).toBe("Undated")
  })

  test("bytes", () => {
    expect(Layout.formatBytes(0)).toBe("0 B")
    expect(Layout.formatBytes(3_880_000_000)).toBe("3.9 GB")
    expect(Layout.formatBytes(84_000_000)).toBe("84 MB")
  })

  test("range selection works in either direction", () => {
    const list = items(["a", "a", "a", "a"])
    expect(Layout.rangeIds(list, 3, 1)).toEqual(["id1", "id2", "id3"])
    expect(Layout.rangeIds(list, -4, 0)).toEqual(["id0"])
  })
})
