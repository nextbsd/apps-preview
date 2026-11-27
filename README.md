# Preview

Pictures and PDFs on NextBSD, as NeXTSTEP's Preview and macOS's: open a file
from File Viewer, page through it, zoom, rotate or export it.

- **Pictures:** PNG, JPEG, TIFF, GIF and BMP, and whatever else GNUstep's
  `NSBitmapImageRep` reads. The other pictures in the folder go down a
  sidebar (↑/↓ or a click moves through them; the search field narrows the
  list by name). Zoom with the toolbar, ⌘+ and ⌘-; ⌘0 fits the window, ⌘1
  is actual size. Rotate turns the picture a quarter; ⌘S saves it turned,
  and Preview asks when the window closes or you move on (a JPEG keeps its
  EXIF). The slideshow plays the folder full screen. The status bar shows
  "W × H pixels · FORMAT · size" and "N of M in folder". Photos are shown
  the way their EXIF says is up.
- **PDF:** rendered by Poppler (poppler-cpp's `page_renderer`) at the
  screen's resolution when a page is shown, so text stays sharp at any zoom;
  the last few pages and every thumbnail are kept. Page thumbnails go down
  the sidebar. The search field marks every match on the pages; "N of M"
  and its arrows (⌘G, ⇧⌘G) go between them, and the status bar counts them.
  Dragging across text selects it; ⌘C copies it, and the context menu has
  Copy and Search for "…".
- **Info** (⌘I): a picture's dimensions, file size, format, colour and
  resolution, and when and with what camera it was taken when the file has
  EXIF; a PDF's pages, page size, title, author and producer.
- **Export** (⌘E): PNG, JPEG (with a quality slider), TIFF or PDF, full or
  half size, with the size the copy will be shown before it's saved. A PDF's
  page exports as a picture, or the PDF as itself.
- Light and Dark follow `NBAppearance`, like every NextBSD app.
- A help book, `Resources/Preview.help`, which Help shows (nextbsd/apps-help).

Its `Info-gnustep.plist` registers png, jpg/jpeg/jpe, tif/tiff, gif, bmp and
pdf (`NSTypes`), so File Viewer and the desktop open them in Preview, and so
do Screenshot and Scanner, which open what they save with `NSWorkspace`.
Someone already logged in picks the types up after `make_services`.

## Building

It needs GNUstep and poppler-cpp (`libpoppler-cpp.so.3`, headers in
`/usr/include/poppler/cpp`), both in NextBSD-gnustep-support and the GNUstep
SDK. `PVPoppler.cc` is the only C++; the rest is Objective-C.

```sh
. /System/Library/Makefiles/GNUstep.sh
gmake
gmake install        # /System/Applications/Preview.app
```

Installed by the NextBSD desktop as `/System/Applications/Preview.app`, built
by [nextbsd-desktop](https://github.com/nextbsd/nextbsd-desktop). Work is
tracked in [nextbsd/nextbsd](https://github.com/nextbsd/nextbsd).

BSD 2-Clause; see [LICENSE](LICENSE).
