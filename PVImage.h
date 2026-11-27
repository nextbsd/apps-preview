/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PVImage: reading and writing pictures. GNUstep's NSBitmapImageRep reads
 * them (PNG, JPEG, TIFF, GIF and whatever else it has a reader for);
 * Preview reads BMP itself when GNUstep can't, reads EXIF (when and with
 * what camera, and which way up), and turns, halves and writes bitmaps.
 */

#ifndef _PV_IMAGE_H_
#define _PV_IMAGE_H_

#import <AppKit/AppKit.h>

typedef enum
{
  PVFormatPNG,
  PVFormatJPEG,
  PVFormatTIFF,
  PVFormatPDF,
  PVFormatGIF,
  PVFormatBMP,
  PVFormatOther
} PVFormat;

@interface PVImage : NSObject

/* Extensions Preview opens as pictures, lower case. */
+ (NSArray *) imageExtensions;
+ (BOOL) isImagePath: (NSString *)path;
+ (BOOL) isPDFPath: (NSString *)path;

/* The picture's first frame, turned the way its EXIF says is up. nil when
   it can't be read. */
+ (NSBitmapImageRep *) readBitmapAtPath: (NSString *)path;

/* EXIF: "Make", "Model", "Taken" (an NSCalendarDate), "Orientation" (an
   NSNumber, 1-8), "Software". Empty when the file has none. */
+ (NSDictionary *) exifAtPath: (NSString *)path;

+ (PVFormat) formatForPath: (NSString *)path;
/* "PNG", "JPEG" ... */
+ (NSString *) formatName: (NSString *)path;
+ (NSString *) extensionForFormat: (PVFormat)format;

/* Turned quarters clockwise (negative: the other way). */
+ (NSBitmapImageRep *) bitmap: (NSBitmapImageRep *)rep
                      rotated: (int)quarters;
/* Width and height divided by factor (2 for half size), averaging. */
+ (NSBitmapImageRep *) bitmap: (NSBitmapImageRep *)rep
                    reducedBy: (int)factor;
/* No bigger than side pixels either way, for a thumbnail. */
+ (NSBitmapImageRep *) thumbnailOf: (NSBitmapImageRep *)rep
                              side: (int)side;
/* 8-bit RGB, from 3-byte rows. */
+ (NSBitmapImageRep *) bitmapWithRGB: (unsigned char *)rgb
                               width: (int)w height: (int)h
                              stride: (int)stride;

/* The file's bytes in format; quality 0-1 for JPEG. dpi is what a PDF's
   page size comes from. nil when it can't be written. */
+ (NSData *) dataForBitmap: (NSBitmapImageRep *)rep
                    format: (PVFormat)format
                   quality: (float)quality;

/* jpeg with the EXIF of the JPEG at path, if it has any, saying the
   picture is the right way up (its pixels are turned already). */
+ (NSData *) JPEG: (NSData *)jpeg withExifOf: (NSString *)path;

/* "Colour" in Info: "RGB", "RGB with transparency", "Grey", "CMYK". */
+ (NSString *) colourDescription: (NSBitmapImageRep *)rep;
/* Pixels per inch, from the size the file gives. */
+ (double) resolution: (NSBitmapImageRep *)rep;
@end

#endif
