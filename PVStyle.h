/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PVStyle: Preview's colours, fonts and glyphs, from the mockup
 * (nextbsd/nextbsd#716). The theme draws the window and the standard
 * controls; Preview draws its toolbar, sidebar, status bar and the area
 * behind the picture, Dark or Light as NBAppearance says (the person's
 * choice in NSGlobalDomain, else the theme's default, else dark), as every
 * NextBSD app reads it.
 */

#ifndef _PV_STYLE_H_
#define _PV_STYLE_H_

#import <AppKit/AppKit.h>

/* Posted in this process when the appearance changes. */
extern NSString *const PVStyleChangedNotification;

@interface PVStyle : NSObject
+ (BOOL) light;
+ (void) reload;

+ (NSColor *) rgb: (unsigned)value alpha: (CGFloat)alpha;

+ (NSColor *) window;		/* the Info and Export panels */
+ (NSColor *) bar;		/* the toolbar and the status bar */
+ (NSColor *) sidebar;
+ (NSColor *) backdrop;		/* behind the picture or the pages */
+ (NSColor *) line;
+ (NSColor *) text;
+ (NSColor *) dim;
+ (NSColor *) faint;
+ (NSColor *) accent;
+ (NSColor *) accentText;
+ (NSColor *) selection;	/* the sidebar's chosen row, a pressed button */
+ (NSColor *) field;

+ (NSFont *) fontOfSize: (CGFloat)size bold: (BOOL)bold;

/* Strokes an SVG path drawn on a 24 x 24 grid (M L H V C A Z, either
   case) into rect, in a flipped view, with round caps and joins. */
+ (void) strokeGlyph: (NSString *)svg inRect: (NSRect)rect
               color: (NSColor *)color width: (CGFloat)width;

/* Text in a flipped view, its top left at point. */
+ (void) drawText: (NSString *)s at: (NSPoint)point font: (NSFont *)font
            color: (NSColor *)color;
+ (NSSize) sizeOfText: (NSString *)s font: (NSFont *)font;
/* Text cut with an ellipsis to fit width. */
+ (NSString *) text: (NSString *)s fitting: (CGFloat)width
               font: (NSFont *)font;

/* Draws image into rect the right way up in a flipped view. */
+ (void) drawImage: (NSImage *)image inRect: (NSRect)rect;

/* "Zero KB", "412 KB", "3.8 MB". */
+ (NSString *) sizeString: (long long)bytes;
@end

/* The mockup's glyphs. */
#define PVGlyphSidebar @"M4 5h16v14H4zM9 5v14"
#define PVGlyphZoomOut @"M10.5 4a6.5 6.5 0 1 0 .01 0M15.5 15.5L20 20M7.5 10.5h6"
#define PVGlyphZoomIn @"M10.5 4a6.5 6.5 0 1 0 .01 0M15.5 15.5L20 20M7.5 10.5h6M10.5 7.5v6"
#define PVGlyphRotate @"M5 12a7 7 0 1 0 2-5M5 4v4h4"
#define PVGlyphInfo @"M12 3a9 9 0 1 0 .01 0M12 11v6M12 7.5h.01"
#define PVGlyphSlides @"M4 5h16v11H4zM8 20h8M12 16v4M10 8.5v4l3.5-2z"
#define PVGlyphShare @"M12 3v12M8 7l4-4 4 4M5 12v8h14v-8"
#define PVGlyphUp @"M6 15l6-6 6 6"
#define PVGlyphDown @"M6 9l6 6 6-6"
#define PVGlyphSearch @"M10.5 4a6.5 6.5 0 1 0 .01 0M15.5 15.5L20 20"

#endif
