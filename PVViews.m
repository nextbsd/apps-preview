/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PVViews.h"
#import "PVStyle.h"
#import "PVPDFDocument.h"

static void
PVRound (NSRect r, CGFloat radius, NSColor *color)
{
  [color set];
  [[NSBezierPath bezierPathWithRoundedRect: r xRadius: radius
                                   yRadius: radius] fill];
}

/* A soft shadow under a picture or a page, then the rectangle filled
   with what is behind it, so a transparent picture shows that. */
static void
PVShadow (NSRect r, NSColor *behind)
{
  int i;

  for (i = 1; i <= 4; i++)
    PVRound (NSOffsetRect (NSInsetRect (r, -i, -i), 0, i), i + 1,
             [NSColor colorWithCalibratedWhite: 0 alpha: 0.07]);
  [behind set];
  NSRectFill (r);
}

/* ======================================================================== */

#define PVToolbarHeight 40
#define PVButtonWidth 30
#define PVButtonHeight 26
#define PVSearchWidth 210

@implementation PVToolbar

- (id) initWithFrame: (NSRect)frame owner: (id<PVViewsOwner>)o
{
  if ((self = [super initWithFrame: frame]) != nil)
    {
      owner = o;
      pressed = -1;
      zoomText = @"100%";
      search = [[NSSearchField alloc]
                 initWithFrame: NSMakeRect (frame.size.width - 10
                                            - PVSearchWidth, 7,
                                            PVSearchWidth, PVButtonHeight)];
      [search setAutoresizingMask: NSViewMinXMargin];
      [[search cell] setPlaceholderString: @"Search"];
      [search setTarget: self];
      [search setAction: @selector(searchAction:)];
      [search setDelegate: (id) self];
      [self addSubview: search];
      [self setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
    }
  return self;
}

- (void) dealloc
{
  RELEASE (search);
  RELEASE (zoomText);
  RELEASE (matchText);
  [super dealloc];
}

- (BOOL) isFlipped
{
  return YES;
}

- (BOOL) acceptsFirstMouse: (NSEvent *)event
{
  return YES;
}

- (NSSearchField *) searchField
{
  return search;
}

- (void) searchAction: (id)sender
{
  [owner searchFor: [search stringValue]];
}

- (void) controlTextDidChange: (NSNotification *)n
{
  [owner searchFor: [search stringValue]];
}

- (void) setZoomText: (NSString *)s
{
  ASSIGN (zoomText, s);
  [self setNeedsDisplay: YES];
}

- (void) setMatchText: (NSString *)s
{
  ASSIGN (matchText, s);
  [self setNeedsDisplay: YES];
}

- (void) setSidebarOn: (BOOL)flag
{
  sidebarOn = flag;
  [self setNeedsDisplay: YES];
}

- (NSFont *) font
{
  return [PVStyle fontOfSize: 12 bold: NO];
}

- (void) layoutRects
{
  CGFloat x = 10, y = (PVToolbarHeight - PVButtonHeight) / 2;
  int i;

#define PVNEXT(tool) do { rects[tool] = NSMakeRect (x, y, PVButtonWidth, \
                                                   PVButtonHeight); \
                          x += PVButtonWidth + 4; } while (0)
  PVNEXT (PVToolSidebar);
  x += 9;
  PVNEXT (PVToolZoomOut);
  x += 44;
  PVNEXT (PVToolZoomIn);
  x += 9;
  PVNEXT (PVToolRotate);
  PVNEXT (PVToolInfo);
  PVNEXT (PVToolSlides);
  PVNEXT (PVToolShare);
#undef PVNEXT
  x = NSMinX ([search frame]) - 6 - 2 * PVButtonWidth;
  rects[PVToolPreviousMatch] = NSMakeRect (x, y, PVButtonWidth,
                                           PVButtonHeight);
  rects[PVToolNextMatch] = NSMakeRect (x + PVButtonWidth, y, PVButtonWidth,
                                       PVButtonHeight);
  if (matchText == nil)
    for (i = PVToolPreviousMatch; i <= PVToolNextMatch; i++)
      rects[i] = NSZeroRect;
}

- (void) drawRect: (NSRect)r
{
  static NSString *glyphs[PVToolCount];
  NSRect b = [self bounds];
  NSFont *font = [self font];
  NSSize s;
  int i;

  if (glyphs[0] == nil)
    {
      glyphs[PVToolSidebar] = PVGlyphSidebar;
      glyphs[PVToolZoomOut] = PVGlyphZoomOut;
      glyphs[PVToolZoomIn] = PVGlyphZoomIn;
      glyphs[PVToolRotate] = PVGlyphRotate;
      glyphs[PVToolInfo] = PVGlyphInfo;
      glyphs[PVToolSlides] = PVGlyphSlides;
      glyphs[PVToolShare] = PVGlyphShare;
      glyphs[PVToolPreviousMatch] = PVGlyphUp;
      glyphs[PVToolNextMatch] = PVGlyphDown;
    }
  [self layoutRects];
  [[PVStyle bar] set];
  NSRectFill (b);
  [[PVStyle line] set];
  NSRectFillUsingOperation (NSMakeRect (0, NSMaxY (b) - 1, b.size.width, 1),
                            NSCompositeSourceOver);

  /* separators */
  NSRectFillUsingOperation (NSMakeRect (NSMaxX (rects[PVToolSidebar]) + 4,
                                        11, 1, 18), NSCompositeSourceOver);
  NSRectFillUsingOperation (NSMakeRect (NSMaxX (rects[PVToolZoomIn]) + 4,
                                        11, 1, 18), NSCompositeSourceOver);

  for (i = 0; i < PVToolCount; i++)
    {
      BOOL on = (i == PVToolSidebar && sidebarOn);
      NSRect g;

      if (NSIsEmptyRect (rects[i]))
        continue;
      if (on || i == pressed)
        PVRound (rects[i], 6, [PVStyle selection]);
      g = NSMakeRect (NSMidX (rects[i]) - 8.5, NSMidY (rects[i]) - 8.5,
                      17, 17);
      [PVStyle strokeGlyph: glyphs[i] inRect: g
                     color: on ? [PVStyle accent] : [PVStyle text]
                     width: 1.7];
    }

  s = [PVStyle sizeOfText: zoomText font: font];
  [PVStyle drawText: zoomText
                 at: NSMakePoint (NSMaxX (rects[PVToolZoomOut]) + 4
                                  + (44 - s.width) / 2,
                                  (PVToolbarHeight - s.height) / 2)
               font: font color: [PVStyle dim]];

  if (matchText != nil)
    {
      s = [PVStyle sizeOfText: matchText font: font];
      [PVStyle drawText: matchText
                     at: NSMakePoint (NSMinX (rects[PVToolPreviousMatch])
                                      - 2 - s.width,
                                      (PVToolbarHeight - s.height) / 2)
                   font: font color: [PVStyle dim]];
    }
}

- (int) toolAt: (NSPoint)p
{
  int i;

  [self layoutRects];
  for (i = 0; i < PVToolCount; i++)
    if (NSPointInRect (p, rects[i]))
      return i;
  return -1;
}

- (void) mouseDown: (NSEvent *)event
{
  NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];
  int tool = [self toolAt: p];
  NSEvent *e;

  if (tool < 0)
    return;
  pressed = tool;
  [self setNeedsDisplay: YES];
  for (;;)
    {
      e = [[self window] nextEventMatchingMask: NSLeftMouseUpMask
                                                | NSLeftMouseDraggedMask];
      p = [self convertPoint: [e locationInWindow] fromView: nil];
      pressed = NSPointInRect (p, rects[tool]) ? tool : -1;
      [self setNeedsDisplay: YES];
      if ([e type] == NSLeftMouseUp)
        break;
    }
  pressed = -1;
  [self setNeedsDisplay: YES];
  if (NSPointInRect (p, rects[tool]))
    [owner toolClicked: tool];
}

@end

/* ======================================================================== */

#define PVSidebarPad 8
#define PVSidebarLabel 14

@implementation PVSidebar

- (id) initWithFrame: (NSRect)frame owner: (id<PVViewsOwner>)o
{
  if ((self = [super initWithFrame: frame]) != nil)
    {
      owner = o;
      selected = -1;
      tops = [[NSMutableArray alloc] init];
    }
  return self;
}

- (void) dealloc
{
  RELEASE (tops);
  [super dealloc];
}

- (BOOL) isFlipped
{
  return YES;
}

- (BOOL) isOpaque
{
  return YES;
}

- (void) reload
{
  NSUInteger i, n = [owner sidebarCount];
  CGFloat y = PVSidebarPad;
  NSScrollView *scroll = [self enclosingScrollView];
  NSSize visible = scroll != nil ? [scroll contentSize] : [self frame].size;

  [tops removeAllObjects];
  for (i = 0; i < n; i++)
    {
      [tops addObject: [NSNumber numberWithDouble: y]];
      y += PVSidebarPad + [owner sidebarThumbnailSize: i].height + 5
        + PVSidebarLabel + PVSidebarPad + 2;
    }
  height = y + PVSidebarPad;
  [self setFrameSize: NSMakeSize (visible.width, MAX (height,
                                                      visible.height))];
  [self setNeedsDisplay: YES];
}

- (NSRect) rowRect: (NSUInteger)i
{
  CGFloat top = [[tops objectAtIndex: i] doubleValue];
  CGFloat h = PVSidebarPad + [owner sidebarThumbnailSize: i].height + 5
    + PVSidebarLabel + PVSidebarPad;

  return NSMakeRect (PVSidebarPad, top, [self bounds].size.width
                     - 2 * PVSidebarPad, h);
}

- (void) drawRect: (NSRect)r
{
  NSUInteger i, n = [tops count];
  NSFont *font = [PVStyle fontOfSize: 11 bold: NO];
  NSRect b = [self bounds];

  [[PVStyle sidebar] set];
  NSRectFill (r);
  [[PVStyle line] set];
  NSRectFillUsingOperation (NSMakeRect (NSMaxX (b) - 1, NSMinY (r), 1,
                                        r.size.height),
                            NSCompositeSourceOver);
  for (i = 0; i < n; i++)
    {
      NSRect row = [self rowRect: i], t;
      NSSize ts = [owner sidebarThumbnailSize: i];
      NSImage *thumb;
      NSString *label;
      NSSize ls;
      BOOL on = ((NSInteger) i == selected);

      if (!NSIntersectsRect (row, r))
        continue;
      if (on)
        PVRound (row, 8, [PVStyle selection]);
      t = NSMakeRect (floor (NSMidX (row) - ts.width / 2),
                      NSMinY (row) + PVSidebarPad, ts.width, ts.height);
      PVShadow (t, [PVStyle sidebar]);
      thumb = [owner sidebarThumbnail: i];
      if (thumb != nil)
        [PVStyle drawImage: thumb inRect: t];
      else
        PVRound (t, 2, [PVStyle line]);
      label = [PVStyle text: [owner sidebarLabel: i]
                    fitting: row.size.width - 12 font: font];
      ls = [PVStyle sizeOfText: label font: font];
      [PVStyle drawText: label
                     at: NSMakePoint (floor (NSMidX (row) - ls.width / 2),
                                      NSMaxY (t) + 5)
                   font: font
                  color: on ? [PVStyle text] : [PVStyle dim]];
    }
}

- (NSInteger) selectedIndex
{
  return selected;
}

- (void) setSelectedIndex: (NSInteger)index
{
  if (index == selected)
    return;
  selected = index;
  if (index >= 0 && index < (NSInteger) [tops count])
    [self scrollRectToVisible: NSInsetRect ([self rowRect: index], 0, -4)];
  [self setNeedsDisplay: YES];
}

- (void) mouseDown: (NSEvent *)event
{
  NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];
  NSUInteger i;

  for (i = 0; i < [tops count]; i++)
    if (NSPointInRect (p, [self rowRect: i]))
      {
        [self setSelectedIndex: i];
        [owner sidebarChose: i];
        return;
      }
}

@end

/* ======================================================================== */

@implementation PVStatusBar

- (void) dealloc
{
  RELEASE (left);
  RELEASE (right);
  [super dealloc];
}

- (BOOL) isFlipped
{
  return YES;
}

- (void) setLeft: (NSArray *)strings right: (NSString *)string
{
  ASSIGN (left, strings);
  ASSIGN (right, string);
  [self setNeedsDisplay: YES];
}

- (void) drawRect: (NSRect)r
{
  NSRect b = [self bounds];
  NSFont *font = [PVStyle fontOfSize: 11.5 bold: NO];
  CGFloat x = 14, y;
  NSUInteger i;
  NSSize s;

  [[PVStyle bar] set];
  NSRectFill (b);
  [[PVStyle line] set];
  NSRectFillUsingOperation (NSMakeRect (0, 0, b.size.width, 1),
                            NSCompositeSourceOver);
  s = [PVStyle sizeOfText: @"Hg" font: font];
  y = floor ((b.size.height - s.height) / 2) + 1;
  for (i = 0; i < [left count]; i++)
    {
      NSString *t = [left objectAtIndex: i];

      [PVStyle drawText: t at: NSMakePoint (x, y) font: font
                  color: [PVStyle dim]];
      x += [PVStyle sizeOfText: t font: font].width + 14;
    }
  if (right != nil)
    {
      s = [PVStyle sizeOfText: right font: font];
      if (NSMaxX (b) - 14 - s.width > x)
        [PVStyle drawText: right
                       at: NSMakePoint (NSMaxX (b) - 14 - s.width, y)
                     font: font color: [PVStyle dim]];
    }
}

@end

/* ======================================================================== */

/* Room around a picture or the pages. */
#define PVMargin 22

/* Scrolls the clip view by the mouse's drag, as a hand. */
static void
PVDragScroll (NSView *view, NSEvent *event)
{
  NSClipView *clip = (NSClipView *) [view superview];
  NSPoint last = [event locationInWindow];
  NSEvent *e;

  if (![clip isKindOfClass: [NSClipView class]])
    return;
  for (;;)
    {
      NSPoint now, origin;

      e = [[view window] nextEventMatchingMask: NSLeftMouseUpMask
                                                | NSLeftMouseDraggedMask];
      if ([e type] == NSLeftMouseUp)
        break;
      now = [e locationInWindow];
      origin = [clip bounds].origin;
      origin.x -= now.x - last.x;
      origin.y += ([view isFlipped] ? 1 : -1) * (now.y - last.y);
      last = now;
      [clip scrollToPoint: [clip constrainScrollPoint: origin]];
      [[clip superview] reflectScrolledClipView: clip];
    }
}

@implementation PVImageCanvas

- (id) initWithFrame: (NSRect)frame owner: (id<PVViewsOwner>)o
{
  if ((self = [super initWithFrame: frame]) != nil)
    {
      owner = o;
      zoom = 1;
    }
  return self;
}

- (void) dealloc
{
  RELEASE (image);
  [super dealloc];
}

- (BOOL) isFlipped
{
  return YES;
}

- (BOOL) isOpaque
{
  return YES;
}

- (BOOL) acceptsFirstResponder
{
  return YES;
}

- (void) setBitmap: (NSBitmapImageRep *)rep
{
  NSImage *i = nil;

  if (rep != nil)
    {
      pixels = NSMakeSize ([rep pixelsWide], [rep pixelsHigh]);
      i = AUTORELEASE ([[NSImage alloc] initWithSize: pixels]);
      [i addRepresentation: rep];
    }
  ASSIGN (image, i);
  [self setNeedsDisplay: YES];
}

- (void) setZoom: (double)z
{
  zoom = z;
}

- (void) fitToVisibleSize: (NSSize)visible
{
  NSSize s = NSMakeSize (ceil (pixels.width * zoom) + 2 * PVMargin,
                         ceil (pixels.height * zoom) + 2 * PVMargin);

  [self setFrameSize: NSMakeSize (MAX (s.width, visible.width),
                                  MAX (s.height, visible.height))];
  [self setNeedsDisplay: YES];
}

- (NSRect) imageRect
{
  NSRect b = [self bounds];
  NSSize s = NSMakeSize (floor (pixels.width * zoom),
                         floor (pixels.height * zoom));

  return NSMakeRect (floor (NSMidX (b) - s.width / 2),
                     floor (NSMidY (b) - s.height / 2), s.width, s.height);
}

- (void) drawRect: (NSRect)r
{
  NSRect i = [self imageRect];

  [[PVStyle backdrop] set];
  NSRectFill (r);
  if (image == nil)
    return;
  PVShadow (i, [PVStyle backdrop]);
  [PVStyle drawImage: image inRect: i];
}

- (void) keyDown: (NSEvent *)event
{
  if (![owner viewKeyDown: event])
    [super keyDown: event];
}

- (void) mouseDown: (NSEvent *)event
{
  [[self window] makeFirstResponder: self];
  PVDragScroll (self, event);
}

- (BOOL) performKeyEquivalent: (NSEvent *)event
{
  if (([event modifierFlags] & NSCommandKeyMask)
      && [[event charactersIgnoringModifiers] isEqual: @"="])
    {
      [owner toolClicked: PVToolZoomIn];
      return YES;
    }
  return [super performKeyEquivalent: event];
}

@end

/* ======================================================================== */

#define PVPageGap 18

@implementation PVPDFCanvas

- (id) initWithFrame: (NSRect)frame owner: (id<PVViewsOwner>)o
{
  if ((self = [super initWithFrame: frame]) != nil)
    {
      owner = o;
      zoom = 1;
      scale = 1;
      selPage = -1;
      currentMatch = -1;
    }
  return self;
}

- (void) dealloc
{
  RELEASE (doc);
  RELEASE (matches);
  [super dealloc];
}

- (BOOL) isFlipped
{
  return YES;
}

- (BOOL) isOpaque
{
  return YES;
}

- (BOOL) acceptsFirstResponder
{
  return YES;
}

- (void) setDocument: (PVPDFDocument *)d
{
  ASSIGN (doc, d);
  selPage = -1;
}

- (double) zoom
{
  return zoom;
}

- (void) setZoom: (double)z
{
  zoom = z;
}

- (void) setDeviceScale: (double)s
{
  scale = s > 0 ? s : 1;
}

- (CGFloat) widestPage
{
  int i, n = [doc pageCount];
  CGFloat w = 0;

  for (i = 0; i < n; i++)
    w = MAX (w, [doc sizeOfPage: i].width);
  return w;
}

- (void) fitToVisibleSize: (NSSize)visible
{
  int i, n = [doc pageCount];
  CGFloat h = PVMargin;

  for (i = 0; i < n; i++)
    h += floor ([doc sizeOfPage: i].height * zoom) + PVPageGap;
  h += PVMargin - PVPageGap;
  [self setFrameSize: NSMakeSize (MAX (visible.width,
                                       ceil ([self widestPage] * zoom)
                                       + 2 * PVMargin),
                                  MAX (visible.height, h))];
  [[self window] invalidateCursorRectsForView: self];
  [self setNeedsDisplay: YES];
}

- (void) layout
{
  NSScrollView *scroll = [self enclosingScrollView];

  if (scroll != nil)
    [self fitToVisibleSize: [scroll contentSize]];
}

- (NSRect) rectOfPage: (int)page
{
  int i;
  CGFloat y = PVMargin;
  NSSize s;
  NSRect b = [self bounds];

  for (i = 0; i < page; i++)
    y += floor ([doc sizeOfPage: i].height * zoom) + PVPageGap;
  s = [doc sizeOfPage: page];
  s = NSMakeSize (floor (s.width * zoom), floor (s.height * zoom));
  return NSMakeRect (floor (NSMidX (b) - s.width / 2), y, s.width, s.height);
}

- (int) pageAt: (NSRect)visible
{
  int i, n = [doc pageCount], best = 0;
  CGFloat most = -1;

  /* The page that fills most of the window. */
  for (i = 0; i < n; i++)
    {
      NSRect r = NSIntersectionRect ([self rectOfPage: i], visible);
      CGFloat area = r.size.height;

      if ([self rectOfPage: i].origin.y > NSMaxY (visible))
        break;
      if (area > most)
        {
          most = area;
          best = i;
        }
    }
  return best;
}

/* Turned page points to the view, and back. */
- (NSRect) viewRect: (NSRect)r onPage: (int)page
{
  NSRect p = [self rectOfPage: page];

  r = [doc turnRect: r onPage: page];
  return NSMakeRect (NSMinX (p) + r.origin.x * zoom,
                     NSMinY (p) + r.origin.y * zoom,
                     r.size.width * zoom, r.size.height * zoom);
}

- (NSPoint) pagePoint: (NSPoint)v onPage: (int)page
{
  NSRect p = [self rectOfPage: page];

  return [doc unturnPoint: NSMakePoint ((v.x - NSMinX (p)) / zoom,
                                        (v.y - NSMinY (p)) / zoom)
                   onPage: page];
}

- (void) drawRect: (NSRect)r
{
  int i, n = [doc pageCount];
  NSUInteger m;
  double dpi = 72.0 * zoom * scale;

  [[PVStyle backdrop] set];
  NSRectFill (r);
  for (i = 0; i < n; i++)
    {
      NSRect p = [self rectOfPage: i];
      NSBitmapImageRep *rep;
      NSImage *img;

      if (NSMinY (p) > NSMaxY (r))
        break;
      if (!NSIntersectsRect (NSInsetRect (p, -6, -6), r))
        continue;
      PVShadow (p, [NSColor whiteColor]);
      rep = [doc renderPage: i dpi: dpi];
      if (rep != nil)
        {
          img = AUTORELEASE ([[NSImage alloc]
                               initWithSize: NSMakeSize ([rep pixelsWide],
                                                         [rep pixelsHigh])]);
          [img addRepresentation: rep];
          [PVStyle drawImage: img inRect: p];
        }

      /* search matches: the current one stronger */
      for (m = 0; m < [matches count]; m++)
        {
          PVMatch *match = [matches objectAtIndex: m];

          if (match->page != i)
            continue;
          [[PVStyle rgb: (NSInteger) m == currentMatch ? 0xff9f1a : 0xffd84d
                  alpha: (NSInteger) m == currentMatch ? 0.55 : 0.45] set];
          NSRectFillUsingOperation (NSInsetRect ([self viewRect: match->rect
                                                         onPage: i], -1, -1),
                                    NSCompositeSourceOver);
        }

      /* the selection */
      if (selPage == i && selFrom >= 0)
        {
          PVPageText *t = [doc textOfPage: i];
          int a = MIN (selFrom, selTo), b = MAX (selFrom, selTo), g;

          [[PVStyle rgb: 0x2f7fff alpha: 0.35] set];
          for (g = a; g <= b && g < t->text.count; g++)
            {
              PVRect gr = t->text.rects[g];
              NSRect vr = [self viewRect: NSMakeRect (gr.x, gr.y, gr.w, gr.h)
                                  onPage: i];

              /* Through the space after the glyph, to the next. */
              if (g < b && !(t->text.flags[g] & PVGlyphLine))
                {
                  PVRect nr = t->text.rects[g + 1];
                  NSRect nv = [self viewRect: NSMakeRect (nr.x, nr.y, nr.w,
                                                          nr.h)
                                      onPage: i];

                  if (NSMinX (nv) > NSMaxX (vr))
                    vr.size.width = NSMinX (nv) - NSMinX (vr);
                }
              NSRectFillUsingOperation (vr, NSCompositeSourceOver);
            }
        }
    }
}

- (void) resetCursorRects
{
  int i, n = [doc pageCount];
  NSRect visible = [self visibleRect];

  for (i = 0; i < n; i++)
    {
      NSRect p = NSIntersectionRect ([self rectOfPage: i], visible);

      if (!NSIsEmptyRect (p))
        [self addCursorRect: p cursor: [NSCursor IBeamCursor]];
    }
}

- (void) revealMatch: (PVMatch *)m
{
  NSRect r = [self viewRect: m->rect onPage: m->page];

  [self scrollRectToVisible: NSInsetRect (r, -80, -80)];
}

- (void) revealPage: (int)page
{
  NSRect r = [self rectOfPage: page];
  NSRect v = [self visibleRect];
  NSClipView *clip = (NSClipView *) [self superview];
  NSPoint o = NSMakePoint (v.origin.x, NSMinY (r) - 10);

  [clip scrollToPoint: [clip constrainScrollPoint: o]];
  [[clip superview] reflectScrolledClipView: clip];
}

- (BOOL) performKeyEquivalent: (NSEvent *)event
{
  /* Command-= zooms in as Command-+ does. */
  if (([event modifierFlags] & NSCommandKeyMask)
      && [[event charactersIgnoringModifiers] isEqual: @"="])
    {
      [owner toolClicked: PVToolZoomIn];
      return YES;
    }
  return [super performKeyEquivalent: event];
}

- (void) setMatches: (NSArray *)m current: (NSInteger)i
{
  ASSIGN (matches, m);
  currentMatch = i;
  [self setNeedsDisplay: YES];
}

- (void) clearSelection
{
  if (selPage >= 0)
    [self setNeedsDisplay: YES];
  selPage = -1;
}

- (NSString *) selectedText
{
  if (selPage < 0 || selFrom < 0)
    return nil;
  return [[doc textOfPage: selPage] stringFrom: selFrom to: selTo];
}

- (int) pageAtPoint: (NSPoint)v
{
  int i, n = [doc pageCount];

  for (i = 0; i < n; i++)
    if (NSPointInRect (v, NSInsetRect ([self rectOfPage: i], 0, -PVPageGap / 2)))
      return i;
  return -1;
}

- (void) mouseDown: (NSEvent *)event
{
  NSPoint v = [self convertPoint: [event locationInWindow] fromView: nil];
  int page = [self pageAtPoint: v];
  PVPageText *t;
  NSEvent *e;

  [[self window] makeFirstResponder: self];
  [self clearSelection];
  if (page < 0)
    {
      PVDragScroll (self, event);
      return;
    }
  t = [doc textOfPage: page];
  if (t->text.count == 0)
    {
      PVDragScroll (self, event);
      return;
    }
  selPage = page;
  selFrom = selTo = -1;
  {
    int g = [t glyphNearest: [self pagePoint: v onPage: page]];
    int anchor = g;
    BOOL moved = NO;

    for (;;)
      {
        e = [[self window] nextEventMatchingMask: NSLeftMouseUpMask
                                                  | NSLeftMouseDraggedMask];
        if ([e type] == NSLeftMouseUp)
          break;
        [self autoscroll: e];
        v = [self convertPoint: [e locationInWindow] fromView: nil];
        g = [t glyphNearest: [self pagePoint: v onPage: page]];
        moved = YES;
        selFrom = anchor;
        selTo = g;
        [self setNeedsDisplay: YES];
      }
    if (!moved)
      selPage = -1;
  }
  [self setNeedsDisplay: YES];
}

- (void) copy: (id)sender
{
  NSString *s = [self selectedText];
  NSPasteboard *pb = [NSPasteboard generalPasteboard];

  if (s == nil)
    return;
  [pb declareTypes: [NSArray arrayWithObject: NSStringPboardType]
             owner: nil];
  [pb setString: s forType: NSStringPboardType];
}

- (void) selectAll: (id)sender
{
  NSRect visible = [self visibleRect];
  int page = [self pageAt: visible];
  PVPageText *t = [doc textOfPage: page];

  if (t->text.count == 0)
    return;
  selPage = page;
  selFrom = 0;
  selTo = t->text.count - 1;
  [self setNeedsDisplay: YES];
}

- (void) searchForSelection: (id)sender
{
  NSString *s = [self selectedText];

  if (s != nil)
    [owner searchFor: s];
}

- (BOOL) validateMenuItem: (id<NSMenuItem>)item
{
  if ([item action] == @selector(copy:)
      || [item action] == @selector(searchForSelection:))
    return [self selectedText] != nil;
  return YES;
}

- (NSMenu *) menuForEvent: (NSEvent *)event
{
  NSString *s = [self selectedText];
  NSMenu *menu;
  id<NSMenuItem> item;

  if (s == nil)
    return nil;
  menu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @""]);
  item = [menu addItemWithTitle: @"Copy" action: @selector(copy:)
                  keyEquivalent: @"c"];
  [item setTarget: self];
  s = [[s componentsSeparatedByCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]]
        componentsJoinedByString: @" "];
  if ([s length] > 24)
    s = [[s substringToIndex: 23] stringByAppendingString: @"…"];
  item = [menu addItemWithTitle: [NSString stringWithFormat:
                                             @"Search for “%@”", s]
                         action: @selector(searchForSelection:)
                  keyEquivalent: @""];
  [item setTarget: self];
  return menu;
}

- (void) keyDown: (NSEvent *)event
{
  if (![owner viewKeyDown: event])
    [self interpretKeyEvents: [NSArray arrayWithObject: event]];
}

/* Arrows and paging, from interpretKeyEvents. */
- (void) scrollBy: (CGFloat)dy
{
  NSClipView *clip = (NSClipView *) [self superview];
  NSPoint o = [clip bounds].origin;

  o.y += dy;
  [clip scrollToPoint: [clip constrainScrollPoint: o]];
  [[clip superview] reflectScrolledClipView: clip];
}

- (void) moveUp: (id)sender { [self scrollBy: -40]; }
- (void) moveDown: (id)sender { [self scrollBy: 40]; }
- (void) scrollPageUp: (id)sender { [self scrollBy: -[self visibleRect].size.height + 40]; }
- (void) scrollPageDown: (id)sender { [self scrollBy: [self visibleRect].size.height - 40]; }
- (void) pageUp: (id)sender { [self scrollPageUp: sender]; }
- (void) pageDown: (id)sender { [self scrollPageDown: sender]; }
- (void) insertText: (id)s { }
- (void) doCommandBySelector: (SEL)sel
{
  if ([self respondsToSelector: sel])
    [self performSelector: sel withObject: nil];
}

@end
