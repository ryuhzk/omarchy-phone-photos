import os
import sys
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

import library as lib

DEVICE = "Example_Phone_0001"
NOW = int(time.mktime((2026, 9, 1, 12, 0, 0, 0, 0, -1)))


def item(parts, content_type="", size=1000, mtime=NOW):
    return lib.make_item(DEVICE, "Internal storage", parts, content_type, size, mtime)


class Classify(unittest.TestCase):
    def test_content_type_wins(self):
        self.assertEqual(lib.classify("x.bin", "image/heif"), "photo")
        self.assertEqual(lib.classify("x.bin", "video/mp4"), "video")

    def test_extension_when_type_is_missing(self):
        self.assertEqual(lib.classify("IMG_1.HEIC", ""), "photo")
        self.assertEqual(lib.classify("clip.MOV", None), "video")
        self.assertIsNone(lib.classify("notes.txt", ""))
        self.assertIsNone(lib.classify("noextension", ""))


class Items(unittest.TestCase):
    def test_album_is_the_folder_under_the_root(self):
        self.assertEqual(item(["DCIM", "Camera", "a.jpg"]).album, "Camera")
        self.assertEqual(item(["Pictures", "Screenshots", "2026", "s.png"]).album, "Screenshots")
        self.assertEqual(item(["DCIM", "loose.jpg"]).album, "DCIM")

    def test_ids_are_stable_and_distinct(self):
        a = item(["DCIM", "Camera", "a.jpg"])
        self.assertEqual(a.id, item(["DCIM", "Camera", "a.jpg"]).id)
        self.assertNotEqual(a.id, item(["DCIM", "Camera", "b.jpg"]).id)
        self.assertRegex(a.id, r"^[0-9a-f]{20}$")

    def test_names_that_are_not_one_component_are_refused(self):
        for parts in (["DCIM", "..", "a.jpg"], ["DCIM", "Camera", "a/b.jpg"], ["DCIM", "x\0.jpg"], ["DCIM", "."]):
            self.assertIsNone(item(parts), parts)
        self.assertIsNone(lib.make_item(DEVICE, "..", ["DCIM", "a.jpg"], "image/jpeg", 1, NOW))
        self.assertTrue(lib.safe_component("Screenshot (1).png"))

    def test_non_media_is_dropped(self):
        self.assertIsNone(item(["DCIM", "Camera", ".thumbdata"]))

    def test_public_view_has_no_path(self):
        view = item(["DCIM", "Camera", "a.jpg"]).public()
        self.assertNotIn("path", view)
        self.assertEqual(view["month"], "2026-09")


class LibraryQueries(unittest.TestCase):
    def setUp(self):
        self.library = lib.Library([
            item(["DCIM", "Camera", "20260901_a.jpg"], "image/jpeg", mtime=NOW),
            item(["DCIM", "Camera", "20260815_b.mp4"], "video/mp4", mtime=NOW - 20 * 86400),
            item(["Pictures", "Screenshots", "Screenshot_1.png"], "image/png", mtime=NOW - 3600),
            item(["DCIM", "Camera", "20260101_c.heic"], "", mtime=NOW - 240 * 86400),
        ])

    def test_newest_first(self):
        names = [i.name for i in self.library.items]
        self.assertEqual(names, ["20260901_a.jpg", "Screenshot_1.png", "20260815_b.mp4", "20260101_c.heic"])

    def test_filters(self):
        self.assertEqual(len(self.library.matching({"kind": "video"})), 1)
        self.assertEqual(len(self.library.matching({"kind": "photo"})), 3)
        self.assertEqual(len(self.library.matching({"album": "Screenshots"})), 1)
        self.assertEqual(len(self.library.matching({"kind": "bogus"})), 4)

    def test_search_is_every_word(self):
        self.assertEqual([i.name for i in self.library.matching({"text": "screenshot"})], ["Screenshot_1.png"])
        self.assertEqual(len(self.library.matching({"text": "2026-08"})), 1)
        self.assertEqual(len(self.library.matching({"text": "camera video"})), 1)
        self.assertEqual(len(self.library.matching({"text": "CAMERA"})), 3)
        self.assertEqual(self.library.matching({"text": "nothing-like-this"}), [])

    def test_paging_is_bounded(self):
        total, page = self.library.page({}, 1, 2)
        self.assertEqual(total, 4)
        self.assertEqual([i.name for i in page], ["Screenshot_1.png", "20260815_b.mp4"])
        total, page = self.library.page({}, -5, 100000)
        self.assertEqual(len(page), 4)

    def test_resolve_only_knows_its_own_ids(self):
        first = self.library.items[0]
        got = self.library.resolve([first.id, first.id, "../../etc/passwd", 7, None])
        self.assertEqual(got, [first])
        self.assertEqual(self.library.resolve("not a list"), [])

    def test_remove(self):
        first = self.library.items[0]
        self.library.remove([first.id])
        self.assertNotIn(first.id, self.library.by_id)
        self.assertEqual(self.library.summary()["total"], 3)

    def test_month_counts_follow_the_query(self):
        self.assertEqual(self.library.month_counts({}), {"2026-09": 2, "2026-08": 1, "2026-01": 1})
        self.assertEqual(self.library.month_counts({"kind": "video"}), {"2026-08": 1})

    def test_summary(self):
        summary = self.library.summary()
        self.assertEqual((summary["photos"], summary["videos"]), (3, 1))
        self.assertEqual(summary["albums"][0], {"name": "Camera", "count": 3})


class Downloads(unittest.TestCase):
    def test_names_cannot_escape(self):
        self.assertEqual(lib.safe_file_name("../../x.jpg"), "_._.._x.jpg")
        self.assertEqual(lib.safe_file_name(".."), "untitled")
        self.assertEqual(lib.safe_file_name("a\nb.jpg"), "ab.jpg")
        self.assertFalse(lib.safe_file_name(".hidden").startswith("."))

    def test_collisions(self):
        existing = {"/d/a.jpg": 5, "/d/a (2).jpg": 6}
        exists = existing.__contains__
        size_of = existing.get
        self.assertEqual(lib.download_target("/d", "b.jpg", 1, exists, size_of), "/d/b.jpg")
        self.assertIsNone(lib.download_target("/d", "a.jpg", 5, exists, size_of))
        self.assertIsNone(lib.download_target("/d", "a.jpg", 6, exists, size_of))
        self.assertEqual(lib.download_target("/d", "a.jpg", 7, exists, size_of), "/d/a (3).jpg")
        self.assertEqual(lib.download_target("/d", "a.jpg", 5, exists, size_of, skip_identical=False), "/d/a (3).jpg")


class Cache(unittest.TestCase):
    def test_key_changes_with_the_file(self):
        a = item(["DCIM", "Camera", "a.jpg"], size=1)
        b = item(["DCIM", "Camera", "a.jpg"], size=2)
        self.assertNotEqual(lib.cache_key(DEVICE, a), lib.cache_key(DEVICE, b))

    def test_eviction_is_least_recently_used(self):
        entries = [("old", 40, 1), ("new", 40, 3), ("mid", 40, 2)]
        self.assertEqual(lib.eviction_plan(entries, 100), ["old"])
        self.assertEqual(lib.eviction_plan(entries, 40), ["old", "mid"])
        self.assertEqual(lib.eviction_plan(entries, 1000), [])


if __name__ == "__main__":
    unittest.main()
