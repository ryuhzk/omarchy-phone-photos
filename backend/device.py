"""Talking to a phone over MTP, through GVfs.

Every operation here takes an Item that came out of a scan, never a path from
the UI, and reaches the phone only through GIO. Images from the phone are
decoded by GdkPixbuf, whose loaders run in glycin's sandbox, and re-encoded
before anything else sees them, so the shell only ever decodes JPEGs this
module wrote.
"""
import os

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, Gio, GLib  # noqa: E402

import library as lib  # noqa: E402

SCAN_ATTRIBUTES = "standard::name,standard::type,standard::size,standard::content-type,time::modified"
THUMB_SIZE = 512
PREVIEW_SIZE = 2400
MAX_EMBEDDED_THUMB = 4 * 1024 * 1024
# Photos are decoded from memory, counted as they arrive: the size the phone
# reports is not trusted to bound what it sends.
MAX_DECODE_BYTES = 64 * 1024 * 1024


class Phone:
    """One MTP volume."""

    def __init__(self, volume):
        self.volume = volume
        root = volume.get_activation_root()
        self.uri = root.get_uri() if root else ""
        self.label = volume.get_name() or "Phone"
        self.id = lib.item_id("phone", "", self.uri)[:12]

    def root(self, monitor):
        """The mounted phone's root, or None while it is not mounted.

        A phone mounted by location (a file manager, `gio mount`) has a mount
        that is not tied to its volume, so the mounts are searched too.
        """
        mount = self.volume.get_mount()
        if mount is not None:
            return mount.get_root()
        for mount in monitor.get_mounts():
            root = mount.get_root()
            if root is not None and root.get_uri() == self.uri:
                return root
        return None

    def mount(self, callback):
        """Mount the phone; `callback(error_or_None)` runs on the main loop."""
        location = Gio.File.new_for_uri(self.uri)

        def done(source, result):
            try:
                source.mount_enclosing_volume_finish(result)
            except GLib.Error as error:
                if not error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.ALREADY_MOUNTED):
                    callback(error)
                    return
            callback(None)

        location.mount_enclosing_volume(Gio.MountMountFlags.NONE, Gio.MountOperation(), None, done)


def mtp_phones(monitor):
    phones = []
    for volume in monitor.get_volumes():
        root = volume.get_activation_root()
        if root is not None and root.get_uri_scheme() == "mtp":
            phones.append(Phone(volume))
    return phones


def storages(root):
    """The phone's storages (internal, SD card). Empty while the phone is locked."""
    result = []
    for info in root.enumerate_children("standard::name,standard::type", Gio.FileQueryInfoFlags.NONE, None):
        if info.get_file_type() == Gio.FileType.DIRECTORY and lib.safe_component(info.get_name()):
            result.append(info.get_name())
    return result


def scan(root, device, cancellable):
    """Every photo and video under DCIM, Pictures and Movies on every storage."""
    items = []
    for storage in storages(root):
        storage_dir = root.get_child(storage)
        for top in lib.MEDIA_ROOTS:
            _walk(storage_dir.get_child(top), device, storage, [top], 0, items, cancellable)
            if len(items) >= lib.MAX_ITEMS:
                return items
    return items


def _walk(folder, device, storage, parts, depth, items, cancellable):
    try:
        children = folder.enumerate_children(SCAN_ATTRIBUTES, Gio.FileQueryInfoFlags.NONE, cancellable)
    except GLib.Error:
        return
    for info in children:
        if cancellable.is_cancelled() or len(items) >= lib.MAX_ITEMS:
            return
        name = info.get_name()
        if not name or name.startswith(".") or not lib.safe_component(name):
            continue
        if info.get_file_type() == Gio.FileType.DIRECTORY:
            if depth < lib.MAX_DEPTH:
                _walk(folder.get_child(name), device, storage, parts + [name], depth + 1, items, cancellable)
            continue
        modified = info.get_modification_date_time()
        item = lib.make_item(
            device, storage, parts + [name],
            info.get_attribute_string("standard::content-type"),
            info.get_size(),
            modified.to_unix() if modified else 0,
        )
        if item is not None:
            items.append(item)


def file_for(root, item):
    return root.get_child(item.storage).resolve_relative_path(item.path)


def _memory(data):
    return Gio.MemoryInputStream.new_from_bytes(GLib.Bytes.new(data))


def _read_bounded(stream, limit):
    """All of `stream`, or None as soon as it passes `limit` bytes."""
    chunks = []
    total = 0
    while True:
        chunk = stream.read_bytes(65536, None).get_data()
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            stream.close(None)
            return None
        chunks.append(chunk)
    stream.close(None)
    return b"".join(chunks)


def _save_jpeg(pixbuf, target, quality):
    """Write through a temporary file so a half-written image is never read."""
    temporary = target + ".tmp"
    pixbuf.savev(temporary, "jpeg", ["quality"], [str(quality)])
    os.chmod(temporary, 0o600)
    os.replace(temporary, target)


def _decoded_at_scale(stream, size):
    pixbuf = GdkPixbuf.Pixbuf.new_from_stream_at_scale(stream, size, size, True, None)
    oriented = pixbuf.apply_embedded_orientation()
    return oriented or pixbuf


def make_thumbnail(root, item, target):
    """Write a thumbnail for `item` to `target`. False when there is none to be had."""
    source = file_for(root, item)
    try:
        info = source.query_info("preview::icon", Gio.FileQueryInfoFlags.NONE, None)
        icon = info.get_attribute_object("preview::icon")
    except GLib.Error:
        icon = None
    # The phone's own thumbnail: instant for JPEG and video. Bounded, decoded in
    # the sandbox and re-encoded, like everything else from the phone.
    if isinstance(icon, Gio.LoadableIcon):
        try:
            stream, _ = icon.load(THUMB_SIZE, None)
            data = _read_bounded(stream, MAX_EMBEDDED_THUMB)
            if data:
                _save_jpeg(_decoded_at_scale(_memory(data), THUMB_SIZE), target, 85)
                return True
        except GLib.Error:
            pass
    # Otherwise decode the photo itself (HEIF, PNG, …). Videos without a
    # thumbnail from the phone get a placeholder in the UI.
    if item.kind != "photo" or item.size > MAX_DECODE_BYTES:
        return False
    try:
        data = _read_bounded(source.read(None), MAX_DECODE_BYTES)
        if not data:
            return False
        pixbuf = _decoded_at_scale(_memory(data), THUMB_SIZE)
    except GLib.Error:
        return False
    _save_jpeg(pixbuf, target, 85)
    return True


def make_preview(root, item, target):
    """A large version of a photo for the viewer."""
    if item.kind != "photo" or item.size > MAX_DECODE_BYTES:
        return False
    try:
        data = _read_bounded(file_for(root, item).read(None), MAX_DECODE_BYTES)
        if not data:
            return False
        pixbuf = _decoded_at_scale(_memory(data), PREVIEW_SIZE)
    except GLib.Error:
        return False
    _save_jpeg(pixbuf, target, 90)
    return True


def delete(root, item):
    """Delete one file from the phone. There is no trash over MTP."""
    file_for(root, item).delete(None)


def download(root, item, folder, cancellable, progress):
    """Copy one file into `folder`. Returns the saved path, or None when already there."""
    target = lib.download_target(folder, item.name, item.size, os.path.exists, os.path.getsize)
    if target is None:
        return None
    partial = target + ".part"
    # Never write through something already standing at the temporary name.
    if os.path.lexists(partial):
        os.unlink(partial)
    destination = Gio.File.new_for_path(partial)
    try:
        file_for(root, item).copy(
            destination, Gio.FileCopyFlags.OVERWRITE | Gio.FileCopyFlags.NOFOLLOW_SYMLINKS,
            cancellable, lambda done, total, *_: progress(done), None,
        )
        if item.mtime > 0:
            os.utime(partial, (item.mtime, item.mtime))
        os.replace(partial, target)
    except BaseException:
        try:
            os.unlink(partial)
        except OSError:
            pass
        raise
    return target
