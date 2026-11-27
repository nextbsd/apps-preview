/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PVPDFDocument: an open PDF. Pages are rendered by Poppler when they are
 * first shown, at the resolution they are shown at, and the last few are
 * kept; so are the thumbnails and each page's text.
 *
 * Points on a page are PDF points from the top left of the page as it is
 * shown, turned as the person turned it (rotation, quarters clockwise).
 */

#ifndef _PV_PDF_DOCUMENT_H_
#define _PV_PDF_DOCUMENT_H_

#import <AppKit/AppKit.h>
#import "PVPoppler.h"

/* A search match: a page and where on it. */
@interface PVMatch : NSObject
{
@public
  int page;
  NSRect rect;			/* unturned */
}
@end

/* A page's text: its glyphs in reading order. */
@interface PVPageText : NSObject
{
@public
  PVText text;
}
/* The glyph nearest point (unturned), or -1 when the page has none. */
- (int) glyphNearest: (NSPoint)point;
/* The glyphs from to to, as text, with spaces and line breaks. */
- (NSString *) stringFrom: (int)from to: (int)to;
@end

@interface PVPDFDocument : NSObject
{
  PVPDF *pdf;
  NSString *path;
  int pages;
  NSSize *sizes;
  int rotation;
  NSMutableDictionary *renders;	/* "page dpi" -> NSBitmapImageRep */
  NSMutableArray *renderOrder;
  NSMutableDictionary *thumbs;	/* page -> NSBitmapImageRep */
  NSMutableDictionary *texts;	/* page -> PVPageText */
}
/* nil when it can't be opened; *locked when it needs a password. */
+ (PVPDFDocument *) documentWithPath: (NSString *)path locked: (BOOL *)locked;

- (NSString *) path;
- (int) pageCount;
/* As shown: turned. */
- (NSSize) sizeOfPage: (int)page;
/* Before the person's turning. */
- (NSSize) unturnedSizeOfPage: (int)page;
- (int) rotation;
- (void) setRotation: (int)quarters;

/* The page at dpi, turned. */
- (NSBitmapImageRep *) renderPage: (int)page dpi: (double)dpi;
/* A small picture of the page, turned, for the sidebar. */
- (NSBitmapImageRep *) thumbnailOfPage: (int)page;
- (BOOL) hasThumbnailOfPage: (int)page;

- (PVPageText *) textOfPage: (int)page;
/* Every match for query, page by page. */
- (NSArray *) search: (NSString *)query;

/* Between unturned page points and turned ones. */
- (NSRect) turnRect: (NSRect)r onPage: (int)page;
- (NSPoint) unturnPoint: (NSPoint)p onPage: (int)page;

/* Info: Title, Author, Producer, Creator, Subject. */
- (NSString *) infoForKey: (NSString *)key;
- (NSDate *) creationDate;
@end

/* "Letter · 8.5 × 11 in", "A4 · 210 × 297 mm". */
NSString *PVPaperDescription (NSSize points);

#endif
