"""The phone layer against a local folder that stands in for a phone.

GIO treats a local folder and an MTP phone through the same interface, so the
bounds and the file handling can be checked without a device.
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

import device  # noqa: E402
import library as lib  # noqa: E402
from gi.repository import Gio, GLib  # noqa: E402


class Bounds(unittest.TestCase):
    def test_reads_stop_at_the_limit(self):
        stream = Gio.MemoryInputStream.new_from_bytes(GLib.Bytes.new(b"x" * 300_000))
        self.assertIsNone(device._read_bounded(stream, 100_000))

    def test_reads_under_the_limit_are_whole(self):
        stream = Gio.MemoryInputStream.new_from_bytes(GLib.Bytes.new(b"y" * 1000))
        self.assertEqual(device._read_bounded(stream, 100_000), b"y" * 1000)

    def test_decode_limit_does_not_trust_the_reported_size(self):
        # An item that claims to be tiny is still read with the byte limit.
        self.assertLessEqual(device.MAX_DECODE_BYTES, 64 * 1024 * 1024)


class LocalPhone(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = self.tmp.name
        os.makedirs(os.path.join(base, "phone", "Internal", "DCIM", "Camera"))
        self.photo = os.path.join(base, "phone", "Internal", "DCIM", "Camera", "a.jpg")
        with open(self.photo, "wb") as handle:
            handle.write(b"photo bytes")
        os.makedirs(os.path.join(base, "phone", "Internal", "DCIM", ".hidden"))
        self.root = Gio.File.new_for_path(os.path.join(base, "phone"))
        self.downloads = os.path.join(base, "downloads")
        os.makedirs(self.downloads)

    def tearDown(self):
        self.tmp.cleanup()

    def scan(self):
        return device.scan(self.root, "local", Gio.Cancellable())

    def test_scan_finds_media_and_skips_hidden(self):
        items = self.scan()
        self.assertEqual([(i.album, i.name) for i in items], [("Camera", "a.jpg")])

    def test_download_never_writes_through_a_planted_link(self):
        item = self.scan()[0]
        victim = os.path.join(self.tmp.name, "victim")
        with open(victim, "w") as handle:
            handle.write("keep me")
        os.symlink(victim, os.path.join(self.downloads, "a.jpg.part"))
        saved = device.download(self.root, item, self.downloads, Gio.Cancellable(), lambda done: None)
        self.assertEqual(saved, os.path.join(self.downloads, "a.jpg"))
        with open(saved, "rb") as handle:
            self.assertEqual(handle.read(), b"photo bytes")
        with open(victim) as handle:
            self.assertEqual(handle.read(), "keep me")
        self.assertFalse(os.path.lexists(os.path.join(self.downloads, "a.jpg.part")))

    def test_download_skips_an_identical_copy(self):
        item = self.scan()[0]
        first = device.download(self.root, item, self.downloads, Gio.Cancellable(), lambda done: None)
        self.assertIsNotNone(first)
        self.assertIsNone(device.download(self.root, item, self.downloads, Gio.Cancellable(), lambda done: None))

    def test_keep_in_trash_trashes_a_copy_and_leaves_the_phone_file(self):
        item = self.scan()[0]
        trashed = []
        original = Gio.File.trash

        def fake_trash(gfile, cancellable):
            trashed.append(gfile.get_path())
            os.remove(gfile.get_path())
            return True

        Gio.File.trash = fake_trash
        try:
            device.keep_in_trash(self.root, item, self.downloads, None)
            # An identical earlier download does not stand in for the Trash copy.
            with open(os.path.join(self.downloads, "a.jpg"), "wb") as handle:
                handle.write(b"photo bytes")
            device.keep_in_trash(self.root, item, self.downloads, None)
        finally:
            Gio.File.trash = original
        self.assertEqual([os.path.basename(p) for p in trashed], ["a.jpg", "a (2).jpg"])
        self.assertTrue(os.path.exists(self.photo))

    def test_failed_trash_leaves_no_copy_behind(self):
        item = self.scan()[0]
        original = Gio.File.trash

        def broken_trash(gfile, cancellable):
            raise GLib.Error("no trash here")

        Gio.File.trash = broken_trash
        try:
            with self.assertRaises(GLib.Error):
                device.keep_in_trash(self.root, item, self.downloads, None)
        finally:
            Gio.File.trash = original
        self.assertEqual(os.listdir(self.downloads), [])
        self.assertTrue(os.path.exists(self.photo))

    def test_delete_removes_only_that_file(self):
        library = lib.Library(self.scan())
        [item] = library.resolve([library.items[0].id, "not-an-id"])
        device.delete(self.root, item)
        self.assertFalse(os.path.exists(self.photo))
        self.assertTrue(os.path.isdir(os.path.dirname(self.photo)))


if __name__ == "__main__":
    unittest.main()
