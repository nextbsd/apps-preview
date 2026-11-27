/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PVSlideshow.h"
#import "PVImage.h"
#import "PVPDFDocument.h"
#import "PVStyle.h"
#import <GNUstepBase/GNUstep.h>

NSString *const PVSlideshowEndedNotification = @"PVSlideshowEnded";

/* Seconds a picture stays. */
#define PVSlideSeconds 4.0

@interface PVSlideWindow : NSWindow
@end

@implementation PVSlideWindow
- (BOOL) canBecomeKeyWindow
{
  return YES;
}
/* Not main: so the theme puts no menu bar in it. */
- (BOOL) canBecomeMainWindow
{
  return NO;
}
@end

@interface PVSlideView : NSView
{
  PVSlideshow *show;
}
- (id) initWithFrame: (NSRect)frame show: (PVSlideshow *)s;
@end

@implementation PVSlideView

- (id) initWithFrame: (NSRect)frame show: (PVSlideshow *)s
{
  if ((self = [super initWithFrame: frame]) != nil)
    show = s;
  return self;
}

- (BOOL) isFlipped
{
  return YES;
}

- (BOOL) acceptsFirstResponder
{
  return YES;
}

- (void) drawRect: (NSRect)r
{
  NSRect b = [self bounds];
  NSImage *img = [show image];
  NSString *hint = [show hint];

  [[NSColor blackColor] set];
  NSRectFill (r);
  if (img != nil)
    {
      NSSize s = [img size];
      double z = MIN (b.size.width / s.width, b.size.height / s.height);
      NSRect i;

      i = NSMakeRect (floor (NSMidX (b) - s.width * z / 2),
                      floor (NSMidY (b) - s.height * z / 2),
                      floor (s.width * z), floor (s.height * z));
      [PVStyle drawImage: img inRect: i];
    }
  if (hint != nil)
    {
      NSFont *f = [PVStyle fontOfSize: 13 bold: NO];
      NSSize s = [PVStyle sizeOfText: hint font: f];
      NSRect h = NSMakeRect (floor (NSMidX (b) - s.width / 2 - 14),
                             NSMaxY (b) - 60, s.width + 28, s.height + 12);

      [[NSColor colorWithCalibratedWhite: 0.1 alpha: 0.8] set];
      [[NSBezierPath bezierPathWithRoundedRect: h xRadius: 8 yRadius: 8]
        fill];
      [PVStyle drawText: hint at: NSMakePoint (NSMinX (h) + 14,
                                               NSMinY (h) + 6)
                   font: f color: [NSColor whiteColor]];
    }
}

- (void) keyDown: (NSEvent *)event
{
  NSString *c = [event charactersIgnoringModifiers];
  unichar k = [c length] > 0 ? [c characterAtIndex: 0] : 0;

  switch (k)
    {
    case 27:
    case 'q':
      [show stop];
      break;
    case NSLeftArrowFunctionKey:
    case NSUpArrowFunctionKey:
      [show step: -1];
      break;
    case NSRightArrowFunctionKey:
    case NSDownArrowFunctionKey:
    case '\r':
      [show step: 1];
      break;
    case ' ':
      [show togglePause];
      break;
    default:
      [super keyDown: event];
    }
}

- (void) mouseDown: (NSEvent *)event
{
  [show step: 1];
}

- (void) rightMouseDown: (NSEvent *)event
{
  [show stop];
}

@end

@implementation PVSlideshow

- (id) initWithPaths: (NSArray *)p start: (NSUInteger)i
             current: (NSBitmapImageRep *)rep
{
  if ((self = [super init]) != nil)
    {
      paths = RETAIN (p);
      count = [p count];
      index = i < count ? i : 0;
      if (rep != nil)
        {
          image = [[NSImage alloc] initWithSize:
                                     NSMakeSize ([rep pixelsWide],
                                                 [rep pixelsHigh])];
          [image addRepresentation: rep];
        }
    }
  return self;
}

- (id) initWithPDF: (PVPDFDocument *)d start: (int)page
{
  if ((self = [super init]) != nil)
    {
      pdf = RETAIN (d);
      count = [d pageCount];
      index = page >= 0 && (NSUInteger) page < count ? page : 0;
    }
  return self;
}

- (void) dealloc
{
  [timer invalidate];
  RELEASE (window);
  RELEASE (view);
  RELEASE (paths);
  RELEASE (pdf);
  RELEASE (image);
  RELEASE (hint);
  RELEASE (hintUntil);
  [super dealloc];
}

- (NSImage *) image
{
  return image;
}

- (NSString *) hint
{
  if (hint != nil && [hintUntil timeIntervalSinceNow] < 0)
    DESTROY (hint);
  return hint;
}

- (void) say: (NSString *)s
{
  ASSIGN (hint, s);
  ASSIGN (hintUntil, [NSDate dateWithTimeIntervalSinceNow: 2.5]);
  [view setNeedsDisplay: YES];
  [view performSelector: @selector(display) withObject: nil
             afterDelay: 2.6];
}

- (void) load
{
  NSBitmapImageRep *rep = nil;

  if (pdf != nil)
    {
      NSRect screen = [window frame];
      NSSize s = [pdf sizeOfPage: index];
      double z = MIN (screen.size.width / s.width,
                      screen.size.height / s.height);

      rep = [pdf renderPage: index dpi: 72.0 * z];
    }
  else
    rep = [PVImage readBitmapAtPath: [paths objectAtIndex: index]];
  DESTROY (image);
  if (rep != nil)
    {
      image = [[NSImage alloc] initWithSize:
                                 NSMakeSize ([rep pixelsWide],
                                             [rep pixelsHigh])];
      [image addRepresentation: rep];
    }
  [view setNeedsDisplay: YES];
}

- (void) restartTimer
{
  [timer invalidate];
  timer = nil;
  if (paused || count < 2)
    return;
  timer = [NSTimer scheduledTimerWithTimeInterval: PVSlideSeconds
                                           target: self
                                         selector: @selector(tick:)
                                         userInfo: nil
                                          repeats: YES];
}

- (void) tick: (NSTimer *)t
{
  /* Round again from the start. */
  index = (index + 1) % count;
  [self load];
}

- (void) step: (int)by
{
  if (count == 0)
    return;
  index = (NSUInteger) (((NSInteger) index + by + (NSInteger) count)
                        % (NSInteger) count);
  [self load];
  [self restartTimer];
}

- (void) togglePause
{
  paused = !paused;
  [self say: paused ? @"Paused: Space plays on" : @"Playing"];
  [self restartTimer];
}

- (void) start
{
  NSScreen *screen = [NSScreen mainScreen];
  NSRect frame = [screen frame];

  window = [[PVSlideWindow alloc] initWithContentRect: frame
                                            styleMask: NSBorderlessWindowMask
                                              backing: NSBackingStoreBuffered
                                                defer: NO];
  [window setReleasedWhenClosed: NO];
  [window setBackgroundColor: [NSColor blackColor]];
  [window setLevel: NSScreenSaverWindowLevel];
  view = [[PVSlideView alloc] initWithFrame:
                                NSMakeRect (0, 0, frame.size.width,
                                            frame.size.height)
                                       show: self];
  [window setContentView: view];
  [window makeKeyAndOrderFront: nil];
  [window makeFirstResponder: view];
  if (pdf != nil || image == nil)
    [self load];
  [self say: @"← → to go back and on · Space pauses · Esc ends"];
  [self restartTimer];
}

- (void) stop
{
  [timer invalidate];
  timer = nil;
  [NSObject cancelPreviousPerformRequestsWithTarget: view];
  [window orderOut: nil];
  [[NSNotificationCenter defaultCenter]
    postNotificationName: PVSlideshowEndedNotification object: self];
}

@end
