/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PVViewer: a Preview window, showing a picture (and the other pictures in
 * its folder down the sidebar) or a PDF (its pages down the sidebar).
 */

#ifndef _PV_VIEWER_H_
#define _PV_VIEWER_H_

#import <AppKit/AppKit.h>
#import "PVViews.h"

@class PVPDFDocument;
@class PVSlideshow;

/* Posted when a viewer's window has closed. */
extern NSString *const PVViewerClosedNotification;

@interface PVViewer : NSObject <PVViewsOwner>
{
  NSString *path;
  BOOL isPDF;
  NSWindow *window;
  PVToolbar *toolbar;
  NSScrollView *sideScroll;
  PVSidebar *sidebar;
  NSScrollView *scroll;
  PVImageCanvas *imageCanvas;
  PVPDFCanvas *pdfCanvas;
  PVStatusBar *status;
  BOOL sidebarShown;
  double zoom;
  BOOL fit;

  /* a picture */
  NSArray *folder;		/* every picture in its folder */
  NSArray *shown;		/* those the search leaves */
  NSString *filter;
  NSBitmapImageRep *bitmap;
  int turned;			/* quarters, unsaved */
  long long fileSize;
  NSMutableDictionary *thumbs;	/* path -> NSImage */
  NSMutableDictionary *thumbSizes;
  NSMutableArray *thumbQueue;

  /* a PDF */
  PVPDFDocument *pdf;
  NSArray *matches;
  NSInteger matchIndex;
  NSString *query;
  int currentPage;
  NSMutableDictionary *pageThumbs;

  NSPanel *infoPanel;
  PVSlideshow *slideshow;
}
/* nil (after saying why) when the file can't be opened. */
+ (PVViewer *) viewerWithPath: (NSString *)path;

- (NSString *) path;
- (NSWindow *) window;
- (void) show;
/* Asks to save a turned picture: NO when the person cancels. */
- (BOOL) canClose;
- (void) layoutViews;
@end

#endif
