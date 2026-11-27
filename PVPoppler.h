/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PVPoppler: the PDF side of Preview, as plain C over poppler-cpp
 * (PVPoppler.cc), so the Objective-C never sees C++.
 *
 * Every rectangle is in PDF points with its origin at the top left of the
 * page as it is shown: the page's own /Rotate and the rotation asked for
 * (a quarter turn clockwise for each step) already applied.
 */

#ifndef _PV_POPPLER_H_
#define _PV_POPPLER_H_

#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PVPDF PVPDF;

typedef struct
{
  double x, y, w, h;
} PVRect;

/* The glyphs of a page in reading order. flags: PVGlyphSpace when a
   space follows the glyph, PVGlyphLine when the line ends after it. */
enum
{
  PVGlyphSpace = 1,
  PVGlyphLine = 2
};

typedef struct
{
  int count;
  unsigned short *chars;	/* UTF-16 */
  PVRect *rects;
  unsigned char *flags;
} PVText;

/* NULL when the file isn't a PDF poppler can read; *locked is set when it
   is encrypted with a password. */
PVPDF *PVPDFOpen (const char *path, int *locked);
void PVPDFClose (PVPDF *pdf);

int PVPDFPageCount (PVPDF *pdf);

/* The page's size in points, as shown (its /Rotate applied). */
void PVPDFPageSize (PVPDF *pdf, int page, double *width, double *height);

/* Renders the page at dpi, turned quarters (0-3) clockwise: RGB, 3 bytes
   a pixel, rows of *stride bytes, from malloc (free it). NULL on
   failure. */
unsigned char *PVPDFRender (PVPDF *pdf, int page, double dpi, int quarters,
                            int *width, int *height, int *stride);

/* The document's Title, Author, Producer, Creator ... as UTF-8 from
   malloc, or NULL when it has none. */
char *PVPDFInfo (PVPDF *pdf, const char *key);
/* CreationDate or ModDate; 0 when it has none. */
time_t PVPDFDate (PVPDF *pdf, const char *key);

/* The page's text, with the page unturned. 0 on success. */
int PVPDFText (PVPDF *pdf, int page, PVText *text);
void PVTextFree (PVText *text);

/* Every match for utf8 on the page, ignoring case, unturned; *rects from
   malloc. Returns how many. */
int PVPDFSearch (PVPDF *pdf, int page, const char *utf8, PVRect **rects);

#ifdef __cplusplus
}
#endif

#endif
