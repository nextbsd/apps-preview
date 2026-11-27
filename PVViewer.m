/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PVViewer.h"
#import "PVExport.h"
#import "PVImage.h"
#import "PVPDFDocument.h"
#import "PVSlideshow.h"
#import "PVStyle.h"
#import <GNUstepBase/GNUstep.h>

NSString *const PVViewerClosedNotification = @"PVViewerClosed";

#define PVToolbarHeight 40
#define PVStatusHeight 26
#define PVSidebarWidth 156
#define PVMargin 22
#define PVSidebarKey @"PreviewShowsSidebar"

/* The window's content: lays its views out when it changes size. */
@interface PVContentView : NSView
{
  PVViewer *viewer;
}
- (id) initWithFrame: (NSRect)frame viewer: (PVViewer *)v;
@end

@implementation PVContentView
- (id) initWithFrame: (NSRect)frame viewer: (PVViewer *)v
{
  if ((self = [super initWithFrame: frame]) != nil)
    viewer = v;
  return self;
}
- (BOOL) isFlipped
{
  return YES;
}
- (void) resizeSubviewsWithOldSize: (NSSize)old
{
  [viewer layoutViews];
}
@end

/* "Scan 2" before "Scan 10", ignoring case, as File Viewer sorts. */
static NSInteger
PVCompareNames (id a, id b, void *context)
{
  return [(NSString *) a compare: b
                         options: NSCaseInsensitiveSearch | NSNumericSearch];
}

static NSString *
PVQuoted (NSString *s)
{
  return [NSString stringWithFormat: @"“%@”", s];
}

@interface PVViewer ()
- (id) initWithPath: (NSString *)p;
- (BOOL) loadImage: (NSString *)p;
- (void) updateStatus;
- (void) updateZoom;
- (void) applyZoom: (double)z fit: (BOOL)f;
- (void) rebuildInfo;
@end

@implementation PVViewer

+ (PVViewer *) viewerWithPath: (NSString *)p
{
  return AUTORELEASE ([[PVViewer alloc] initWithPath: p]);
}

- (NSView *) makeViews: (NSRect)frame
{
  PVContentView *content = AUTORELEASE ([[PVContentView alloc]
                                          initWithFrame: frame viewer: self]);

  toolbar = [[PVToolbar alloc]
              initWithFrame: NSMakeRect (0, 0, frame.size.width,
                                         PVToolbarHeight)
                      owner: self];
  [content addSubview: toolbar];

  sideScroll = [[NSScrollView alloc] initWithFrame:
                                       NSMakeRect (0, PVToolbarHeight,
                                                   PVSidebarWidth, 100)];
  [sideScroll setHasVerticalScroller: YES];
  [sideScroll setBorderType: NSNoBorder];
  [sideScroll setDrawsBackground: YES];
  [sideScroll setBackgroundColor: [PVStyle sidebar]];
  sidebar = [[PVSidebar alloc] initWithFrame:
                                 NSMakeRect (0, 0, PVSidebarWidth, 100)
                                       owner: self];
  [sideScroll setDocumentView: sidebar];
  [content addSubview: sideScroll];

  scroll = [[NSScrollView alloc] initWithFrame:
                                   NSMakeRect (PVSidebarWidth,
                                               PVToolbarHeight, 100, 100)];
  [scroll setHasVerticalScroller: YES];
  [scroll setHasHorizontalScroller: YES];
  [scroll setAutohidesScrollers: YES];
  [scroll setBorderType: NSNoBorder];
  [scroll setDrawsBackground: YES];
  [scroll setBackgroundColor: [PVStyle backdrop]];
  if (isPDF)
    {
      pdfCanvas = [[PVPDFCanvas alloc] initWithFrame:
                                         NSMakeRect (0, 0, 100, 100)
                                               owner: self];
      [pdfCanvas setDocument: pdf];
      [scroll setDocumentView: pdfCanvas];
      [[scroll contentView] setPostsBoundsChangedNotifications: YES];
      [[NSNotificationCenter defaultCenter]
        addObserver: self selector: @selector(scrolled:)
               name: NSViewBoundsDidChangeNotification
             object: [scroll contentView]];
    }
  else
    {
      imageCanvas = [[PVImageCanvas alloc] initWithFrame:
                                             NSMakeRect (0, 0, 100, 100)
                                                   owner: self];
      [scroll setDocumentView: imageCanvas];
    }
  [content addSubview: scroll];

  status = [[PVStatusBar alloc] initWithFrame: NSMakeRect (0, 0, 100,
                                                           PVStatusHeight)];
  [content addSubview: status];
  return content;
}

/* Pictures in the folder, in the order File Viewer lists them. */
- (NSArray *) picturesBeside: (NSString *)p
{
  NSString *dir = [p stringByDeletingLastPathComponent];
  NSArray *names = [[NSFileManager defaultManager]
                     directoryContentsAtPath: dir];
  NSMutableArray *found = [NSMutableArray array];
  NSUInteger i;

  names = [names sortedArrayUsingFunction: PVCompareNames context: NULL];
  for (i = 0; i < [names count]; i++)
    {
      NSString *n = [names objectAtIndex: i];

      if ([n hasPrefix: @"."] || ![PVImage isImagePath: n])
        continue;
      [found addObject: [dir stringByAppendingPathComponent: n]];
    }
  if (![found containsObject: p])
    [found insertObject: p atIndex: 0];
  return found;
}

- (id) initWithPath: (NSString *)p
{
  NSRect visible = [[NSScreen mainScreen] visibleFrame], frame;
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  NSSize content;

  if ((self = [super init]) == nil)
    return nil;
  path = [p copy];
  isPDF = [PVImage isPDFPath: p];
  thumbs = [[NSMutableDictionary alloc] init];
  thumbSizes = [[NSMutableDictionary alloc] init];
  thumbQueue = [[NSMutableArray alloc] init];
  pageThumbs = [[NSMutableDictionary alloc] init];
  matchIndex = -1;
  sidebarShown = [defs objectForKey: PVSidebarKey] == nil
    || [defs boolForKey: PVSidebarKey];

  if (isPDF)
    {
      BOOL locked = NO;

      pdf = RETAIN ([PVPDFDocument documentWithPath: p locked: &locked]);
      if (pdf == nil)
        {
          if (locked)
            NSRunAlertPanel (@"This PDF is locked with a password.",
                             @"Preview can't open %@: it needs a password.",
                             @"OK", nil, nil, [p lastPathComponent]);
          else
            NSRunAlertPanel (@"The PDF couldn't be opened.",
                             @"%@ is damaged, or isn't a PDF.", @"OK", nil,
                             nil, [p lastPathComponent]);
          RELEASE (self);
          return nil;
        }
      {
        NSSize page = [pdf sizeOfPage: 0];
        double z = MIN (1.0, (visible.size.height * 0.85 - PVToolbarHeight
                              - PVStatusHeight - 2 * PVMargin) / page.height);

        content = NSMakeSize (page.width * z + 2 * PVMargin + 20
                              + (sidebarShown ? PVSidebarWidth : 0),
                              visible.size.height * 0.85);
      }
    }
  else
    {
      NSBitmapImageRep *rep = [PVImage readBitmapAtPath: p];
      double z;

      if (rep == nil)
        {
          NSRunAlertPanel (@"The picture couldn't be opened.",
                           @"%@ is damaged, or is in a format Preview "
                           @"can't read.", @"OK", nil, nil,
                           [p lastPathComponent]);
          RELEASE (self);
          return nil;
        }
      bitmap = RETAIN (rep);
      folder = RETAIN ([self picturesBeside: path]);
      shown = RETAIN (folder);
      z = MIN (1.0, MIN ((visible.size.width * 0.8 - PVSidebarWidth
                          - 2 * PVMargin) / [rep pixelsWide],
                         (visible.size.height * 0.8 - PVToolbarHeight
                          - PVStatusHeight - 2 * PVMargin)
                         / [rep pixelsHigh]));
      content = NSMakeSize ([rep pixelsWide] * z + 2 * PVMargin
                            + (sidebarShown ? PVSidebarWidth : 0),
                            [rep pixelsHigh] * z + 2 * PVMargin
                            + PVToolbarHeight + PVStatusHeight);
    }
  content.width = MAX (content.width, 720);
  content.height = MAX (content.height, 480);
  frame = NSMakeRect (0, 0, content.width, content.height);

  window = [[NSWindow alloc]
             initWithContentRect: frame
                       styleMask: (NSTitledWindowMask | NSClosableWindowMask
                                   | NSMiniaturizableWindowMask
                                   | NSResizableWindowMask)
                         backing: NSBackingStoreBuffered
                           defer: NO];
  [window setReleasedWhenClosed: NO];
  [window setDelegate: (id) self];
  [window setMinSize: NSMakeSize (560, 360)];
  [window setContentView: [self makeViews: frame]];
  [window setBackgroundColor: [PVStyle backdrop]];
  [toolbar setSidebarOn: sidebarShown];
  if (isPDF)
    {
      double s = 1;

      if ([window respondsToSelector: @selector(backingScaleFactor)])
        s = [(id) window backingScaleFactor];
      else if ([window respondsToSelector: @selector(userSpaceScaleFactor)])
        s = [window userSpaceScaleFactor];
      [pdfCanvas setDeviceScale: s];
    }
  else
    [self loadImage: path];
  [sidebar reload];
  [self layoutViews];
  [self applyZoom: 1 fit: YES];
  [window center];
  [window makeFirstResponder: isPDF ? (NSView *) pdfCanvas
                                    : (NSView *) imageCanvas];
  [self updateStatus];
  [[NSNotificationCenter defaultCenter]
    addObserver: self selector: @selector(styleChanged:)
           name: PVStyleChangedNotification object: nil];
  [[NSNotificationCenter defaultCenter]
    addObserver: self selector: @selector(slideshowEnded:)
           name: PVSlideshowEndedNotification object: nil];
  return self;
}

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [NSObject cancelPreviousPerformRequestsWithTarget: self];
  [window setDelegate: nil];
  RELEASE (window);
  RELEASE (toolbar);
  RELEASE (sideScroll);
  RELEASE (sidebar);
  RELEASE (scroll);
  RELEASE (imageCanvas);
  RELEASE (pdfCanvas);
  RELEASE (status);
  RELEASE (path);
  RELEASE (folder);
  RELEASE (shown);
  RELEASE (filter);
  RELEASE (bitmap);
  RELEASE (thumbs);
  RELEASE (thumbSizes);
  RELEASE (thumbQueue);
  RELEASE (pdf);
  RELEASE (matches);
  RELEASE (query);
  RELEASE (pageThumbs);
  RELEASE (infoPanel);
  RELEASE (slideshow);
  [super dealloc];
}

- (NSString *) path
{
  return path;
}

- (NSWindow *) window
{
  return window;
}

- (void) show
{
  [window makeKeyAndOrderFront: nil];
}

/* ---- layout ---- */

- (void) layoutViews
{
  NSRect b = [[window contentView] bounds];
  CGFloat side = sidebarShown ? PVSidebarWidth : 0;
  CGFloat mainHeight = b.size.height - PVToolbarHeight - PVStatusHeight;

  [toolbar setFrame: NSMakeRect (0, 0, b.size.width, PVToolbarHeight)];
  [sideScroll setHidden: !sidebarShown];
  [sideScroll setFrame: NSMakeRect (0, PVToolbarHeight, side,
                                    b.size.height - PVToolbarHeight)];
  [scroll setFrame: NSMakeRect (side, PVToolbarHeight,
                                b.size.width - side, mainHeight)];
  [status setFrame: NSMakeRect (side, b.size.height - PVStatusHeight,
                                b.size.width - side, PVStatusHeight)];
  if (sidebarShown)
    [sidebar reload];
  if (fit)
    [self applyZoom: zoom fit: YES];
  else if (isPDF)
    [pdfCanvas fitToVisibleSize: [scroll contentSize]];
  else
    [imageCanvas fitToVisibleSize: [scroll contentSize]];
  [[window contentView] setNeedsDisplay: YES];
}

- (void) styleChanged: (NSNotification *)n
{
  [window setBackgroundColor: [PVStyle backdrop]];
  [scroll setBackgroundColor: [PVStyle backdrop]];
  [sideScroll setBackgroundColor: [PVStyle sidebar]];
  [[window contentView] setNeedsDisplay: YES];
  [toolbar setNeedsDisplay: YES];
  [sidebar setNeedsDisplay: YES];
  [status setNeedsDisplay: YES];
  [[scroll documentView] setNeedsDisplay: YES];
  if (infoPanel != nil && [infoPanel isVisible])
    [self rebuildInfo];
}

/* ---- zoom ---- */

static const double PVZooms[] = {
  0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8
};
#define PVZoomCount (sizeof (PVZooms) / sizeof (PVZooms[0]))

- (double) maxZoom
{
  /* A PDF's page is rendered whole, so not past 400%. */
  return isPDF ? 4 : 8;
}

- (double) fitZoom
{
  NSSize v = [scroll contentSize];
  NSSize s;

  if (isPDF)
    {
      s = [pdf sizeOfPage: currentPage];
      return MAX (0.1, MIN ((v.width - 2 * PVMargin) / s.width,
                            (v.height - 2 * PVMargin) / s.height));
    }
  if (bitmap == nil)
    return 1;
  s = NSMakeSize ([bitmap pixelsWide], [bitmap pixelsHigh]);
  return MAX (0.01, MIN (1.0, MIN ((v.width - 2 * PVMargin) / s.width,
                                   (v.height - 2 * PVMargin) / s.height)));
}

- (void) updateZoom
{
  if (isPDF && fit)
    [toolbar setZoomText: @"Fit"];
  else
    [toolbar setZoomText: [NSString stringWithFormat: @"%.0f%%",
                                    zoom * 100]];
}

- (void) applyZoom: (double)z fit: (BOOL)f
{
  NSClipView *clip = [scroll contentView];
  NSRect before = [clip documentVisibleRect];
  NSSize old = [[scroll documentView] frame].size;
  CGFloat fx, fy;
  int page = currentPage;

  fit = f;
  if (fit)
    z = [self fitZoom];
  z = MAX (0.01, MIN ([self maxZoom], z));
  /* Keep the middle of what's shown in the middle. */
  fx = old.width > 0 ? NSMidX (before) / old.width : 0.5;
  fy = old.height > 0 ? NSMidY (before) / old.height : 0.5;
  zoom = z;
  if (isPDF)
    {
      [pdfCanvas setZoom: z];
      [pdfCanvas fitToVisibleSize: [scroll contentSize]];
      if (fit)
        [pdfCanvas revealPage: page];
      else
        {
          NSSize now = [pdfCanvas frame].size;
          NSSize v = [scroll contentSize];
          NSPoint o = NSMakePoint (fx * now.width - v.width / 2,
                                   fy * now.height - v.height / 2);

          [clip scrollToPoint: [clip constrainScrollPoint: o]];
          [scroll reflectScrolledClipView: clip];
        }
    }
  else
    {
      NSSize now, v = [scroll contentSize];
      NSPoint o;

      [imageCanvas setZoom: z];
      [imageCanvas fitToVisibleSize: v];
      now = [imageCanvas frame].size;
      o = NSMakePoint (fx * now.width - v.width / 2,
                       fy * now.height - v.height / 2);
      [clip scrollToPoint: [clip constrainScrollPoint: o]];
      [scroll reflectScrolledClipView: clip];
    }
  [self updateZoom];
}

- (void) zoomIn: (id)sender
{
  unsigned i;

  for (i = 0; i < PVZoomCount; i++)
    if (PVZooms[i] > zoom + 0.001)
      {
        [self applyZoom: PVZooms[i] fit: NO];
        return;
      }
}

- (void) zoomOut: (id)sender
{
  int i;

  for (i = PVZoomCount - 1; i >= 0; i--)
    if (PVZooms[i] < zoom - 0.001)
      {
        [self applyZoom: PVZooms[i] fit: NO];
        return;
      }
}

- (void) zoomToFit: (id)sender
{
  [self applyZoom: zoom fit: YES];
}

- (void) actualSize: (id)sender
{
  [self applyZoom: 1 fit: NO];
}

/* ---- the sidebar ---- */

- (void) toggleSidebar: (id)sender
{
  sidebarShown = !sidebarShown;
  [[NSUserDefaults standardUserDefaults] setBool: sidebarShown
                                          forKey: PVSidebarKey];
  [toolbar setSidebarOn: sidebarShown];
  [self layoutViews];
}

- (NSUInteger) sidebarCount
{
  return isPDF ? (NSUInteger) [pdf pageCount] : [shown count];
}

- (void) queueThumbnail: (id)key
{
  if ([thumbQueue containsObject: key])
    return;
  [thumbQueue addObject: key];
  if ([thumbQueue count] == 1)
    [self performSelector: @selector(makeThumbnail) withObject: nil
               afterDelay: 0];
}

/* One thumbnail at a time, between events, so the window keeps up. */
- (void) makeThumbnail
{
  id key;

  if ([thumbQueue count] == 0)
    return;
  key = RETAIN ([thumbQueue objectAtIndex: 0]);
  [thumbQueue removeObjectAtIndex: 0];
  if (isPDF)
    {
      NSBitmapImageRep *rep = [pdf thumbnailOfPage: [key intValue]];

      if (rep != nil)
        {
          NSImage *img = AUTORELEASE ([[NSImage alloc]
                                        initWithSize:
                                          NSMakeSize ([rep pixelsWide],
                                                      [rep pixelsHigh])]);

          [img addRepresentation: rep];
          [pageThumbs setObject: img forKey: key];
        }
      [sidebar setNeedsDisplay: YES];
    }
  else
    {
      NSBitmapImageRep *rep = [key isEqual: path] && bitmap != nil
        ? bitmap : [PVImage readBitmapAtPath: key];
      NSImage *img = nil;
      NSSize size = NSMakeSize (96, 64);

      if (rep != nil)
        {
          rep = [PVImage thumbnailOf: rep side: 120];
          img = AUTORELEASE ([[NSImage alloc]
                               initWithSize:
                                 NSMakeSize ([rep pixelsWide],
                                             [rep pixelsHigh])]);
          [img addRepresentation: rep];
          size = NSMakeSize ([rep pixelsWide], [rep pixelsHigh]);
        }
      else
        img = AUTORELEASE ([[NSImage alloc] initWithSize:
                                              NSMakeSize (1, 1)]);
      [thumbs setObject: img forKey: key];
      [thumbSizes setObject: [NSValue valueWithSize: size] forKey: key];
      [sidebar reload];
    }
  RELEASE (key);
  if ([thumbQueue count] > 0)
    [self performSelector: @selector(makeThumbnail) withObject: nil
               afterDelay: 0.01];
}

- (NSImage *) sidebarThumbnail: (NSUInteger)i
{
  if (isPDF)
    {
      NSNumber *key = [NSNumber numberWithInt: (int) i];
      NSImage *img = [pageThumbs objectForKey: key];

      if (img == nil)
        [self queueThumbnail: key];
      return img;
    }
  else
    {
      NSString *p = [shown objectAtIndex: i];
      NSImage *img = [thumbs objectForKey: p];

      if (img == nil)
        [self queueThumbnail: p];
      return img;
    }
}

- (NSSize) sidebarThumbnailSize: (NSUInteger)i
{
  NSSize s;
  double f;

  if (isPDF)
    {
      s = [pdf sizeOfPage: (int) i];
      f = 84.0 / MAX (s.width, 1);
      if (s.height * f > 120)
        f = 120.0 / s.height;
      return NSMakeSize (floor (s.width * f), floor (s.height * f));
    }
  else
    {
      NSValue *v = [thumbSizes objectForKey: [shown objectAtIndex: i]];

      s = v != nil ? [v sizeValue] : NSMakeSize (96, 64);
      f = MIN (120.0 / MAX (s.width, 1), 80.0 / MAX (s.height, 1));
      f = MIN (f, 1.0);
      return NSMakeSize (MAX (8, floor (s.width * f)),
                         MAX (8, floor (s.height * f)));
    }
}

- (NSString *) sidebarLabel: (NSUInteger)i
{
  if (isPDF)
    return [NSString stringWithFormat: @"%lu", (unsigned long) i + 1];
  return [[shown objectAtIndex: i] lastPathComponent];
}

- (void) goToPage: (int)page
{
  if (page < 0 || page >= [pdf pageCount])
    return;
  currentPage = page;
  [pdfCanvas revealPage: page];
  [self updateStatus];
}

- (void) goToImage: (NSUInteger)i
{
  if (i >= [shown count])
    return;
  if ([[shown objectAtIndex: i] isEqual: path])
    return;
  if (![self canClose])
    {
      [sidebar setSelectedIndex: [shown indexOfObject: path]];
      return;
    }
  [self loadImage: [shown objectAtIndex: i]];
}

- (void) sidebarChose: (NSUInteger)i
{
  if (isPDF)
    [self goToPage: (int) i];
  else
    [self goToImage: i];
}

/* ---- a picture ---- */

- (BOOL) loadImage: (NSString *)p
{
  NSBitmapImageRep *rep = [p isEqual: path] && bitmap != nil
    ? bitmap : [PVImage readBitmapAtPath: p];
  NSDictionary *a;

  if (rep == nil)
    {
      NSBeep ();
      return NO;
    }
  ASSIGN (bitmap, rep);
  ASSIGN (path, p);
  turned = 0;
  a = [[NSFileManager defaultManager] fileAttributesAtPath: p
                                              traverseLink: YES];
  fileSize = [a fileSize];
  [imageCanvas setBitmap: bitmap];
  [window setTitle: [p lastPathComponent]];
  [window setRepresentedFilename: p];
  [sidebar setSelectedIndex: [shown indexOfObject: p] == NSNotFound
           ? -1 : (NSInteger) [shown indexOfObject: p]];
  [self applyZoom: 1 fit: YES];
  [self updateStatus];
  if (infoPanel != nil && [infoPanel isVisible])
    [self rebuildInfo];
  [[NSNotificationCenter defaultCenter]
    postNotificationName: @"PVViewerOpened" object: self];
  return YES;
}

- (void) step: (int)by
{
  NSUInteger i, n = isPDF ? (NSUInteger) [pdf pageCount] : [shown count];
  NSInteger now;

  if (n == 0)
    return;
  if (isPDF)
    {
      [self goToPage: MAX (0, MIN ((int) n - 1, currentPage + by))];
      return;
    }
  now = [shown indexOfObject: path] == NSNotFound
    ? -1 : (NSInteger) [shown indexOfObject: path];
  i = (NSUInteger) MAX (0, MIN ((NSInteger) n - 1, now + by));
  if ((NSInteger) i != now)
    [self goToImage: i];
}

- (void) goPrevious: (id)sender { [self step: -1]; }
- (void) goNext: (id)sender { [self step: 1]; }
- (void) goFirst: (id)sender { [self step: -100000]; }
- (void) goLast: (id)sender { [self step: 100000]; }

- (void) rotateBy: (int)q
{
  if (isPDF)
    {
      int page = currentPage;

      [pdf setRotation: [pdf rotation] + q];
      [pdfCanvas clearSelection];
      [pageThumbs removeAllObjects];
      [sidebar reload];
      [self applyZoom: zoom fit: fit];
      [self goToPage: page];
      return;
    }
  ASSIGN (bitmap, [PVImage bitmap: bitmap rotated: q]);
  turned = ((turned + q) % 4 + 4) % 4;
  [imageCanvas setBitmap: bitmap];
  [thumbs removeObjectForKey: path];
  [thumbSizes removeObjectForKey: path];
  [sidebar reload];
  [self applyZoom: zoom fit: fit];
  [self updateStatus];
  [window setDocumentEdited: turned != 0];
}

- (void) rotateLeft: (id)sender { [self rotateBy: -1]; }
- (void) rotateRight: (id)sender { [self rotateBy: 1]; }

/* Writes the turned picture over the file, in its own format. */
- (BOOL) saveTurned
{
  PVFormat f = [PVImage formatForPath: path];
  NSData *data = nil;

  if (f != PVFormatOther)
    data = [PVImage dataForBitmap: bitmap format: f quality: 0.92];
  /* A photo keeps when and with what it was taken. */
  if (data != nil && f == PVFormatJPEG)
    data = [PVImage JPEG: data withExifOf: path];
  if (data == nil)
    {
      NSRunAlertPanel (@"The picture couldn't be saved.",
                       @"Preview can't write %@ pictures. Use Export to save "
                       @"a copy in another format.", @"OK", nil, nil,
                       [PVImage formatName: path]);
      return NO;
    }
  if (![data writeToFile: path atomically: YES])
    {
      NSRunAlertPanel (@"The picture couldn't be saved.",
                       @"%@ couldn't be written: you may not have "
                       @"permission to change it.", @"OK", nil, nil,
                       [path lastPathComponent]);
      return NO;
    }
  turned = 0;
  fileSize = [data length];
  [window setDocumentEdited: NO];
  [self updateStatus];
  return YES;
}

- (void) saveDocument: (id)sender
{
  if (!isPDF && turned != 0)
    [self saveTurned];
}

- (BOOL) canClose
{
  int answer;

  if (isPDF || turned == 0)
    return YES;
  answer = NSRunAlertPanel ([NSString stringWithFormat:
                                        @"Do you want to keep %@ turned?",
                                      PVQuoted ([path lastPathComponent])],
                            @"Preview saves it turned. If you don't save it, "
                            @"it stays as it was.",
                            @"Save", @"Don't Save", @"Cancel");
  if (answer == NSAlertDefaultReturn)
    return [self saveTurned];
  if (answer == NSAlertAlternateReturn)
    {
      turned = 0;
      [window setDocumentEdited: NO];
      return YES;
    }
  return NO;
}

- (BOOL) windowShouldClose: (id)sender
{
  return [self canClose];
}

- (void) windowWillClose: (NSNotification *)n
{
  if ([n object] != window)
    return;
  [NSObject cancelPreviousPerformRequestsWithTarget: self];
  [infoPanel close];
  [[NSNotificationCenter defaultCenter]
    postNotificationName: PVViewerClosedNotification object: self];
}

- (void) copy: (id)sender
{
  NSPasteboard *pb = [NSPasteboard generalPasteboard];

  if (isPDF || bitmap == nil)
    return;
  [pb declareTypes: [NSArray arrayWithObject: NSTIFFPboardType] owner: nil];
  [pb setData: [bitmap TIFFRepresentation] forType: NSTIFFPboardType];
}

/* ---- the status bar and the title ---- */

- (void) updateStatus
{
  if (isPDF)
    {
      NSString *right = nil;
      int n = [pdf pageCount];

      if ([query length] > 0)
        right = [matches count] == 0
          ? [NSString stringWithFormat: @"No matches for %@",
                      PVQuoted (query)]
          : [NSString stringWithFormat: @"%lu %@ for %@",
                      (unsigned long) [matches count],
                      [matches count] == 1 ? @"match" : @"matches",
                      PVQuoted (query)];
      [status setLeft: [NSArray arrayWithObjects:
                                  [NSString stringWithFormat:
                                              @"Page %d of %d",
                                            currentPage + 1, n],
                                PVPaperDescription ([pdf unturnedSizeOfPage:
                                                           currentPage]),
                                nil]
                right: right];
      [window setTitle: [NSString stringWithFormat: @"%@ — page %d of %d",
                                  [path lastPathComponent],
                                  currentPage + 1, n]];
      [window setRepresentedFilename: path];
      [sidebar setSelectedIndex: currentPage];
      return;
    }
  {
    NSUInteger i = [shown indexOfObject: path];
    NSString *where = [[path stringByDeletingLastPathComponent]
                        lastPathComponent];
    NSString *right;

    if (i == NSNotFound)
      right = [NSString stringWithFormat: @"%lu in %@",
                        (unsigned long) [shown count], where];
    else
      right = [NSString stringWithFormat: @"%lu of %lu in %@",
                        (unsigned long) i + 1, (unsigned long) [shown count],
                        where];
    [status setLeft: [NSArray arrayWithObjects:
                                [NSString stringWithFormat:
                                            @"%ld × %ld pixels",
                                          (long) [bitmap pixelsWide],
                                          (long) [bitmap pixelsHigh]],
                              [NSString stringWithFormat: @"%@ · %@",
                                        [PVImage formatName: path],
                                        [PVStyle sizeString: fileSize]],
                              nil]
              right: right];
  }
}

- (void) scrolled: (NSNotification *)n
{
  [self pagesScrolled];
}

- (void) pagesScrolled
{
  int page;

  if (!isPDF)
    return;
  page = [pdfCanvas pageAt: [pdfCanvas visibleRect]];
  if (page != currentPage)
    {
      currentPage = page;
      [self updateStatus];
    }
}

/* ---- searching ---- */

- (void) searchFor: (NSString *)text
{
  NSSearchField *field = [toolbar searchField];

  if (![[field stringValue] isEqual: text])
    [field setStringValue: text];
  [NSObject cancelPreviousPerformRequestsWithTarget: self
                                           selector: @selector(runSearch)
                                             object: nil];
  [self performSelector: @selector(runSearch) withObject: nil
             afterDelay: 0.3];
}

- (void) showMatch: (NSInteger)i
{
  if ([matches count] == 0)
    {
      matchIndex = -1;
      [pdfCanvas setMatches: matches current: -1];
      [toolbar setMatchText: [query length] > 0 ? @"0 of 0" : nil];
      return;
    }
  matchIndex = (i % (NSInteger) [matches count] + [matches count])
    % [matches count];
  [pdfCanvas setMatches: matches current: matchIndex];
  [pdfCanvas revealMatch: [matches objectAtIndex: matchIndex]];
  [toolbar setMatchText: [NSString stringWithFormat: @"%ld of %lu",
                                   (long) matchIndex + 1,
                                   (unsigned long) [matches count]]];
}

- (void) runSearch
{
  NSString *q = [[[toolbar searchField] stringValue]
                  stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSUInteger i;

  if (!isPDF)
    {
      /* Pictures: the sidebar keeps those whose names match. */
      NSMutableArray *keep = [NSMutableArray array];

      ASSIGN (filter, q);
      for (i = 0; i < [folder count]; i++)
        {
          NSString *p = [folder objectAtIndex: i];

          if ([q length] == 0
              || [[p lastPathComponent] rangeOfString: q
                                              options: NSCaseInsensitiveSearch]
                   .location != NSNotFound)
            [keep addObject: p];
        }
      ASSIGN (shown, keep);
      [sidebar reload];
      [sidebar setSelectedIndex: [shown indexOfObject: path] == NSNotFound
               ? -1 : (NSInteger) [shown indexOfObject: path]];
      [self updateStatus];
      return;
    }
  if ([q isEqual: query])
    return;
  ASSIGN (query, q);
  ASSIGN (matches, [pdf search: q]);
  if ([q length] == 0)
    {
      DESTROY (matches);
      [pdfCanvas setMatches: nil current: -1];
      [toolbar setMatchText: nil];
      [self updateStatus];
      return;
    }
  /* The first match from the page shown on. */
  for (i = 0; i < [matches count]; i++)
    if (((PVMatch *) [matches objectAtIndex: i])->page >= currentPage)
      break;
  [self showMatch: i < [matches count] ? (NSInteger) i : 0];
  [self updateStatus];
}

- (void) findNext: (id)sender
{
  if ([matches count] > 0)
    [self showMatch: matchIndex + 1];
}

- (void) findPrevious: (id)sender
{
  if ([matches count] > 0)
    [self showMatch: matchIndex - 1];
}

- (void) find: (id)sender
{
  [window makeFirstResponder: [toolbar searchField]];
}

/* ---- keys ---- */

- (BOOL) viewKeyDown: (NSEvent *)event
{
  NSString *c = [event charactersIgnoringModifiers];
  unichar k = [c length] > 0 ? [c characterAtIndex: 0] : 0;

  if (isPDF)
    {
      switch (k)
        {
        case NSLeftArrowFunctionKey: [self step: -1]; return YES;
        case NSRightArrowFunctionKey: [self step: 1]; return YES;
        case NSHomeFunctionKey: [self goFirst: nil]; return YES;
        case NSEndFunctionKey: [self goLast: nil]; return YES;
        default: return NO;
        }
    }
  switch (k)
    {
    case NSUpArrowFunctionKey:
    case NSLeftArrowFunctionKey:
      [self step: -1];
      return YES;
    case NSDownArrowFunctionKey:
    case NSRightArrowFunctionKey:
    case ' ':
      [self step: 1];
      return YES;
    case NSHomeFunctionKey: [self goFirst: nil]; return YES;
    case NSEndFunctionKey: [self goLast: nil]; return YES;
    default: return NO;
    }
}

/* ---- the toolbar ---- */

- (void) toolClicked: (PVTool)tool
{
  switch (tool)
    {
    case PVToolSidebar: [self toggleSidebar: nil]; break;
    case PVToolZoomOut: [self zoomOut: nil]; break;
    case PVToolZoomIn: [self zoomIn: nil]; break;
    case PVToolRotate: [self rotateLeft: nil]; break;
    case PVToolInfo: [self showInfo: nil]; break;
    case PVToolSlides: [self startSlideshow: nil]; break;
    case PVToolShare: [self exportDocument: nil]; break;
    case PVToolPreviousMatch: [self findPrevious: nil]; break;
    case PVToolNextMatch: [self findNext: nil]; break;
    default: break;
    }
}

/* ---- Info ---- */

static NSTextField *
PVLabel (NSRect frame, NSString *text, NSFont *font, NSColor *color,
         NSTextAlignment alignment)
{
  NSTextField *label = AUTORELEASE ([[NSTextField alloc]
                                      initWithFrame: frame]);

  [label setStringValue: text != nil ? text : @""];
  [label setEditable: NO];
  [label setSelectable: YES];
  [label setBordered: NO];
  [label setBezeled: NO];
  [label setDrawsBackground: NO];
  [label setFont: font];
  [label setTextColor: color];
  [label setAlignment: alignment];
  return label;
}

static NSString *
PVDateString (NSDate *d)
{
  NSCalendarDate *c = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate:
                                        [d timeIntervalSinceReferenceDate]];

  return [NSString stringWithFormat: @"%@ %d %@",
                   [c descriptionWithCalendarFormat: @"%A"],
                   (int) [c dayOfMonth],
                   [c descriptionWithCalendarFormat: @"%B %Y, %H:%M"]];
}

- (NSArray *) infoRows
{
  NSMutableArray *rows = [NSMutableArray array];
  NSDictionary *a = [[NSFileManager defaultManager]
                      fileAttributesAtPath: path traverseLink: YES];
  NSString *where = [[path stringByDeletingLastPathComponent]
                      stringByAbbreviatingWithTildeInPath];

  {
    NSMutableArray *parts = [NSMutableArray array];
    NSEnumerator *e = [[where pathComponents] objectEnumerator];
    NSString *c;

    /* "Home › Pictures › Holiday" */
    while ((c = [e nextObject]) != nil)
      {
        if ([c isEqual: @"/"] || [c length] == 0)
          continue;
        [parts addObject: [c hasPrefix: @"~"] ? @"Home" : c];
      }
    where = [parts count] > 0 ? [parts componentsJoinedByString: @" › "]
      : @"/";
  }
#define ROW(k, v) do { if ((v) != nil) [rows addObject: [NSArray arrayWithObjects: (k), (v), nil]]; } while (0)
  if (isPDF)
    {
      NSSize s = [pdf unturnedSizeOfPage: currentPage];
      NSDate *made = [pdf creationDate];

      ROW (@"Pages", ([NSString stringWithFormat: @"%d", [pdf pageCount]]));
      ROW (@"Page size", PVPaperDescription (s));
      ROW (@"Title", [pdf infoForKey: @"Title"]);
      ROW (@"Author", [pdf infoForKey: @"Author"]);
      ROW (@"Producer", [pdf infoForKey: @"Producer"]);
      ROW (@"Created with", [pdf infoForKey: @"Creator"]);
      if (made != nil)
        ROW (@"Created", PVDateString (made));
      ROW (@"File size", [PVStyle sizeString: [a fileSize]]);
      ROW (@"Format", @"PDF");
    }
  else
    {
      NSDictionary *exif = [PVImage exifAtPath: path];
      NSString *camera = [exif objectForKey: @"Model"];
      double dpi = [PVImage resolution: bitmap];

      /* The model says which camera ("Pixel 9", "Canon EOS R6"); the
         maker only when there's no model. */
      if (camera == nil)
        camera = [exif objectForKey: @"Make"];
      ROW (@"Dimensions", ([NSString stringWithFormat: @"%ld × %ld pixels",
                                     (long) [bitmap pixelsWide],
                                     (long) [bitmap pixelsHigh]]));
      ROW (@"File size", [PVStyle sizeString: [a fileSize]]);
      ROW (@"Format", [PVImage formatName: path]);
      ROW (@"Colour", [PVImage colourDescription: bitmap]);
      ROW (@"Resolution", ([NSString stringWithFormat:
                                       @"%.0f pixels per inch", dpi]));
      if ([exif objectForKey: @"Taken"] != nil)
        ROW (@"Taken", PVDateString ([exif objectForKey: @"Taken"]));
      ROW (@"Camera", camera);
    }
  ROW (@"Where", where);
#undef ROW
  return rows;
}

- (void) rebuildInfo
{
  NSArray *rows = [self infoRows];
  NSView *content;
  NSFont *font = [PVStyle fontOfSize: 12.5 bold: NO];
  CGFloat width = 420, labelWidth = 110, rowHeight = 26, y, height;
  NSRect frame;
  NSUInteger i;

  height = 12 + [rows count] * rowHeight + 12;
  if (infoPanel == nil)
    {
      infoPanel = [[NSPanel alloc]
                    initWithContentRect: NSMakeRect (0, 0, width, height)
                              styleMask: NSTitledWindowMask
                                         | NSClosableWindowMask
                                backing: NSBackingStoreBuffered
                                  defer: NO];
      [infoPanel setReleasedWhenClosed: NO];
      [infoPanel setFloatingPanel: YES];
      [infoPanel setHidesOnDeactivate: YES];
      [infoPanel setBecomesKeyOnlyIfNeeded: YES];
      frame = [window frame];
      [infoPanel setFrameTopLeftPoint:
                   NSMakePoint (MIN (NSMaxX (frame) + 12,
                                     NSMaxX ([[window screen] visibleFrame])
                                     - width - 8),
                                NSMaxY (frame))];
    }
  else
    {
      frame = [infoPanel frame];
      [infoPanel setContentSize: NSMakeSize (width, height)];
      [infoPanel setFrameTopLeftPoint: NSMakePoint (NSMinX (frame),
                                                    NSMaxY (frame))];
    }
  [infoPanel setTitle: [NSString stringWithFormat: @"Info: %@",
                                 [path lastPathComponent]]];
  [infoPanel setBackgroundColor: [PVStyle window]];
  content = AUTORELEASE ([[NSView alloc]
                           initWithFrame: NSMakeRect (0, 0, width, height)]);
  y = height - 12;
  for (i = 0; i < [rows count]; i++)
    {
      NSArray *row = [rows objectAtIndex: i];
      NSBox *rule;

      y -= rowHeight;
      rule = AUTORELEASE ([[NSBox alloc] initWithFrame:
                                           NSMakeRect (16, y + rowHeight - 1,
                                                       width - 32, 1)]);
      [rule setBoxType: NSBoxCustom];
      [rule setBorderType: NSNoBorder];
      [rule setFillColor: [PVStyle line]];
      [rule setTitlePosition: NSNoTitle];
      if (i > 0)
        [content addSubview: rule];
      {
        NSTextField *key = PVLabel (NSMakeRect (16, y + 4, labelWidth, 18),
                                    [row objectAtIndex: 0], font,
                                    [PVStyle dim], NSRightTextAlignment);

        [key setSelectable: NO];
        [content addSubview: key];
      }
      [content addSubview: PVLabel (NSMakeRect (16 + labelWidth + 10, y + 4,
                                                width - labelWidth - 42, 18),
                                    [row objectAtIndex: 1], font,
                                    [PVStyle text], NSLeftTextAlignment)];
    }
  [infoPanel setContentView: content];
}

- (void) showInfo: (id)sender
{
  if (infoPanel != nil && [infoPanel isVisible])
    {
      [infoPanel orderOut: nil];
      return;
    }
  [self rebuildInfo];
  [infoPanel orderFront: nil];
}

/* ---- Export ---- */

- (void) exportDocument: (id)sender
{
  NSBitmapImageRep *rep = bitmap;
  NSString *label = nil;

  if (isPDF)
    {
      /* A page as a picture: at twice 72 dpi, so 1224 × 1584 for a
         letter page. */
      rep = [pdf renderPage: currentPage dpi: 144];
      if ([pdf pageCount] > 1)
        label = [NSString stringWithFormat: @"Page %d", currentPage + 1];
    }
  if (rep == nil)
    {
      NSBeep ();
      return;
    }
  [PVExport runForWindow: window bitmap: rep path: path pageLabel: label];
}

/* ---- the slideshow ---- */

- (void) startSlideshow: (id)sender
{
  if (slideshow != nil)
    return;
  if (isPDF)
    slideshow = [[PVSlideshow alloc] initWithPDF: pdf start: currentPage];
  else
    {
      NSUInteger i = [shown indexOfObject: path];

      slideshow = [[PVSlideshow alloc]
                    initWithPaths: shown
                            start: i == NSNotFound ? 0 : i
                          current: bitmap];
    }
  [slideshow start];
}

- (void) slideshowEnded: (NSNotification *)n
{
  if ([n object] != slideshow)
    return;
  AUTORELEASE (slideshow);
  slideshow = nil;
  [window makeKeyAndOrderFront: nil];
  [window makeFirstResponder: [scroll documentView]];
}

/* ---- menus ---- */

- (BOOL) validateMenuItem: (id<NSMenuItem>)item
{
  SEL a = [item action];

  if (a == @selector(toggleSidebar:))
    [item setTitle: sidebarShown ? @"Hide Sidebar" : @"Show Sidebar"];
  if (a == @selector(saveDocument:))
    return !isPDF && turned != 0;
  if (a == @selector(findNext:) || a == @selector(findPrevious:))
    return [matches count] > 0;
  if (a == @selector(copy:))
    return !isPDF;
  return YES;
}

@end
