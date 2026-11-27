/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PVSlideshow: the folder's pictures (or a PDF's pages) full screen, one
 * every few seconds. ← and → go back and on, Space pauses, Escape or a
 * click on nothing ends it.
 */

#ifndef _PV_SLIDESHOW_H_
#define _PV_SLIDESHOW_H_

#import <AppKit/AppKit.h>

@class PVPDFDocument;

/* Posted when it ends; the object is the slideshow. */
extern NSString *const PVSlideshowEndedNotification;

@interface PVSlideshow : NSObject
{
  NSWindow *window;
  NSView *view;
  NSArray *paths;
  PVPDFDocument *pdf;
  NSUInteger index, count;
  NSImage *image;
  NSTimer *timer;
  BOOL paused;
  NSString *hint;
  NSDate *hintUntil;
}
- (id) initWithPaths: (NSArray *)paths start: (NSUInteger)i
             current: (NSBitmapImageRep *)rep;
- (id) initWithPDF: (PVPDFDocument *)pdf start: (int)page;
- (void) start;
- (void) stop;

/* For its view. */
- (NSImage *) image;
- (NSString *) hint;
- (void) step: (int)by;
- (void) togglePause;
@end

#endif
