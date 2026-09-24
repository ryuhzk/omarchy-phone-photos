"""The Phone Photos sidecar: one JSON object per line in, one per line out.

It watches for phones, scans the one in use, and serves the panel pages of its
photos and videos, thumbnails, deletes and downloads. The panel names files
only by the ids this process handed out; it never sends a path.
"""
import json
import os
import queue
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gi  # noqa: E402

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

import device as phone_io  # noqa: E402
import library as lib  # noqa: E402

MAX_LINE = 1024 * 1024
THUMB_CACHE_LIMIT = 256 * 1024 * 1024
PREVIEW_CACHE_LIMIT = 256 * 1024 * 1024
LOCKED_RETRY_SECONDS = 3


class Output:
    def __init__(self, stream):
        self.stream = stream
        self.lock = threading.Lock()

    def __call__(self, event, **fields):
        fields["event"] = event
        line = (json.dumps(fields, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
        with self.lock:
            self.stream.write(line)
            self.stream.flush()


class Cache:
    """Thumbnails and previews, private to the user and bounded in size."""

    def __init__(self, base, name, limit):
        self.dir = os.path.join(base, name)
        os.makedirs(self.dir, mode=0o700, exist_ok=True)
        os.chmod(self.dir, 0o700)
        self.limit = limit
        self.writes = 0
        self.lock = threading.Lock()

    def path(self, key):
        return os.path.join(self.dir, key + ".jpg")

    def hit(self, key):
        path = self.path(key)
        if os.path.isfile(path):
            try:
                os.utime(path)
            except OSError:
                pass
            return path
        return None

    def wrote(self):
        with self.lock:
            self.writes += 1
            due = self.writes % 64 == 0
        if due:
            self.evict()

    def evict(self):
        entries = []
        with os.scandir(self.dir) as it:
            for entry in it:
                if entry.is_file(follow_symlinks=False):
                    stat = entry.stat(follow_symlinks=False)
                    entries.append((entry.path, stat.st_size, stat.st_mtime))
        for path in lib.eviction_plan(entries, self.limit):
            try:
                os.unlink(path)
            except OSError:
                pass


class ThumbQueue:
    """Thumbnails to make, most recently asked for first."""

    def __init__(self):
        self.pending = []
        self.condition = threading.Condition()

    def ask(self, ids):
        with self.condition:
            wanted = [i for i in ids if isinstance(i, str)][:400]
            wanted_set = set(wanted)
            self.pending = wanted + [i for i in self.pending if i not in wanted_set]
            del self.pending[2000:]
            self.condition.notify()

    def clear(self):
        with self.condition:
            self.pending = []

    def take(self):
        with self.condition:
            while not self.pending:
                self.condition.wait()
            return self.pending.pop(0)


class Sidecar:
    def __init__(self, emit):
        self.emit = emit
        self.monitor = Gio.VolumeMonitor.get()
        self.phones = []
        self.current = None  # Phone
        self.root = None  # Gio.File of the mounted phone
        self.library = lib.Library()
        self.version = 0
        self.lock = threading.RLock()
        self.jobs = queue.Queue()
        self.thumbs = ThumbQueue()
        self.scan_cancel = Gio.Cancellable()
        self.download_cancel = Gio.Cancellable()
        self.locked_retry = None
        cache_base = os.path.join(GLib.get_user_cache_dir(), "omarchy-phone-photos")
        os.makedirs(cache_base, mode=0o700, exist_ok=True)
        self.thumb_cache = Cache(cache_base, "thumbs", THUMB_CACHE_LIMIT)
        self.preview_cache = Cache(cache_base, "previews", PREVIEW_CACHE_LIMIT)
        for signal in ("volume-added", "volume-removed", "volume-changed", "mount-added", "mount-removed"):
            self.monitor.connect(signal, lambda *_: GLib.idle_add(self.refresh_phones))
        threading.Thread(target=self.job_worker, daemon=True).start()
        threading.Thread(target=self.thumb_worker, daemon=True).start()
        threading.Thread(target=lambda: (self.thumb_cache.evict(), self.preview_cache.evict()), daemon=True).start()

    # --- phones ---------------------------------------------------------

    def refresh_phones(self):
        self.phones = phone_io.mtp_phones(self.monitor)
        current_id = self.current.id if self.current else None
        still_here = next((p for p in self.phones if p.id == current_id), None)
        if still_here is None:
            self.forget_phone()
            if self.phones:
                self.use_phone(self.phones[0])
        self.emit("devices", devices=[{"id": p.id, "label": p.label} for p in self.phones],
                  current=self.current.id if self.current else None)
        if not self.phones:
            self.emit("state", phase="none")
        return False

    def is_current(self, phone):
        return self.current is not None and phone is not None and self.current.id == phone.id

    def forget_phone(self):
        self.scan_cancel.cancel()
        self.download_cancel.cancel()
        self.thumbs.clear()
        with self.lock:
            self.current = None
            self.root = None
            self.library = lib.Library()
            self.version += 1

    def use_phone(self, phone):
        self.current = phone
        if phone.root(self.monitor) is not None:
            self.mounted(phone)
            return
        self.emit("state", phase="mounting", device=phone.label)

        def done(error):
            if not self.is_current(phone):
                return
            if error is not None:
                self.emit("state", phase="error", device=phone.label, message=error.message)
                return
            self.mounted(phone)

        phone.mount(done)

    def mounted(self, phone):
        root = phone.root(self.monitor)
        if root is None:
            self.emit("state", phase="error", device=phone.label, message="The phone mounted but cannot be opened.")
            return
        with self.lock:
            self.root = root
        self.request_scan()

    def request_scan(self):
        if self.root is None:
            return
        self.scan_cancel.cancel()
        self.scan_cancel = Gio.Cancellable()
        self.jobs.put(("scan", self.scan_cancel))

    # --- workers --------------------------------------------------------

    def job_worker(self):
        while True:
            job = self.jobs.get()
            try:
                getattr(self, "run_" + job[0])(*job[1:])
            except Exception as error:  # the sidecar must outlive any one job
                self.emit("error", message=str(error))

    def run_scan(self, cancellable):
        root, phone = self.root, self.current
        if root is None or phone is None:
            return
        self.emit("state", phase="scanning", device=phone.label)
        try:
            if not phone_io.storages(root):
                self.emit("state", phase="locked", device=phone.label)
                GLib.timeout_add_seconds(LOCKED_RETRY_SECONDS, self.retry_locked, phone)
                return
            items = phone_io.scan(root, phone.uri, cancellable)
        except GLib.Error as error:
            self.emit("state", phase="error", device=phone.label, message=error.message)
            return
        if cancellable.is_cancelled() or not self.is_current(phone):
            return
        with self.lock:
            self.library = lib.Library(items)
            self.version += 1
            summary = self.library.summary()
            version = self.version
        self.emit("library", version=version, device=phone.label, **summary)
        self.emit("state", phase="ready", device=phone.label)

    def retry_locked(self, phone):
        if self.is_current(phone):
            self.request_scan()
        return False

    def run_delete(self, ids, keep_copies):
        with self.lock:
            items = self.library.resolve(ids)
            root, phone = self.root, self.current
        if root is None or phone is None:
            return
        folder = self.download_folder(phone) if keep_copies else None
        deleted, failed = [], []
        for index, item in enumerate(items):
            try:
                # A copy in the Trash first; if that fails, the phone keeps it.
                if keep_copies:
                    phone_io.keep_in_trash(root, item, folder, None)
                phone_io.delete(root, item)
                deleted.append(item.id)
            except GLib.Error as error:
                if error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.NOT_FOUND):
                    deleted.append(item.id)
                else:
                    failed.append({"id": item.id, "name": item.name, "message": error.message})
            except OSError as error:
                failed.append({"id": item.id, "name": item.name, "message": str(error)})
            if keep_copies or len(deleted) % 20 == 0 or index == len(items) - 1:
                self.emit("deleting", done=index + 1, total=len(items), trash=keep_copies)
        with self.lock:
            self.library.remove(deleted)
            self.version += 1
            summary = self.library.summary()
            version = self.version
        self.emit("deleted", ids=deleted, failed=failed, version=version, trash=keep_copies, **summary)

    def download_folder(self, phone):
        pictures = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES) \
            or os.path.join(GLib.get_home_dir(), "Pictures")
        folder = os.path.join(pictures, lib.safe_file_name(phone.label))
        os.makedirs(folder, exist_ok=True)
        return folder

    def run_download(self, ids, cancellable):
        with self.lock:
            items = self.library.resolve(ids)
            root, phone = self.root, self.current
        if root is None or phone is None:
            return
        folder = self.download_folder(phone)
        total_bytes = sum(item.size for item in items)
        state = {"base": 0, "last": 0.0}
        saved, skipped, failed = 0, 0, []

        def progress(done_in_file, name):
            now = time.monotonic()
            if now - state["last"] >= 0.15:
                state["last"] = now
                self.emit("downloading", bytes=state["base"] + done_in_file, total=total_bytes,
                          name=name, done=saved + skipped, count=len(items))

        for item in items:
            if cancellable.is_cancelled():
                break
            try:
                result = phone_io.download(root, item, folder, cancellable, lambda done, n=item.name: progress(done, n))
                if result is None:
                    skipped += 1
                else:
                    saved += 1
            except GLib.Error as error:
                if error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.CANCELLED):
                    break
                failed.append({"id": item.id, "name": item.name, "message": error.message})
            state["base"] += item.size
        self.emit("downloaded", saved=saved, skipped=skipped, failed=failed,
                  cancelled=cancellable.is_cancelled(), folder=folder)

    def thumb_worker(self):
        while True:
            item_id = self.thumbs.take()
            with self.lock:
                item = self.library.by_id.get(item_id)
                root, phone = self.root, self.current
            if item is None or root is None or phone is None:
                continue
            key = lib.cache_key(phone.uri, item)
            path = self.thumb_cache.hit(key)
            if path is None:
                target = self.thumb_cache.path(key)
                try:
                    if phone_io.make_thumbnail(root, item, target):
                        path = target
                        self.thumb_cache.wrote()
                except (GLib.Error, OSError) as error:
                    self.emit("thumb", id=item_id, path=None, message=str(error))
                    continue
            self.emit("thumb", id=item_id, path=path)

    def run_preview(self, item_id):
        with self.lock:
            item = self.library.by_id.get(item_id)
            root, phone = self.root, self.current
        if item is None or root is None or phone is None:
            return
        key = lib.cache_key(phone.uri, item)
        path = self.preview_cache.hit(key)
        if path is None:
            target = self.preview_cache.path(key)
            if phone_io.make_preview(root, item, target):
                path = target
                self.preview_cache.wrote()
        self.emit("preview", id=item_id, path=path)

    # --- commands from the panel ----------------------------------------

    def handle(self, message):
        op = message.get("op")
        if op == "hello":
            self.refresh_phones()
        elif op == "device":
            phone = next((p for p in self.phones if p.id == message.get("id")), None)
            if phone is not None and not self.is_current(phone):
                self.forget_phone()
                self.use_phone(phone)
                self.refresh_phones()
        elif op == "rescan":
            self.request_scan()
        elif op == "page":
            offset = max(0, int(message.get("offset") or 0))
            with self.lock:
                total, items = self.library.page(message.get("query"), offset, message.get("limit"))
                months = self.library.month_counts(message.get("query")) if offset == 0 else None
                version = self.version
                device = self.current.uri if self.current else ""
            rows = []
            for item in items:
                row = item.public()
                row["thumb"] = self.thumb_cache.hit(lib.cache_key(device, item)) if device else None
                rows.append(row)
            self.emit("page", seq=message.get("seq"), version=version, total=total,
                      offset=offset, items=rows, months=months)
        elif op == "ids":
            with self.lock:
                matches = self.library.matching(message.get("query"))
            self.emit("ids", seq=message.get("seq"), ids=[i.id for i in matches],
                      bytes=sum(i.size for i in matches))
        elif op == "thumbs":
            ids = message.get("ids")
            if isinstance(ids, list):
                self.thumbs.ask(ids)
        elif op == "preview":
            if isinstance(message.get("id"), str):
                self.jobs.put(("preview", message["id"]))
        elif op == "delete":
            if isinstance(message.get("ids"), list) and message["ids"]:
                self.jobs.put(("delete", message["ids"], message.get("trash") is True))
        elif op == "download":
            if isinstance(message.get("ids"), list) and message["ids"]:
                self.download_cancel = Gio.Cancellable()
                self.jobs.put(("download", message["ids"], self.download_cancel))
        elif op == "cancel":
            self.download_cancel.cancel()


def main():
    emit = Output(sys.stdout.buffer)
    sidecar = Sidecar(emit)
    loop = GLib.MainLoop()
    buffer = bytearray()
    stdin = sys.stdin.buffer.raw

    def readable(_fd, condition):
        if condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR):
            chunk = b""
        else:
            chunk = os.read(stdin.fileno(), 65536)
        if not chunk:
            loop.quit()
            return False
        buffer.extend(chunk)
        while True:
            newline = buffer.find(b"\n")
            if newline < 0:
                if len(buffer) > MAX_LINE:
                    buffer.clear()
                break
            line = bytes(buffer[:newline])
            del buffer[:newline + 1]
            if not line.strip() or len(line) > MAX_LINE:
                continue
            try:
                message = json.loads(line)
            except ValueError:
                continue
            if isinstance(message, dict):
                try:
                    sidecar.handle(message)
                except Exception as error:
                    emit("error", message=str(error))
        return True

    GLib.io_add_watch(stdin.fileno(), GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR, readable)
    emit("ready")
    loop.run()


if __name__ == "__main__":
    main()
