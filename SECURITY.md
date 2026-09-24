# Security

This document is for someone deciding whether to trust `ryuhzk.phone-photos`.
It says what the plugin reads, writes, deletes and runs, with what authority,
and how each is bounded. Each claim names the code that makes it true, so it can
be checked rather than believed.

There is no sandbox around the plugin itself. The window is QML inside
`omarchy-shell`, and it starts one Python helper; both run as the desktop user.
What follows describes a small surface, not an isolated one.

## What runs

| Piece                      | What it is                                             | When it runs |
| -------------------------- | ------------------------------------------------------ | ------------ |
| `Panel.qml`, `ui/*.qml`    | The bar icon and the gallery window                    | While the bar is up |
| `ui/Layout.js`             | Pure layout arithmetic, no I/O                         | Inside the window |
| `backend/phone_photos.py`  | The helper: phone detection, scanning, thumbnails, delete, download | While the bar is up |
| `backend/device.py`        | Every operation that touches the phone, through GIO    | Inside the helper |
| `backend/library.py`       | Pure functions: classification, search, paging, file names, cache eviction | Inside the helper |

The helper is started as one fixed command, with no shell and nothing resolved
through `PATH`:

```
/usr/bin/python3 -I <plugin>/backend/phone_photos.py
```

- `-I` is Python's isolated mode: it ignores every `PYTHON*` variable and the
  user's site-packages, so nothing in the environment or in `~/.local` can
  change what code the helper imports.
- It is started with `clearEnvironment: true` and receives only
  `PATH=/usr/bin:/bin` plus, when set, `HOME USER LANG LC_ALL XDG_RUNTIME_DIR
  DBUS_SESSION_BUS_ADDRESS XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME`
  (`Panel.qml`, `sidecarEnvironment`). The D-Bus and runtime-dir variables are
  what GIO needs to reach the GVfs daemons that talk to the phone.

The only other process the plugin starts is `/usr/bin/xdg-open <folder>`, with
the same closed environment, when you click **Open folder** after a download.

## How the phone is reached

Only through GIO and the GVfs MTP backend (`gvfs-mtp`), the same path the file
manager uses. The helper opens no socket and makes no network request, and it
reaches no device other than MTP volumes (`device.mtp_phones` keeps only volumes
whose activation root has the `mtp` scheme).

## The window never sends a path

Every photo and video is named between the window and the helper by an opaque
id: the first 20 hex digits of a SHA-256 over the device, storage and path
(`library.item_id`). The window can only send ids back. The helper looks each
one up in the list its own scan produced (`Library.resolve`), and ignores
anything that is not an id it handed out, so no message from the window can make
the helper read, copy or delete a file it did not find while scanning
`DCIM`, `Pictures` and `Movies`. `tests/test_library.py` covers this.

Scanning skips names that start with `.` and goes no deeper than six folders.
A phone reports its own file names, so a name that is empty, `.` or `..`, or
that contains `/` or a NUL, is refused before it can become an item
(`library.safe_component`): a device cannot make an id stand for any path
other than the one it listed. `tests/test_library.py` covers this.

## What it deletes

Only files the user selected and then confirmed in a dialog that states the
count and the size (`ui/ConfirmDelete.qml`, where keyboard focus starts on
**Cancel**). The window then sends the selected ids; the helper resolves them as
above and deletes each one with `Gio.File.delete` (`device.delete`).

MTP has no trash. When the dialog's **Move them to this computer's Trash** box
is ticked, each item is first copied into `~/Pictures/<phone name>/` under a
name that collides with nothing and then moved to the desktop Trash with
`Gio.File.trash` (`device.keep_in_trash`). The phone file is deleted only after
both steps succeed; if either fails, the partial copy is removed, the phone file
is left alone, and the failure is reported. `tests/test_device.py` covers both
outcomes. When the box is not ticked, the dialog says the deletion is permanent,
and it is.

## What it reads from the phone, and how that is bounded

- **Listings** of `DCIM`, `Pictures` and `Movies`: names, sizes, dates, types.
  At most 200,000 items are kept (`library.MAX_ITEMS`).
- **Thumbnails** the phone itself offers for JPEG and video, read up to 4 MB
  each (`device.MAX_EMBEDDED_THUMB`); anything larger is discarded unread.
- **Photos** without a phone thumbnail (HEIF, PNG…), up to 64 MB each
  (`device.MAX_DECODE_BYTES`). The limit is counted on the bytes as they
  arrive (`device._read_bounded`), not taken from the size the phone reports,
  so a device that lies about a file's size still cannot make the helper hold
  more than the limit; the read stops and the photo gets a placeholder.
  `tests/test_device.py` covers this.
- **Files you download**, copied with GIO.

**Nothing from the phone is decoded in the shell.** Every image the helper gets
from the phone — its own thumbnails included — is decoded by GdkPixbuf, whose
loaders are glycin's: separate processes confined by bubblewrap and seccomp
(`glycin` depends on `bubblewrap` and `libseccomp`). The result is scaled down
and re-encoded as a new JPEG (`device._decoded_at_scale`, `device._save_jpeg`). The window only
ever loads those re-encoded files, so a malformed file on the phone reaches a
sandboxed decoder, never the shell's.

## What it writes

| Where | What | Bound |
| ----- | ---- | ----- |
| `~/.cache/omarchy-phone-photos/thumbs/` | Thumbnails the helper made | 256 MB, least recently used removed first |
| `~/.cache/omarchy-phone-photos/previews/` | Large previews for the viewer | 256 MB, least recently used removed first |
| `~/Pictures/<phone name>/` | Files you chose to download | What you chose |
| The desktop Trash (`~/.local/share/Trash`) | Copies of deleted items, when that box is ticked | What you deleted |
| `~/.config/omarchy/shell.json` | This widget's own `trashCopies` setting, through the shell's plugin settings API | One boolean |

- The cache folders are created `0700` and each file `0600`, because they hold
  pictures of the user's life (`phone_photos.Cache`, `device._save_jpeg`).
- Cache files are written to a temporary name and renamed into place, so a
  half-written image is never shown.
- Downloads keep the file name from the phone after removing `/`, control
  characters and a leading `.` (`library.safe_file_name`), so a name cannot leave
  the download folder or hide itself. A file that is already there with the same
  size is skipped; otherwise the new one is saved alongside as `name (2).ext`,
  never over an existing file (`library.download_target`). The copy goes to
  `<name>.part` and is renamed only once complete; anything already standing at
  that temporary name, a symbolic link included, is removed first rather than
  written through (`device.download`, covered by `tests/test_device.py`).
- The phone's name used for the folder goes through the same cleaning.

Nothing is written to the phone, and nothing is written outside the places
above. The settings write goes through the shell's own `updateEntryInline` for
this widget's entry only (`Panel.qml`, `setTrashCopies`), carrying over the
entry's other settings unchanged; it happens only when the box is clicked.

## What the helper accepts

One JSON object per line on standard input, at most 1 MB per line
(`phone_photos.MAX_LINE`); longer lines are dropped. Unknown operations are
ignored. A page is at most 300 items (`library.MAX_PAGE`), a thumbnail request
at most 400 ids, and the thumbnail queue at most 2,000 entries.

## What it does not do

- It runs nothing as root and never asks for a password.
- It installs nothing, on the computer or on the phone, and turns on no
  developer option.
- It does not upload anything anywhere.
- It does not start any work on its own beyond scanning a phone that was plugged
  in; deleting and downloading happen only on request.

## Reporting a problem

Open an issue at https://github.com/ryuhzk/omarchy-phone-photos/issues. For
something you would rather not describe in public, say so in the issue and ask
for a private channel.
