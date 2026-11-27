/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PVStyle.h"
#import <GNUstepGUI/GSTheme.h>

NSString *const PVStyleChangedNotification = @"PVStyleChanged";

static BOOL light = NO;
static BOOL haveRead = NO;

#define PICK(d, l) ([PVStyle light] ? (l) : (d))

@implementation PVStyle

+ (void) reload
{
  NSArray *allowed = [NSArray arrayWithObjects: @"dark", @"light", nil];
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  id v;

  [defs synchronize];
  v = [[defs persistentDomainForName: NSGlobalDomain]
        objectForKey: @"NBAppearance"];
  if (![allowed containsObject: v])
    v = [defs objectForKey: @"NBAppearance"];
  if (![allowed containsObject: v])
    v = [[[GSTheme theme] infoDictionary] objectForKey: @"NBAppearance"];
  light = [v isEqual: @"light"];
  haveRead = YES;
}

+ (BOOL) light
{
  if (!haveRead)
    [self reload];
  return light;
}

+ (NSColor *) rgb: (unsigned)v alpha: (CGFloat)a
{
  return [NSColor colorWithCalibratedRed: ((v >> 16) & 255) / 255.0
                                   green: ((v >> 8) & 255) / 255.0
                                    blue: (v & 255) / 255.0
                                   alpha: a];
}

+ (NSColor *) window { return PICK ([self rgb: 0x1c1e23 alpha: 1], [self rgb: 0xf7f7f9 alpha: 1]); }
+ (NSColor *) bar { return PICK ([self rgb: 0x24272d alpha: 1], [self rgb: 0xe8e9ed alpha: 1]); }
+ (NSColor *) sidebar { return PICK ([self rgb: 0x202227 alpha: 1], [self rgb: 0xeef0f3 alpha: 1]); }
+ (NSColor *) backdrop { return PICK ([self rgb: 0x15171b alpha: 1], [self rgb: 0xdfe2e7 alpha: 1]); }
+ (NSColor *) line { return PICK ([self rgb: 0xffffff alpha: .09], [self rgb: 0x000000 alpha: .10]); }
+ (NSColor *) text { return PICK ([self rgb: 0xe9ebef alpha: 1], [self rgb: 0x1d1f24 alpha: 1]); }
+ (NSColor *) dim { return PICK ([self rgb: 0x9aa0ac alpha: 1], [self rgb: 0x5f6470 alpha: 1]); }
+ (NSColor *) faint { return PICK ([self rgb: 0x6b7180 alpha: 1], [self rgb: 0x8d929c alpha: 1]); }
+ (NSColor *) accent { return PICK ([self rgb: 0x00d4ff alpha: 1], [self rgb: 0x00a3c7 alpha: 1]); }
+ (NSColor *) accentText { return PICK ([self rgb: 0x04141a alpha: 1], [self rgb: 0xffffff alpha: 1]); }
+ (NSColor *) selection { return PICK ([self rgb: 0x00d4ff alpha: .18], [self rgb: 0x00a3c7 alpha: .16]); }
+ (NSColor *) field { return PICK ([self rgb: 0x121418 alpha: 1], [self rgb: 0xffffff alpha: 1]); }

+ (NSFont *) fontOfSize: (CGFloat)size bold: (BOOL)bold
{
  NSFont *f = bold ? [NSFont boldSystemFontOfSize: size]
    : [NSFont systemFontOfSize: size];

  return f != nil ? f : [NSFont userFontOfSize: size];
}

/* ---- glyphs ---- */

/* An arc as SVG's "a" draws it (a circle, rx = ry = r), from the path's
   current point to (x, y), in a flipped grid. */
static void
PVArc (NSBezierPath *p, CGFloat r, BOOL large, BOOL sweep, CGFloat x,
       CGFloat y)
{
  NSPoint from = [p currentPoint];
  CGFloat dx = (x - from.x) / 2, dy = (y - from.y) / 2;
  CGFloat d2 = dx * dx + dy * dy, h, cx, cy, a0, a1;

  if (d2 <= 0)
    return;
  if (d2 > r * r)
    r = sqrt (d2);
  h = sqrt (MAX (r * r - d2, 0)) / sqrt (d2);
  /* The centre is to one side of the chord's middle. */
  if (large == sweep)
    h = -h;
  cx = from.x + dx - h * dy;
  cy = from.y + dy + h * dx;
  a0 = atan2 (from.y - cy, from.x - cx) * 180 / M_PI;
  a1 = atan2 (y - cy, x - cx) * 180 / M_PI;
  /* In a flipped grid, clockwise on screen is the angle going up. */
  [p appendBezierPathWithArcWithCenter: NSMakePoint (cx, cy) radius: r
                            startAngle: a0 endAngle: a1 clockwise: !sweep];
}

static NSBezierPath *
PVParsePath (NSString *svg)
{
  NSBezierPath *p = [NSBezierPath bezierPath];
  const char *s = [svg UTF8String];
  char command = 'M';
  NSPoint cur = NSZeroPoint, start = NSZeroPoint;
  double v[7];
  int need, i;

  while (*s != '\0')
    {
      while (*s == ' ' || *s == ',')
        s++;
      if (*s == '\0')
        break;
      if (strchr ("MmLlHhVvCcAaZz", *s) != NULL)
        {
          command = *s++;
          if (command == 'Z' || command == 'z')
            {
              [p closePath];
              cur = start;
              continue;
            }
          continue;
        }
      switch (command)
        {
        case 'H': case 'h': case 'V': case 'v': need = 1; break;
        case 'C': case 'c': need = 6; break;
        case 'A': case 'a': need = 7; break;
        default: need = 2; break;
        }
      for (i = 0; i < need; i++)
        {
          char *end;

          while (*s == ' ' || *s == ',')
            s++;
          v[i] = strtod (s, &end);
          if (end == s)
            return p;
          s = end;
        }
      switch (command)
        {
        case 'M': case 'm':
          if (command == 'm')
            cur = NSMakePoint (cur.x + v[0], cur.y + v[1]);
          else
            cur = NSMakePoint (v[0], v[1]);
          [p moveToPoint: cur];
          start = cur;
          /* Pairs after a move are lines. */
          command = (command == 'm') ? 'l' : 'L';
          break;
        case 'L': cur = NSMakePoint (v[0], v[1]); [p lineToPoint: cur]; break;
        case 'l':
          cur = NSMakePoint (cur.x + v[0], cur.y + v[1]);
          [p lineToPoint: cur];
          break;
        case 'H': cur.x = v[0]; [p lineToPoint: cur]; break;
        case 'h': cur.x += v[0]; [p lineToPoint: cur]; break;
        case 'V': cur.y = v[0]; [p lineToPoint: cur]; break;
        case 'v': cur.y += v[0]; [p lineToPoint: cur]; break;
        case 'C': case 'c':
          {
            CGFloat ox = command == 'c' ? cur.x : 0;
            CGFloat oy = command == 'c' ? cur.y : 0;

            [p curveToPoint: NSMakePoint (ox + v[4], oy + v[5])
              controlPoint1: NSMakePoint (ox + v[0], oy + v[1])
              controlPoint2: NSMakePoint (ox + v[2], oy + v[3])];
            cur = NSMakePoint (ox + v[4], oy + v[5]);
            break;
          }
        case 'A': case 'a':
          {
            CGFloat x = v[5], y = v[6];

            if (command == 'a')
              {
                x += cur.x;
                y += cur.y;
              }
            PVArc (p, v[0], v[3] != 0, v[4] != 0, x, y);
            cur = NSMakePoint (x, y);
            break;
          }
        }
    }
  return p;
}

+ (void) strokeGlyph: (NSString *)svg inRect: (NSRect)rect
               color: (NSColor *)color width: (CGFloat)width
{
  static NSMutableDictionary *cache = nil;
  NSBezierPath *path;
  NSAffineTransform *t = [NSAffineTransform transform];
  CGFloat s = rect.size.width / 24.0;

  if (cache == nil)
    cache = [[NSMutableDictionary alloc] init];
  path = [cache objectForKey: svg];
  if (path == nil)
    {
      path = PVParsePath (svg);
      [cache setObject: path forKey: svg];
    }
  path = [[path copy] autorelease];
  [t translateXBy: rect.origin.x yBy: rect.origin.y];
  [t scaleBy: s];
  [path transformUsingAffineTransform: t];
  [path setLineWidth: width * s];
  [path setLineCapStyle: NSRoundLineCapStyle];
  [path setLineJoinStyle: NSRoundLineJoinStyle];
  [color set];
  [path stroke];
}

/* ---- text ---- */

+ (void) drawText: (NSString *)s at: (NSPoint)point font: (NSFont *)font
            color: (NSColor *)color
{
  NSDictionary *a = [NSDictionary dictionaryWithObjectsAndKeys:
                                    font, NSFontAttributeName,
                                  color, NSForegroundColorAttributeName,
                                  nil];

  [s drawAtPoint: point withAttributes: a];
}

+ (NSSize) sizeOfText: (NSString *)s font: (NSFont *)font
{
  return [s sizeWithAttributes:
              [NSDictionary dictionaryWithObject: font
                                          forKey: NSFontAttributeName]];
}

+ (NSString *) text: (NSString *)s fitting: (CGFloat)width
               font: (NSFont *)font
{
  NSUInteger n;

  if ([self sizeOfText: s font: font].width <= width)
    return s;
  for (n = [s length]; n > 1; n--)
    {
      NSString *t = [[s substringToIndex: n - 1]
                      stringByAppendingString: @"…"];

      if ([self sizeOfText: t font: font].width <= width)
        return t;
    }
  return @"…";
}

+ (void) drawImage: (NSImage *)image inRect: (NSRect)rect
{
  NSAffineTransform *t = [NSAffineTransform transform];

  /* GNUstep draws an image upside down in a flipped view: flip it back
     around the rectangle. */
  [NSGraphicsContext saveGraphicsState];
  [t translateXBy: NSMinX (rect) yBy: NSMaxY (rect)];
  [t scaleXBy: 1 yBy: -1];
  [t concat];
  [image drawInRect: NSMakeRect (0, 0, rect.size.width, rect.size.height)
           fromRect: NSZeroRect operation: NSCompositeSourceOver
           fraction: 1.0];
  [NSGraphicsContext restoreGraphicsState];
}

+ (NSString *) sizeString: (long long)bytes
{
  if (bytes <= 0)
    return @"Zero KB";
  if (bytes < 1000 * 1000)
    return [NSString stringWithFormat: @"%lld KB",
                     (bytes + 999) / 1000];
  if (bytes < 1000LL * 1000 * 1000)
    return [NSString stringWithFormat: @"%.1f MB", bytes / 1e6];
  return [NSString stringWithFormat: @"%.2f GB", bytes / 1e9];
}

@end
