"""The phone's photos and videos as a list, and every decision made about it.

Nothing in this module touches the phone, the disk or the network, so all of it
can be tested without a device.
"""
import hashlib
import os
import time
from dataclasses import dataclass, field

# The folders a phone keeps pictures and recordings in. Anything outside them
# (Download, Android/…) is other apps' files, not the gallery.
MEDIA_ROOTS = ("DCIM", "Pictures", "Movies")
MAX_DEPTH = 6
MAX_ITEMS = 200_000
MAX_PAGE = 300

IMAGE_EXTENSIONS = {
    "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "dng", "jxl",
}
VIDEO_EXTENSIONS = {"mp4", "mov", "m4v", "3gp", "3gpp", "mkv", "webm", "avi"}


@dataclass
class Item:
    """One photo or video on the phone."""

    id: str
    storage: str
    path: str  # relative to the storage root, "/"-separated
    name: str
    album: str
    kind: str  # "photo" or "video"
    size: int
    mtime: int  # seconds since the epoch
    search: str = field(default="", repr=False)

    def month(self):
        return time.strftime("%Y-%m", time.localtime(self.mtime)) if self.mtime > 0 else "unknown"

    def public(self):
        return {
            "id": self.id,
            "name": self.name,
            "album": self.album,
            "kind": self.kind,
            "size": self.size,
            "mtime": self.mtime,
            "month": self.month(),
        }


def item_id(device, storage, path):
    """A stable id for one file. The UI only ever names files by this."""
    digest = hashlib.sha256(f"{device}\0{storage}\0{path}".encode("utf-8", "surrogatepass"))
    return digest.hexdigest()[:20]


def classify(name, content_type):
    """"photo", "video", or None for anything that is not gallery media."""
    content_type = (content_type or "").lower()
    if content_type.startswith("image/"):
        return "photo"
    if content_type.startswith("video/"):
        return "video"
    extension = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    if extension in IMAGE_EXTENSIONS:
        return "photo"
    if extension in VIDEO_EXTENSIONS:
        return "video"
    return None


def album_for(parts):
    """The album a file belongs to: the folder under DCIM/Pictures/Movies."""
    if len(parts) >= 3:
        return parts[1]
    return parts[0]


def safe_component(name):
    """Whether a name from the phone is one plain path component.

    A device reports its own file names; one that says "..", or puts a "/" in a
    name, must not be able to make an id stand for some other path.
    """
    return (isinstance(name, str) and name not in ("", ".", "..")
            and "/" not in name and "\0" not in name and len(name) <= 1024)


def make_item(device, storage, parts, content_type, size, mtime):
    """An Item for a file at `parts` (path components under the storage), or None."""
    if not safe_component(storage) or not all(safe_component(part) for part in parts):
        return None
    name = parts[-1]
    kind = classify(name, content_type)
    if kind is None:
        return None
    path = "/".join(parts)
    item = Item(
        id=item_id(device, storage, path),
        storage=storage,
        path=path,
        name=name,
        album=album_for(parts),
        kind=kind,
        size=max(0, int(size or 0)),
        mtime=max(0, int(mtime or 0)),
    )
    date = time.strftime("%Y-%m-%d", time.localtime(item.mtime)) if item.mtime else ""
    words = [name, item.album, date, kind]
    if "screenshot" in (name + " " + item.album).lower():
        words.append("screenshot")
    item.search = " ".join(words).lower()
    return item


class Library:
    """Everything found on one phone, newest first."""

    def __init__(self, items=()):
        self.items = []
        self.by_id = {}
        self.replace(items)

    def replace(self, items):
        unique = {}
        for item in items:
            unique[item.id] = item
        self.items = sorted(unique.values(), key=lambda i: (-i.mtime, i.name))[:MAX_ITEMS]
        self.by_id = {item.id: item for item in self.items}

    def remove(self, ids):
        gone = set(ids)
        self.items = [item for item in self.items if item.id not in gone]
        for item_id_ in gone:
            self.by_id.pop(item_id_, None)

    def albums(self):
        counts = {}
        for item in self.items:
            counts[item.album] = counts.get(item.album, 0) + 1
        return [{"name": name, "count": count} for name, count in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))]

    def summary(self):
        photos = sum(1 for item in self.items if item.kind == "photo")
        return {"total": len(self.items), "photos": photos, "videos": len(self.items) - photos, "albums": self.albums()}

    def matching(self, query):
        """Every item that passes the filters in `query`, newest first."""
        query = query if isinstance(query, dict) else {}
        kind = query.get("kind") if query.get("kind") in ("photo", "video") else None
        album = query.get("album") if isinstance(query.get("album"), str) and query.get("album") else None
        text = query.get("text") if isinstance(query.get("text"), str) else ""
        tokens = [token for token in text.lower().split() if token][:16]
        result = []
        for item in self.items:
            if kind and item.kind != kind:
                continue
            if album and item.album != album:
                continue
            if tokens and not all(token in item.search for token in tokens):
                continue
            result.append(item)
        return result

    def page(self, query, offset, limit):
        matches = self.matching(query)
        offset = max(0, int(offset or 0))
        limit = max(1, min(MAX_PAGE, int(limit or MAX_PAGE)))
        return len(matches), matches[offset:offset + limit]

    def month_counts(self, query):
        """How many matching items each month holds, for the month headings."""
        counts = {}
        for item in self.matching(query):
            month = item.month()
            counts[month] = counts.get(month, 0) + 1
        return counts

    def resolve(self, ids):
        """The items named by `ids`, ignoring anything that is not an id we handed out."""
        if not isinstance(ids, list):
            return []
        seen = set()
        result = []
        for value in ids[:MAX_ITEMS]:
            if isinstance(value, str) and value in self.by_id and value not in seen:
                seen.add(value)
                result.append(self.by_id[value])
        return result


def safe_file_name(name):
    """A file name that cannot leave the folder it is written into."""
    name = name.replace("/", "_").replace("\0", "_").strip()
    name = "".join(ch for ch in name if ch >= " " and ch != "\x7f")
    if name in ("", ".", ".."):
        name = "untitled"
    if name.startswith("."):
        name = "_" + name[1:]
    return name[:200]


def download_target(folder, name, size, exists, size_of, skip_identical=True):
    """Where to save `name`, or None when an identical copy is already there.

    With `skip_identical` off there is always a fresh name, for a copy that
    must exist on its own (one headed for the Trash). `exists(path)` and
    `size_of(path)` are injected so the rule can be tested.
    """
    name = safe_file_name(name)
    stem, dot, extension = name.rpartition(".")
    if not dot:
        stem, extension = name, ""
    candidate = os.path.join(folder, name)
    counter = 1
    while exists(candidate):
        if skip_identical and size_of(candidate) == size:
            return None
        counter += 1
        suffix = f" ({counter})"
        candidate = os.path.join(folder, f"{stem}{suffix}.{extension}" if extension else f"{stem}{suffix}")
    return candidate


def cache_key(device, item):
    """Cache file name for an item: changes whenever the file on the phone does."""
    raw = f"{device}\0{item.storage}\0{item.path}\0{item.size}\0{item.mtime}"
    return hashlib.sha256(raw.encode("utf-8", "surrogatepass")).hexdigest()[:32]


def eviction_plan(entries, limit_bytes):
    """Which cache files to delete so the rest fit in `limit_bytes`.

    `entries` is a list of (path, size, last_used); the least recently used go first.
    """
    total = sum(size for _, size, _ in entries)
    doomed = []
    for path, size, _ in sorted(entries, key=lambda entry: entry[2]):
        if total <= limit_bytes:
            break
        doomed.append(path)
        total -= size
    return doomed
