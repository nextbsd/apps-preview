/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Preview's own views, as the mockup draws them (nextbsd/nextbsd#716):
 * the toolbar, the sidebar of pictures or pages, the status bar, and what
 * shows the picture or the PDF's pages.
 */

#ifndef _PV_VIEWS_H_
#define _PV_VIEWS_H_

#import <AppKit/AppKit.h>

@class PVPDFDocument;
@class PVMatch;

typedef enum
{
  PVToolSidebar,
  PVToolZoomOut,
  PVToolZoomIn,
  PVToolRotate,
  PVToolInfo,
  PVToolSlides,
  PVToolShare,
  PVToolPreviousMatch,
  PVToolNextMatch,
  PVToolCount
} PVTool;

/* What the views tell the window's PVViewer. */
@protocol PVViewsOwner
- (void) toolClicked: (PVTool)tool;
- (NSUInteger) sidebarCount;
- (NSImage *) sidebarThumbnail: (NSUInteger)index;	/* nil: not yet */
- (NSSize) sidebarThumbnailSize: (NSUInteger)index;
- (NSString *) sidebarLabel: (NSUInteger)index;
- (void) sidebarChose: (NSUInteger)index;
/* Keys the picture or the pages don't use: arrows, Escape. */
- (BOOL) viewKeyDown: (NSEvent *)event;
- (void) pagesScrolled;
- (void) searchFor: (NSString *)text;
@end

/* ---- the toolbar -------------------------------------------------------- */

@interface PVToolbar : NSView
{
  id<PVViewsOwner> owner;
  NSSearchField *search;
  NSString *zoomText;
  NSString *matchText;		/* nil: no search */
  BOOL sidebarOn;
  int pressed;
  NSRect rects[PVToolCount];
}
- (id) initWithFrame: (NSRect)frame owner: (id<PVViewsOwner>)o;
- (NSSearchField *) searchField;
- (void) setZoomText: (NSString *)s;
- (void) setMatchText: (NSString *)s;
- (void) setSidebarOn: (BOOL)flag;
@end

/* ---- the sidebar -------------------------------------------------------- */

@interface PVSidebar : NSView
{
  id<PVViewsOwner> owner;
  NSInteger selected;
  NSMutableArray *tops;		/* each row's top */
  CGFloat height;
}
- (id) initWithFrame: (NSRect)frame owner: (id<PVViewsOwner>)o;
/* The rows changed: count, sizes, labels. */
- (void) reload;
- (NSInteger) selectedIndex;
- (void) setSelectedIndex: (NSInteger)index;
@end

/* ---- the status bar ----------------------------------------------------- */

@interface PVStatusBar : NSView
{
  NSArray *left;
  NSString *right;
}
- (void) setLeft: (NSArray *)strings right: (NSString *)string;
@end

/* ---- a picture ---------------------------------------------------------- */

@interface PVImageCanvas : NSView
{
  id<PVViewsOwner> owner;
  NSImage *image;
  NSSize pixels;
  double zoom;
}
- (id) initWithFrame: (NSRect)frame owner: (id<PVViewsOwner>)o;
- (void) setBitmap: (NSBitmapImageRep *)rep;
- (void) setZoom: (double)z;
/* The frame for the scroll view's visible size. */
- (void) fitToVisibleSize: (NSSize)size;
@end

/* ---- a PDF's pages ------------------------------------------------------ */

@interface PVPDFCanvas : NSView
{
  id<PVViewsOwner> owner;
  PVPDFDocument *doc;
  double zoom;
  double scale;			/* device pixels a point */
  NSArray *matches;		/* PVMatch */
  NSInteger currentMatch;
  /* selection: glyphs on one page */
  int selPage, selFrom, selTo;
}
- (id) initWithFrame: (NSRect)frame owner: (id<PVViewsOwner>)o;
- (void) setDocument: (PVPDFDocument *)d;
- (void) setZoom: (double)z;
- (double) zoom;
- (void) setDeviceScale: (double)s;
- (void) fitToVisibleSize: (NSSize)size;
/* Where the page is in the view. */
- (NSRect) rectOfPage: (int)page;
/* The page in the middle of rect. */
- (int) pageAt: (NSRect)visible;
- (void) setMatches: (NSArray *)m current: (NSInteger)i;
- (void) revealMatch: (PVMatch *)match;
/* Scrolls the page's top to the top. */
- (void) revealPage: (int)page;
- (void) clearSelection;
- (NSString *) selectedText;
- (void) layout;
@end

#endif
