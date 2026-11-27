/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PVExport: the Export sheet. Saves a copy of the picture (or of a PDF's
 * page, as a picture) as PNG, JPEG, TIFF or PDF, full or half size, with
 * the size it will be shown before it is saved; or a PDF as itself.
 */

#ifndef _PV_EXPORT_H_
#define _PV_EXPORT_H_

#import <AppKit/AppKit.h>

@interface PVExport : NSObject
{
  NSPanel *panel;
  NSTextField *nameField;
  NSPopUpButton *wherePopup;
  NSPopUpButton *formatPopup;
  NSSlider *qualitySlider;
  NSTextField *qualityLabel;
  NSTextField *qualityTitle;
  NSPopUpButton *sizePopup;
  NSTextField *estimate;
  NSMutableArray *folders;
  NSBitmapImageRep *bitmap;
  NSString *pdfPath;
  NSString *pageLabel;
  int sourceFormat;
  NSString *sourcePath;
}
/* bitmap: the picture, or the PDF's page rendered at full size; path:
   the file shown (a PDF is offered as a PDF too); label: "Page 2" when a
   PDF's page is the picture. */
+ (void) runForWindow: (NSWindow *)window
               bitmap: (NSBitmapImageRep *)bitmap
                 path: (NSString *)path
            pageLabel: (NSString *)label;
@end

#endif
