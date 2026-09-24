# Phone Photos for Omarchy

The photos and videos on an Android phone, in a gallery on your desktop, while
the phone is plugged in.

Plug the phone in over USB and an icon appears in the middle of the bar. Click
it for every photo and video on the phone, newest first and grouped by month.
Search them, pick one or many, download them, or delete them from the phone.
Unplug the phone and the icon goes away.

![The Phone Photos window: a grid of photos grouped by month, with filters and
search along the top](preview.png)

## What it does

- **Appears only when needed.** The bar icon is there while an Android phone is
  connected and gone when it is not.
- **Everything, newest first.** Photos and videos from `DCIM`, `Pictures` and
  `Movies` on every storage of the phone, grouped under a heading per month.
  Thumbnails load as you scroll and more of the library loads as you reach the
  end, so a phone with tens of thousands of photos opens as quickly as one with
  a hundred.
- **Filters and search.** All / Photos / Videos, one album at a time (Camera,
  Screenshots, WeChat…), and a search box that matches file names, album names,
  dates (`2026-08`, `2026-08-15`), and words like `video` or `screenshot`.
- **Selection.** Click a photo's check circle, or Ctrl-click, to start
  selecting; Shift-click picks everything in between; Ctrl A selects everything
  that matches the current filters, including what has not loaded yet.
- **Delete, with a second step.** Deleting asks first and shows what is about
  to go and how much it weighs. Phones have no trash over USB, so the dialog
  offers one: tick **Move them to this computer's Trash** and each item is first
  copied here and put in the Trash, from where it can be restored (to
  `~/Pictures/<phone name>/`); leave it unticked and the items are deleted from
  the phone for good. The dialog remembers your last choice. The rest of the
  grid slides together afterwards.
- **Download.** Selected photos and videos are copied to
  `~/Pictures/<phone name>/` with their original dates. A file that is already
  there with the same size is skipped; a different file with the same name is
  saved alongside it as `name (2).jpg`.
- **A viewer.** Click a photo to see it large, with ← and → to move through the
  gallery. Videos show their poster frame; download one to play it.

### Keys

| Key | What it does |
|---|---|
| Arrow keys | Move through the grid |
| Enter | Open the focused photo |
| Space | Select or unselect the focused photo |
| Ctrl A | Select everything that matches the filters |
| Delete | Delete the selection (asks first) |
| Ctrl F | Search |
| Esc | Clear the selection, close the viewer, or close the window |

## Requirements

Nothing needs installing on a standard Omarchy system. The plugin uses these
packages, all from the official Arch repositories and all present on Omarchy by
default:

| Package | What it is used for |
|---|---|
| `python` | Runs the plugin's helper process |
| `python-gobject` | Lets the helper use GIO and GdkPixbuf |
| `gvfs-mtp` (with `gvfs` and `libmtp`) | Talks to the phone over MTP: listing, reading, deleting, and the phone's own thumbnails |
| `gdk-pixbuf2` | Makes thumbnails and previews, applying the photo's rotation |
| `glycin` (with `libheif`, `bubblewrap`) | Decodes HEIF/HEIC photos, the default format on many phones, in a sandbox |

If you removed any of them, reinstall that package by the name in the table.

On the phone there is nothing to install and no developer option to turn on.
It needs to be unlocked and set to **File transfer** in the USB notification.

## Install

```bash
omarchy plugin add https://github.com/ryuhzk/omarchy-phone-photos --enable
```

`omarchy plugin add` shows what it is about to clone and asks before doing it.
`--enable` puts the widget in the middle of the bar. To place it somewhere else:

```bash
omarchy bar move ryuhzk.phone-photos --section right
```

or use **Setup → Plugins → Phone Photos**.

If the icon does not appear when a phone is plugged in, restart the shell once:

```bash
omarchy restart shell
```

## Connect a phone

1. Connect the phone with a USB cable.
2. Unlock it.
3. In the USB notification on the phone, choose **File transfer**. If the phone
   asks whether to allow access to its data, allow it.

The icon appears in the bar. Click it to open the gallery. If the phone is
still locked, the window says so and picks up as soon as it is unlocked.

## Settings

**Setup → Plugins → Phone Photos** has one setting, the same one as the box in
the delete dialog:

| Setting | What it does |
|---|---|
| `trashCopies` | Before deleting from the phone, put a copy of each item in this computer's Trash. Off by default; the delete dialog sets it to your last choice. |

## Update

```bash
omarchy plugin update ryuhzk.phone-photos
```

The update shows the diff before it applies anything.

## Remove

```bash
omarchy plugin remove ryuhzk.phone-photos
```

It asks first. Then it takes the widget off the bar, removes its entry from
`~/.config/omarchy/shell.json`, and deletes the plugin's folder under
`~/.config/omarchy/plugins/`.

The plugin keeps thumbnails and previews in `~/.cache/omarchy-phone-photos/`,
never more than 256 MB of each. Removing the plugin leaves that folder behind;
delete the folder `~/.cache/omarchy-phone-photos` if you want the space back.

Photos and videos you downloaded stay in `~/Pictures/<phone name>/`. Nothing
is ever installed on the phone.

## Troubleshooting

| What you see | What to do |
|---|---|
| No icon in the bar with the phone plugged in | Unlock the phone and choose **File transfer** in its USB notification. A cable that only charges will not work. |
| "Unlock the phone" | Unlock it, and allow access to phone data if it asks. The window continues on its own. |
| "The phone could not be read" | Another program may be holding the phone. Close it, unplug and replug the phone, then **Try again**. |
| A photo without a thumbnail | The phone offered none and the format could not be decoded. The photo is still there and can be downloaded. |

## How it works

`Panel.qml` is the bar icon and the window; the parts of the window are in
`ui/`. It starts one helper, `backend/phone_photos.py`, which watches for
phones through GVfs, reads the one in use, and answers the window's requests
one JSON line at a time. The window names photos only by ids the helper handed
out; it never sends a path.

[SECURITY.md](SECURITY.md) lists everything the plugin reads, writes and runs,
and the limits on each.

## Development

```bash
python3 -m unittest discover -s tests
bun test
omarchy plugin validate .
```

`bun test` runs the tests for the window's layout code (`ui/Layout.js`). Bun is
only needed for that; the plugin itself never uses it.

## License

[MIT](LICENSE)
