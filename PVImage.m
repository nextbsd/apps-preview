/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PVImage.h"
#include <zlib.h>

@implementation PVImage

+ (NSArray *) imageExtensions
{
  static NSMutableArray *list = nil;

  if (list == nil)
    {
      NSArray *gnustep = [NSBitmapImageRep imageUnfilteredFileTypes];
      NSUInteger i;

      list = [[NSMutableArray alloc] initWithObjects: @"png", @"jpg",
                                     @"jpeg", @"jpe", @"tif", @"tiff",
                                     @"gif", @"bmp", nil];
      for (i = 0; i < [gnustep count]; i++)
        {
          NSString *e = [[gnustep objectAtIndex: i] lowercaseString];

          /* Only real file extensions, not pasteboard types. */
          if ([e length] > 0 && [e length] <= 5
              && [e rangeOfString: @"."].location == NSNotFound
              && ![e isEqual: @"pdf"] && ![e isEqual: @"eps"]
              && ![e isEqual: @"ps"] && ![list containsObject: e])
            [list addObject: e];
        }
    }
  return list;
}

+ (BOOL) isImagePath: (NSString *)path
{
  return [[self imageExtensions] containsObject:
                                   [[path pathExtension] lowercaseString]];
}

+ (BOOL) isPDFPath: (NSString *)path
{
  return [[[path pathExtension] lowercaseString] isEqual: @"pdf"];
}

/* ---- pixels ---- */

/* 8 bits a sample, one plane, samples packed: the layout everything
   below works on. */
static BOOL
PVIsMeshed8 (NSBitmapImageRep *rep)
{
  return [rep bitsPerSample] == 8 && ![rep isPlanar]
    && [rep bitsPerPixel] == 8 * [rep samplesPerPixel]
    && [rep bitmapData] != NULL;
}

static NSBitmapImageRep *
PVNewBitmap (int w, int h, int spp, BOOL alpha, NSString *space,
             NSBitmapFormat format)
{
  return AUTORELEASE ([[NSBitmapImageRep alloc]
                        initWithBitmapDataPlanes: NULL
                                      pixelsWide: w
                                      pixelsHigh: h
                                   bitsPerSample: 8
                                 samplesPerPixel: spp
                                        hasAlpha: alpha
                                        isPlanar: NO
                                  colorSpaceName: space
                                    bitmapFormat: format
                                     bytesPerRow: w * spp
                                    bitsPerPixel: 8 * spp]);
}

/* Any bitmap as 8-bit RGB(A), through NSColor: slow, for the odd ones
   (16 bits a sample, planar, CMYK). */
static NSBitmapImageRep *
PVConvert (NSBitmapImageRep *rep)
{
  int w = [rep pixelsWide], h = [rep pixelsHigh], x, y;
  BOOL alpha = [rep hasAlpha];
  int spp = alpha ? 4 : 3;
  NSBitmapImageRep *out = PVNewBitmap (w, h, spp, alpha,
                                       NSCalibratedRGBColorSpace, 0);
  unsigned char *d = [out bitmapData];

  for (y = 0; y < h; y++)
    for (x = 0; x < w; x++)
      {
        NSColor *c = [[rep colorAtX: x y: y]
                       colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
        CGFloat r = 0, g = 0, b = 0, a = 1;
        unsigned char *p = d + ((size_t) y * w + x) * spp;

        if (c != nil)
          [c getRed: &r green: &g blue: &b alpha: &a];
        p[0] = (unsigned char) (r * 255 + 0.5);
        p[1] = (unsigned char) (g * 255 + 0.5);
        p[2] = (unsigned char) (b * 255 + 0.5);
        if (alpha)
          p[3] = (unsigned char) (a * 255 + 0.5);
      }
  [out setSize: [rep size]];
  return out;
}

static NSBitmapImageRep *
PVMeshed (NSBitmapImageRep *rep)
{
  return PVIsMeshed8 (rep) ? rep : PVConvert (rep);
}

static NSSize
PVSizeAtResolution (NSBitmapImageRep *rep, int w, int h)
{
  double dpi = [PVImage resolution: rep];

  return NSMakeSize (w * 72.0 / dpi, h * 72.0 / dpi);
}

+ (double) resolution: (NSBitmapImageRep *)rep
{
  double dpi = 72;

  if ([rep size].width > 0)
    dpi = [rep pixelsWide] * 72.0 / [rep size].width;
  if (dpi < 1 || dpi > 10000)
    dpi = 72;
  return dpi;
}

+ (NSBitmapImageRep *) bitmap: (NSBitmapImageRep *)rep
                      rotated: (int)quarters
{
  NSBitmapImageRep *src, *out;
  int w, h, spp, x, y, nw, nh, q = ((quarters % 4) + 4) % 4;
  unsigned char *s, *d;
  NSInteger srow;

  if (q == 0)
    return rep;
  src = PVMeshed (rep);
  w = [src pixelsWide];
  h = [src pixelsHigh];
  spp = [src samplesPerPixel];
  srow = [src bytesPerRow];
  nw = (q % 2) ? h : w;
  nh = (q % 2) ? w : h;
  out = PVNewBitmap (nw, nh, spp, [src hasAlpha], [src colorSpaceName],
                     [src bitmapFormat]);
  s = [src bitmapData];
  d = [out bitmapData];
  for (y = 0; y < h; y++)
    {
      unsigned char *from = s + (size_t) y * srow;

      for (x = 0; x < w; x++)
        {
          int dx, dy;

          switch (q)
            {
            case 1: dx = h - 1 - y; dy = x; break;
            case 2: dx = w - 1 - x; dy = h - 1 - y; break;
            default: dx = y; dy = w - 1 - x; break;
            }
          memcpy (d + ((size_t) dy * nw + dx) * spp, from + x * spp, spp);
        }
    }
  [out setSize: (q % 2) ? NSMakeSize ([rep size].height, [rep size].width)
                        : [rep size]];
  return out;
}

+ (NSBitmapImageRep *) bitmap: (NSBitmapImageRep *)rep
                    reducedBy: (int)f
{
  NSBitmapImageRep *src, *out;
  int w, h, spp, nw, nh, x, y, i, j, k;
  unsigned char *s, *d;
  NSInteger srow;

  if (f <= 1)
    return rep;
  src = PVMeshed (rep);
  w = [src pixelsWide];
  h = [src pixelsHigh];
  spp = [src samplesPerPixel];
  srow = [src bytesPerRow];
  nw = MAX (1, w / f);
  nh = MAX (1, h / f);
  out = PVNewBitmap (nw, nh, spp, [src hasAlpha], [src colorSpaceName],
                     [src bitmapFormat]);
  s = [src bitmapData];
  d = [out bitmapData];
  for (y = 0; y < nh; y++)
    for (x = 0; x < nw; x++)
      {
        unsigned sum[5] = { 0, 0, 0, 0, 0 };
        int n = 0;

        for (j = 0; j < f && y * f + j < h; j++)
          for (i = 0; i < f && x * f + i < w; i++)
            {
              unsigned char *p = s + (size_t) (y * f + j) * srow
                + (size_t) (x * f + i) * spp;

              for (k = 0; k < spp && k < 5; k++)
                sum[k] += p[k];
              n++;
            }
        for (k = 0; k < spp && k < 5; k++)
          d[((size_t) y * nw + x) * spp + k] = n ? sum[k] / n : 0;
      }
  [out setSize: PVSizeAtResolution (rep, nw, nh)];
  return out;
}

+ (NSBitmapImageRep *) thumbnailOf: (NSBitmapImageRep *)rep side: (int)side
{
  int big = MAX ([rep pixelsWide], [rep pixelsHigh]);
  int f = big / (2 * side);

  return f > 1 ? [self bitmap: rep reducedBy: f] : rep;
}

+ (NSBitmapImageRep *) bitmapWithRGB: (unsigned char *)rgb
                               width: (int)w height: (int)h
                              stride: (int)stride
{
  NSBitmapImageRep *out = PVNewBitmap (w, h, 3, NO,
                                       NSCalibratedRGBColorSpace, 0);
  unsigned char *d = [out bitmapData];
  int y;

  for (y = 0; y < h; y++)
    memcpy (d + (size_t) y * w * 3, rgb + (size_t) y * stride, w * 3);
  return out;
}

/* 8-bit RGB with no alpha, on white: for JPEG, BMP and PDF. */
static NSBitmapImageRep *
PVOpaqueRGB (NSBitmapImageRep *rep)
{
  NSBitmapImageRep *src = PVMeshed (rep), *out;
  int w = [src pixelsWide], h = [src pixelsHigh], spp = [src samplesPerPixel];
  BOOL alpha = [src hasAlpha];
  BOOL alphaFirst = ([src bitmapFormat] & NSAlphaFirstBitmapFormat) != 0;
  BOOL premultiplied = alpha
    && ([src bitmapFormat] & NSAlphaNonpremultipliedBitmapFormat) == 0;
  int colours = alpha ? spp - 1 : spp;
  NSInteger srow = [src bytesPerRow];
  unsigned char *s = [src bitmapData], *d;
  int x, y, k;

  if (colours == 3 && !alpha)
    return src;
  if (colours != 1 && colours != 3)
    return PVOpaqueRGB (PVConvert (rep));
  out = PVNewBitmap (w, h, 3, NO, NSCalibratedRGBColorSpace, 0);
  d = [out bitmapData];
  for (y = 0; y < h; y++)
    for (x = 0; x < w; x++)
      {
        unsigned char *p = s + (size_t) y * srow + (size_t) x * spp;
        unsigned char *q = d + ((size_t) y * w + x) * 3;
        unsigned a = 255, c[3];
        const unsigned char *col = p;

        if (alpha)
          {
            a = alphaFirst ? p[0] : p[colours];
            col = alphaFirst ? p + 1 : p;
          }
        for (k = 0; k < 3; k++)
          c[k] = col[colours == 1 ? 0 : k];
        for (k = 0; k < 3; k++)
          {
            unsigned v = premultiplied ? c[k] + (255 - a)
              : (c[k] * a + 255 * (255 - a)) / 255;

            q[k] = v > 255 ? 255 : v;
          }
      }
  [out setSize: [rep size]];
  return out;
}

+ (NSString *) colourDescription: (NSBitmapImageRep *)rep
{
  NSString *space = [rep colorSpaceName], *s;

  if ([space isEqual: NSCalibratedWhiteColorSpace]
      || [space isEqual: NSDeviceWhiteColorSpace]
      || [space isEqual: NSDeviceBlackColorSpace]
      || [space isEqual: NSCalibratedBlackColorSpace])
    s = @"Grey";
  else if ([space isEqual: NSDeviceCMYKColorSpace])
    s = @"CMYK";
  else
    s = @"RGB";
  if ([rep hasAlpha])
    s = [s stringByAppendingString: @" with transparency"];
  if ([rep bitsPerSample] == 16)
    s = [s stringByAppendingString: @", 16 bits a channel"];
  return s;
}

/* ---- BMP ---- */

static unsigned
PVLE (const unsigned char *p, int n)
{
  unsigned v = 0;
  int i;

  for (i = n - 1; i >= 0; i--)
    v = (v << 8) | p[i];
  return v;
}

/* Uncompressed (and bit-field) BMPs of 1, 4, 8, 24 and 32 bits. */
static NSBitmapImageRep *
PVReadBMP (NSData *data)
{
  const unsigned char *b = [data bytes], *palette, *pixels;
  NSUInteger len = [data length];
  unsigned offset, header, compression, colours;
  int w, h, bpp, row, x, y, spp;
  BOOL topDown = NO, alpha = NO;
  NSBitmapImageRep *out;
  unsigned char *d;

  if (len < 54 || b[0] != 'B' || b[1] != 'M')
    return nil;
  offset = PVLE (b + 10, 4);
  header = PVLE (b + 14, 4);
  if (header < 40 || 14 + header > len)
    return nil;
  w = (int) PVLE (b + 18, 4);
  h = (int) PVLE (b + 22, 4);
  bpp = PVLE (b + 28, 2);
  compression = PVLE (b + 30, 4);
  colours = PVLE (b + 46, 4);
  if (h < 0)
    {
      h = -h;
      topDown = YES;
    }
  if (w <= 0 || h <= 0 || w > 30000 || h > 30000
      || (compression != 0 && compression != 3))
    return nil;
  if (bpp != 1 && bpp != 4 && bpp != 8 && bpp != 24 && bpp != 32)
    return nil;
  row = ((w * bpp + 31) / 32) * 4;
  if (offset + (NSUInteger) row * h > len)
    return nil;
  palette = b + 14 + header;
  if (colours == 0 && bpp <= 8)
    colours = 1u << bpp;
  if (bpp <= 8 && palette + colours * 4 > b + len)
    return nil;
  pixels = b + offset;
  /* 32 bits: the fourth byte is alpha when any pixel has some. */
  if (bpp == 32)
    for (y = 0; y < h && !alpha; y++)
      for (x = 0; x < w; x++)
        if (pixels[(size_t) y * row + 4 * x + 3] != 0)
          {
            alpha = YES;
            break;
          }
  spp = alpha ? 4 : 3;
  out = PVNewBitmap (w, h, spp, alpha, NSCalibratedRGBColorSpace,
                     alpha ? NSAlphaNonpremultipliedBitmapFormat : 0);
  d = [out bitmapData];
  for (y = 0; y < h; y++)
    {
      const unsigned char *s = pixels + (size_t) (topDown ? y : h - 1 - y) * row;
      unsigned char *q = d + (size_t) y * w * spp;

      for (x = 0; x < w; x++, q += spp)
        {
          unsigned index;

          switch (bpp)
            {
            case 24: case 32:
              q[0] = s[x * (bpp / 8) + 2];
              q[1] = s[x * (bpp / 8) + 1];
              q[2] = s[x * (bpp / 8)];
              if (alpha)
                q[3] = s[x * 4 + 3];
              continue;
            case 8: index = s[x]; break;
            case 4: index = (s[x / 2] >> ((x % 2) ? 0 : 4)) & 15; break;
            default: index = (s[x / 8] >> (7 - x % 8)) & 1; break;
            }
          if (index >= colours)
            index = 0;
          q[0] = palette[index * 4 + 2];
          q[1] = palette[index * 4 + 1];
          q[2] = palette[index * 4];
        }
    }
  return out;
}

static NSData *
PVWriteBMP (NSBitmapImageRep *rep)
{
  NSBitmapImageRep *rgb = PVOpaqueRGB (rep);
  int w = [rgb pixelsWide], h = [rgb pixelsHigh], row = ((w * 3 + 3) / 4) * 4;
  NSMutableData *out = [NSMutableData dataWithLength: 54 + (size_t) row * h];
  unsigned char *b = [out mutableBytes], *s = [rgb bitmapData];
  NSInteger srow = [rgb bytesPerRow];
  unsigned v[] = { 54 + row * h, 0, 54, 40, w, h };
  int x, y, i;

  b[0] = 'B';
  b[1] = 'M';
  for (i = 0; i < 6; i++)
    {
      int at = (i < 3) ? 2 + 4 * i : 14 + 4 * (i - 3);

      b[at] = v[i] & 255;
      b[at + 1] = (v[i] >> 8) & 255;
      b[at + 2] = (v[i] >> 16) & 255;
      b[at + 3] = (v[i] >> 24) & 255;
    }
  b[26] = 1;			/* planes */
  b[28] = 24;			/* bits a pixel */
  for (y = 0; y < h; y++)
    {
      unsigned char *q = b + 54 + (size_t) (h - 1 - y) * row;
      unsigned char *p = s + (size_t) y * srow;

      for (x = 0; x < w; x++)
        {
          q[3 * x] = p[3 * x + 2];
          q[3 * x + 1] = p[3 * x + 1];
          q[3 * x + 2] = p[3 * x];
        }
    }
  return out;
}

/* ---- PDF ---- */

/* One page, the picture filling it, at the picture's resolution. */
static NSData *
PVWritePDF (NSBitmapImageRep *rep)
{
  NSBitmapImageRep *rgb = PVOpaqueRGB (rep);
  int w = [rgb pixelsWide], h = [rgb pixelsHigh], y;
  double dpi = [PVImage resolution: rep];
  double pw = w * 72.0 / dpi, ph = h * 72.0 / dpi;
  NSMutableData *raw = [NSMutableData dataWithLength: (size_t) w * 3 * h];
  NSMutableData *out = [NSMutableData data];
  NSMutableArray *offsets = [NSMutableArray array];
  uLongf zlen = compressBound ((uLong) [raw length]);
  NSMutableData *z = [NSMutableData dataWithLength: zlen];
  NSString *content;
  NSUInteger xref, i;

  for (y = 0; y < h; y++)
    memcpy ((unsigned char *) [raw mutableBytes] + (size_t) y * w * 3,
            [rgb bitmapData] + (size_t) y * [rgb bytesPerRow], w * 3);
  if (compress2 ([z mutableBytes], &zlen, [raw bytes], [raw length], 6)
      != Z_OK)
    return nil;
  [z setLength: zlen];
  content = [NSString stringWithFormat: @"q %.3f 0 0 %.3f 0 0 cm /Im0 Do Q\n",
                      pw, ph];

#define PVAPPEND(s) [out appendData: [(s) dataUsingEncoding: NSASCIIStringEncoding]]
#define PVOBJECT() [offsets addObject: [NSNumber numberWithUnsignedInteger: [out length]]]
  [out appendBytes: "%PDF-1.4\n%\xe2\xe3\xcf\xd3\n" length: 15];
  PVOBJECT ();
  PVAPPEND (@"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
  PVOBJECT ();
  PVAPPEND (@"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
  PVOBJECT ();
  PVAPPEND (([NSString stringWithFormat:
                         @"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.3f %.3f] "
                       @"/Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>\nendobj\n",
                       pw, ph]));
  PVOBJECT ();
  PVAPPEND (([NSString stringWithFormat:
                         @"4 0 obj\n<< /Length %lu >>\nstream\n%@endstream\nendobj\n",
                       (unsigned long) [content length], content]));
  PVOBJECT ();
  PVAPPEND (([NSString stringWithFormat:
                         @"5 0 obj\n<< /Type /XObject /Subtype /Image /Width %d /Height %d "
                       @"/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode "
                       @"/Length %lu >>\nstream\n", w, h, (unsigned long) zlen]));
  [out appendData: z];
  PVAPPEND (@"\nendstream\nendobj\n");
  xref = [out length];
  PVAPPEND (([NSString stringWithFormat: @"xref\n0 %lu\n0000000000 65535 f \n",
                       (unsigned long) [offsets count] + 1]));
  for (i = 0; i < [offsets count]; i++)
    PVAPPEND (([NSString stringWithFormat: @"%010lu 00000 n \n",
                         (unsigned long) [[offsets objectAtIndex: i]
                                           unsignedIntegerValue]]));
  PVAPPEND (([NSString stringWithFormat:
                         @"trailer\n<< /Size %lu /Root 1 0 R >>\nstartxref\n%lu\n%%%%EOF\n",
                       (unsigned long) [offsets count] + 1,
                       (unsigned long) xref]));
#undef PVAPPEND
#undef PVOBJECT
  return out;
}

/* ---- EXIF ---- */

typedef struct
{
  const unsigned char *b;
  NSUInteger len;
  BOOL big;
} PVTiff;

static unsigned
PVTiffInt (PVTiff *t, NSUInteger at, int n)
{
  unsigned v = 0;
  int i;

  if (at + n > t->len)
    return 0;
  for (i = 0; i < n; i++)
    v = t->big ? (v << 8) | t->b[at + i]
      : v | ((unsigned) t->b[at + i] << (8 * i));
  return v;
}

static NSString *
PVTiffString (PVTiff *t, NSUInteger entry)
{
  unsigned count = PVTiffInt (t, entry + 4, 4);
  NSUInteger at = count <= 4 ? entry + 8 : PVTiffInt (t, entry + 8, 4);
  NSString *s;

  if (count == 0 || at + count > t->len)
    return nil;
  while (count > 0 && t->b[at + count - 1] == '\0')
    count--;
  s = AUTORELEASE ([[NSString alloc] initWithBytes: t->b + at length: count
                                          encoding: NSUTF8StringEncoding]);
  if (s == nil)
    s = AUTORELEASE ([[NSString alloc] initWithBytes: t->b + at
                                              length: count
                                            encoding: NSISOLatin1StringEncoding]);
  s = [s stringByTrimmingCharactersInSet:
           [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return [s length] > 0 ? s : nil;
}

static void
PVTiffIFD (PVTiff *t, NSUInteger ifd, NSMutableDictionary *out, int depth)
{
  unsigned n = PVTiffInt (t, ifd, 2), i;

  if (depth > 2 || ifd == 0 || ifd + 2 + 12 * n > t->len)
    return;
  for (i = 0; i < n; i++)
    {
      NSUInteger e = ifd + 2 + 12 * i;
      unsigned tag = PVTiffInt (t, e, 2), type = PVTiffInt (t, e + 2, 2);
      NSString *s;

      switch (tag)
        {
        case 0x010F: if ((s = PVTiffString (t, e))) [out setObject: s forKey: @"Make"]; break;
        case 0x0110: if ((s = PVTiffString (t, e))) [out setObject: s forKey: @"Model"]; break;
        case 0x0131: if ((s = PVTiffString (t, e))) [out setObject: s forKey: @"Software"]; break;
        case 0x0132:
          if ((s = PVTiffString (t, e)) && [out objectForKey: @"Original"] == nil)
            [out setObject: s forKey: @"DateTime"];
          break;
        case 0x9003: if ((s = PVTiffString (t, e))) [out setObject: s forKey: @"Original"]; break;
        case 0x0112:
          [out setObject: [NSNumber numberWithUnsignedInt:
                                      PVTiffInt (t, e + 8, type == 3 ? 2 : 4)]
                  forKey: @"Orientation"];
          break;
        case 0x8769:
          PVTiffIFD (t, PVTiffInt (t, e + 8, 4), out, depth + 1);
          break;
        }
    }
}

static void
PVParseTiff (const unsigned char *b, NSUInteger len, NSMutableDictionary *out)
{
  PVTiff t;

  if (len < 8)
    return;
  t.b = b;
  t.len = len;
  if (b[0] == 'I' && b[1] == 'I')
    t.big = NO;
  else if (b[0] == 'M' && b[1] == 'M')
    t.big = YES;
  else
    return;
  if (PVTiffInt (&t, 2, 2) != 42)
    return;
  PVTiffIFD (&t, PVTiffInt (&t, 4, 4), out, 0);
}

+ (NSDictionary *) exifAtPath: (NSString *)path
{
  NSData *data = [NSData dataWithContentsOfMappedFile: path];
  const unsigned char *b = [data bytes];
  NSUInteger len = [data length], at;
  NSMutableDictionary *out = [NSMutableDictionary dictionary];
  NSString *when;

  if (len >= 4 && b[0] == 0xFF && b[1] == 0xD8)
    {
      /* JPEG: the APP1 segment that starts "Exif\0\0". */
      at = 2;
      while (at + 4 <= len && b[at] == 0xFF)
        {
          unsigned marker = b[at + 1];
          unsigned seg = (b[at + 2] << 8) | b[at + 3];

          if (marker == 0xDA || marker == 0xD9 || seg < 2)
            break;
          if (marker == 0xE1 && seg >= 8 && at + 2 + seg <= len
              && memcmp (b + at + 4, "Exif\0\0", 6) == 0)
            {
              PVParseTiff (b + at + 10, seg - 8, out);
              break;
            }
          at += 2 + seg;
        }
    }
  else if (len >= 8 && ((b[0] == 'I' && b[1] == 'I') || (b[0] == 'M' && b[1] == 'M')))
    PVParseTiff (b, len, out);
  else if (len >= 8 && memcmp (b, "\x89PNG", 4) == 0)
    {
      /* PNG: the eXIf chunk. */
      at = 8;
      while (at + 12 <= len)
        {
          unsigned n = (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

          if (at + 12 + (NSUInteger) n > len)
            break;
          if (memcmp (b + at + 4, "eXIf", 4) == 0)
            {
              PVParseTiff (b + at + 8, n, out);
              break;
            }
          if (memcmp (b + at + 4, "IDAT", 4) == 0)
            break;
          at += 12 + n;
        }
    }
  when = [out objectForKey: @"Original"];
  if (when == nil)
    when = [out objectForKey: @"DateTime"];
  if (when != nil)
    {
      NSCalendarDate *d = [NSCalendarDate dateWithString: when
                                          calendarFormat: @"%Y:%m:%d %H:%M:%S"];

      if (d != nil)
        [out setObject: d forKey: @"Taken"];
    }
  [out removeObjectForKey: @"Original"];
  [out removeObjectForKey: @"DateTime"];
  return out;
}

/* The original's APP1 Exif segment, whole, or nil. */
static NSData *
PVExifSegment (NSData *data)
{
  const unsigned char *b = [data bytes];
  NSUInteger len = [data length], at = 2;

  if (len < 4 || b[0] != 0xFF || b[1] != 0xD8)
    return nil;
  while (at + 4 <= len && b[at] == 0xFF)
    {
      unsigned marker = b[at + 1];
      unsigned seg = (b[at + 2] << 8) | b[at + 3];

      if (marker == 0xDA || marker == 0xD9 || seg < 2)
        break;
      if (marker == 0xE1 && seg >= 8 && at + 2 + seg <= len
          && memcmp (b + at + 4, "Exif\0\0", 6) == 0)
        return [data subdataWithRange: NSMakeRange (at, 2 + seg)];
      at += 2 + seg;
    }
  return nil;
}

+ (NSData *) JPEG: (NSData *)jpeg withExifOf: (NSString *)path
{
  NSMutableData *exif = [[PVExifSegment ([NSData dataWithContentsOfFile:
                                                  path]) mutableCopy]
                          autorelease];
  const unsigned char *j = [jpeg bytes];
  NSUInteger len = [jpeg length], at = 2;
  NSMutableData *out;
  PVTiff t;
  unsigned n, i, ifd;

  if (exif == nil || len < 4 || j[0] != 0xFF || j[1] != 0xD8)
    return jpeg;
  /* Orientation 1: the right way up. */
  t.b = (unsigned char *) [exif mutableBytes] + 10;
  t.len = [exif length] - 10;
  t.big = t.b[0] == 'M';
  ifd = PVTiffInt (&t, 4, 4);
  n = PVTiffInt (&t, ifd, 2);
  for (i = 0; i < n && ifd + 2 + 12 * (i + 1) <= t.len; i++)
    {
      unsigned char *e = (unsigned char *) t.b + ifd + 2 + 12 * i;

      if (PVTiffInt (&t, ifd + 2 + 12 * i, 2) == 0x0112)
        {
          e[8] = t.big ? 0 : 1;
          e[9] = t.big ? 1 : 0;
        }
    }
  /* After the JFIF segment, where there is one. */
  if (len >= 6 && j[2] == 0xFF && j[3] == 0xE0)
    at = 4 + ((j[4] << 8) | j[5]);
  out = [NSMutableData dataWithBytes: j length: at];
  [out appendData: exif];
  [out appendBytes: j + at length: len - at];
  return out;
}

/* ---- reading and writing ---- */

+ (NSBitmapImageRep *) readBitmapAtPath: (NSString *)path
{
  NSData *data = [NSData dataWithContentsOfFile: path];
  NSBitmapImageRep *rep = nil;
  NSArray *reps;
  int orientation;

  if (data == nil)
    return nil;
  NS_DURING
    {
      reps = [NSBitmapImageRep imageRepsWithData: data];
      if ([reps count] > 0)
        rep = [reps objectAtIndex: 0];
    }
  NS_HANDLER
    rep = nil;
  NS_ENDHANDLER
  if (rep == nil || ![rep isKindOfClass: [NSBitmapImageRep class]]
      || [rep pixelsWide] <= 0 || [rep pixelsHigh] <= 0)
    rep = PVReadBMP (data);
  if (rep == nil)
    return nil;
  if ([rep size].width <= 0 || [rep size].height <= 0)
    [rep setSize: NSMakeSize ([rep pixelsWide], [rep pixelsHigh])];
  /* Cameras save the picture as the sensor saw it and say which way is
     up: 3 upside down, 6 a quarter turn clockwise, 8 anticlockwise. */
  orientation = [[[self exifAtPath: path] objectForKey: @"Orientation"]
                  intValue];
  if (orientation == 3)
    rep = [self bitmap: rep rotated: 2];
  else if (orientation == 6)
    rep = [self bitmap: rep rotated: 1];
  else if (orientation == 8)
    rep = [self bitmap: rep rotated: 3];
  return rep;
}

+ (PVFormat) formatForPath: (NSString *)path
{
  NSString *e = [[path pathExtension] lowercaseString];

  if ([e isEqual: @"png"])
    return PVFormatPNG;
  if ([e isEqual: @"jpg"] || [e isEqual: @"jpeg"] || [e isEqual: @"jpe"])
    return PVFormatJPEG;
  if ([e isEqual: @"tif"] || [e isEqual: @"tiff"])
    return PVFormatTIFF;
  if ([e isEqual: @"pdf"])
    return PVFormatPDF;
  if ([e isEqual: @"gif"])
    return PVFormatGIF;
  if ([e isEqual: @"bmp"])
    return PVFormatBMP;
  return PVFormatOther;
}

+ (NSString *) formatName: (NSString *)path
{
  switch ([self formatForPath: path])
    {
    case PVFormatJPEG: return @"JPEG";
    case PVFormatTIFF: return @"TIFF";
    default: return [[path pathExtension] uppercaseString];
    }
}

+ (NSString *) extensionForFormat: (PVFormat)format
{
  switch (format)
    {
    case PVFormatPNG: return @"png";
    case PVFormatJPEG: return @"jpg";
    case PVFormatTIFF: return @"tiff";
    case PVFormatPDF: return @"pdf";
    case PVFormatGIF: return @"gif";
    case PVFormatBMP: return @"bmp";
    default: return nil;
    }
}

+ (NSData *) dataForBitmap: (NSBitmapImageRep *)rep format: (PVFormat)format
                   quality: (float)quality
{
  NSData *data = nil;

  NS_DURING
    {
      switch (format)
        {
        case PVFormatPNG:
          data = [rep representationUsingType: NSPNGFileType
                                   properties: [NSDictionary dictionary]];
          break;
        case PVFormatJPEG:
          data = [PVOpaqueRGB (rep)
                   representationUsingType: NSJPEGFileType
                                properties:
                     [NSDictionary dictionaryWithObject:
                                     [NSNumber numberWithFloat: quality]
                                                 forKey: NSImageCompressionFactor]];
          break;
        case PVFormatTIFF:
          data = [rep TIFFRepresentation];
          break;
        case PVFormatGIF:
          data = [PVOpaqueRGB (rep)
                   representationUsingType: NSGIFFileType
                                properties: [NSDictionary dictionary]];
          break;
        case PVFormatBMP:
          data = PVWriteBMP (rep);
          break;
        case PVFormatPDF:
          data = PVWritePDF (rep);
          break;
        default:
          data = nil;
        }
    }
  NS_HANDLER
    data = nil;
  NS_ENDHANDLER
  return [data length] > 0 ? data : nil;
}

@end
