/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PVPDFDocument.h"
#import "PVImage.h"

/* How many rendered pages are kept, and the thumbnails' width. */
#define PVKeptRenders 10
#define PVThumbWidth 84.0

@implementation PVMatch
@end

@implementation PVPageText

- (void) dealloc
{
  PVTextFree (&text);
  [super dealloc];
}

- (int) glyphNearest: (NSPoint)p
{
  double best = 1e30;
  int i, found = -1;

  for (i = 0; i < text.count; i++)
    {
      PVRect r = text.rects[i];
      double dx = 0, dy = 0, d;

      if (p.x < r.x)
        dx = r.x - p.x;
      else if (p.x > r.x + r.w)
        dx = p.x - (r.x + r.w);
      if (p.y < r.y)
        dy = r.y - p.y;
      else if (p.y > r.y + r.h)
        dy = p.y - (r.y + r.h);
      /* Lines first: being on the line matters more than how far along. */
      d = dx + 4 * dy;
      if (d < best)
        {
          best = d;
          found = i;
          if (d == 0)
            break;
        }
    }
  return found;
}

- (NSString *) stringFrom: (int)from to: (int)to
{
  NSMutableString *s = [NSMutableString string];
  int i;

  if (from > to)
    {
      i = from;
      from = to;
      to = i;
    }
  if (from < 0)
    from = 0;
  if (to >= text.count)
    to = text.count - 1;
  for (i = from; i <= to; i++)
    {
      unichar c = text.chars[i];

      [s appendString: [NSString stringWithCharacters: &c length: 1]];
      if (i < to)
        {
          if (text.flags[i] & PVGlyphLine)
            [s appendString: @"\n"];
          else if (text.flags[i] & PVGlyphSpace)
            [s appendString: @" "];
        }
    }
  return s;
}

@end

@implementation PVPDFDocument

+ (PVPDFDocument *) documentWithPath: (NSString *)p locked: (BOOL *)locked
{
  int isLocked = 0;
  PVPDF *pdf = PVPDFOpen ([p fileSystemRepresentation], &isLocked);
  PVPDFDocument *d;
  int i;

  if (locked != NULL)
    *locked = isLocked != 0;
  if (pdf == NULL)
    return nil;
  if (PVPDFPageCount (pdf) <= 0)
    {
      PVPDFClose (pdf);
      return nil;
    }
  d = AUTORELEASE ([[PVPDFDocument alloc] init]);
  d->pdf = pdf;
  d->path = [p copy];
  d->pages = PVPDFPageCount (pdf);
  d->sizes = calloc (d->pages, sizeof (NSSize));
  for (i = 0; i < d->pages; i++)
    {
      double w, h;

      PVPDFPageSize (pdf, i, &w, &h);
      d->sizes[i] = NSMakeSize (w, h);
    }
  d->renders = [[NSMutableDictionary alloc] init];
  d->renderOrder = [[NSMutableArray alloc] init];
  d->thumbs = [[NSMutableDictionary alloc] init];
  d->texts = [[NSMutableDictionary alloc] init];
  return d;
}

- (void) dealloc
{
  PVPDFClose (pdf);
  free (sizes);
  RELEASE (path);
  RELEASE (renders);
  RELEASE (renderOrder);
  RELEASE (thumbs);
  RELEASE (texts);
  [super dealloc];
}

- (NSString *) path
{
  return path;
}

- (int) pageCount
{
  return pages;
}

- (NSSize) unturnedSizeOfPage: (int)page
{
  if (page < 0 || page >= pages)
    return NSMakeSize (612, 792);
  return sizes[page];
}

- (NSSize) sizeOfPage: (int)page
{
  NSSize s = [self unturnedSizeOfPage: page];

  return (rotation % 2) ? NSMakeSize (s.height, s.width) : s;
}

- (int) rotation
{
  return rotation;
}

- (void) setRotation: (int)q
{
  q = ((q % 4) + 4) % 4;
  if (q == rotation)
    return;
  rotation = q;
  [renders removeAllObjects];
  [renderOrder removeAllObjects];
  [thumbs removeAllObjects];
}

- (NSBitmapImageRep *) render: (int)page dpi: (double)dpi
{
  unsigned char *rgb;
  int w, h, stride;
  NSBitmapImageRep *rep;
  NSSize s = [self sizeOfPage: page];

  rgb = PVPDFRender (pdf, page, dpi, rotation, &w, &h, &stride);
  if (rgb == NULL)
    return nil;
  rep = [PVImage bitmapWithRGB: rgb width: w height: h stride: stride];
  free (rgb);
  [rep setSize: s];
  return rep;
}

- (NSBitmapImageRep *) renderPage: (int)page dpi: (double)dpi
{
  NSString *key;
  NSBitmapImageRep *rep;

  if (page < 0 || page >= pages)
    return nil;
  key = [NSString stringWithFormat: @"%d %.1f", page, dpi];
  rep = [renders objectForKey: key];
  if (rep != nil)
    {
      [renderOrder removeObject: key];
      [renderOrder addObject: key];
      return rep;
    }
  rep = [self render: page dpi: dpi];
  if (rep == nil)
    return nil;
  [renders setObject: rep forKey: key];
  [renderOrder addObject: key];
  while ([renderOrder count] > PVKeptRenders)
    {
      [renders removeObjectForKey: [renderOrder objectAtIndex: 0]];
      [renderOrder removeObjectAtIndex: 0];
    }
  return rep;
}

- (BOOL) hasThumbnailOfPage: (int)page
{
  return [thumbs objectForKey: [NSNumber numberWithInt: page]] != nil;
}

- (NSBitmapImageRep *) thumbnailOfPage: (int)page
{
  NSNumber *key = [NSNumber numberWithInt: page];
  NSBitmapImageRep *rep = [thumbs objectForKey: key];
  NSSize s;

  if (rep != nil || page < 0 || page >= pages)
    return rep;
  s = [self sizeOfPage: page];
  /* Twice the size it is drawn, for a sharp thumbnail. */
  rep = [self render: page dpi: 72.0 * 2 * PVThumbWidth / MAX (s.width, 1)];
  if (rep != nil)
    [thumbs setObject: rep forKey: key];
  return rep;
}

- (PVPageText *) textOfPage: (int)page
{
  NSNumber *key = [NSNumber numberWithInt: page];
  PVPageText *t = [texts objectForKey: key];

  if (t != nil || page < 0 || page >= pages)
    return t;
  t = AUTORELEASE ([[PVPageText alloc] init]);
  PVPDFText (pdf, page, &t->text);
  [texts setObject: t forKey: key];
  return t;
}

- (NSArray *) search: (NSString *)query
{
  NSMutableArray *found = [NSMutableArray array];
  const char *q = [query UTF8String];
  int page, i, n;

  if ([query length] == 0)
    return found;
  for (page = 0; page < pages; page++)
    {
      PVRect *rects = NULL;

      n = PVPDFSearch (pdf, page, q, &rects);
      for (i = 0; i < n; i++)
        {
          PVMatch *m = AUTORELEASE ([[PVMatch alloc] init]);

          m->page = page;
          m->rect = NSMakeRect (rects[i].x, rects[i].y, rects[i].w,
                                rects[i].h);
          [found addObject: m];
        }
      free (rects);
    }
  return found;
}

- (NSPoint) turnPoint: (NSPoint)p size: (NSSize)s
{
  switch (rotation)
    {
    case 1: return NSMakePoint (s.height - p.y, p.x);
    case 2: return NSMakePoint (s.width - p.x, s.height - p.y);
    case 3: return NSMakePoint (p.y, s.width - p.x);
    default: return p;
    }
}

- (NSRect) turnRect: (NSRect)r onPage: (int)page
{
  NSSize s = [self unturnedSizeOfPage: page];
  NSPoint a = [self turnPoint: r.origin size: s];
  NSPoint b = [self turnPoint: NSMakePoint (NSMaxX (r), NSMaxY (r)) size: s];

  return NSMakeRect (MIN (a.x, b.x), MIN (a.y, b.y), fabs (a.x - b.x),
                     fabs (a.y - b.y));
}

- (NSPoint) unturnPoint: (NSPoint)p onPage: (int)page
{
  NSSize s = [self unturnedSizeOfPage: page];

  switch (rotation)
    {
    case 1: return NSMakePoint (p.y, s.height - p.x);
    case 2: return NSMakePoint (s.width - p.x, s.height - p.y);
    case 3: return NSMakePoint (s.width - p.y, p.x);
    default: return p;
    }
}

- (NSString *) infoForKey: (NSString *)key
{
  char *v = PVPDFInfo (pdf, [key UTF8String]);
  NSString *s;

  if (v == NULL)
    return nil;
  s = [NSString stringWithUTF8String: v];
  free (v);
  s = [s stringByTrimmingCharactersInSet:
           [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return [s length] > 0 ? s : nil;
}

- (NSDate *) creationDate
{
  time_t t = PVPDFDate (pdf, "CreationDate");

  return t > 0 ? [NSDate dateWithTimeIntervalSince1970: t] : nil;
}

@end

NSString *
PVPaperDescription (NSSize p)
{
  static const struct
  {
    const char *name;
    double w, h;		/* points */
    BOOL metric;
  } papers[] = {
    { "Letter", 612, 792, NO }, { "Legal", 612, 1008, NO },
    { "Tabloid", 792, 1224, NO }, { "A3", 841.9, 1190.6, YES },
    { "A4", 595.3, 841.9, YES }, { "A5", 419.5, 595.3, YES },
    { "B5", 498.9, 708.7, YES }
  };
  double w = MIN (p.width, p.height), h = MAX (p.width, p.height);
  unsigned i;

  for (i = 0; i < sizeof (papers) / sizeof (papers[0]); i++)
    if (fabs (papers[i].w - w) < 3 && fabs (papers[i].h - h) < 3)
      {
        NSString *name = [NSString stringWithUTF8String: papers[i].name];
        double a = p.width, b = p.height;

        if (papers[i].metric)
          return [NSString stringWithFormat: @"%@ · %.0f × %.0f mm", name,
                           a / 72 * 25.4, b / 72 * 25.4];
        return [NSString stringWithFormat: @"%@ · %g × %g in", name,
                         round (a / 72 * 100) / 100,
                         round (b / 72 * 100) / 100];
      }
  return [NSString stringWithFormat: @"%g × %g in",
                   round (p.width / 72 * 100) / 100,
                   round (p.height / 72 * 100) / 100];
}
