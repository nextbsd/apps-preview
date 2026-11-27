/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PVPoppler over poppler-cpp (libpoppler-cpp, from NextBSD-gnustep-support).
 */

#include "PVPoppler.h"

#include <poppler/cpp/poppler-document.h>
#include <poppler/cpp/poppler-global.h>
#include <poppler/cpp/poppler-image.h>
#include <poppler/cpp/poppler-page.h>
#include <poppler/cpp/poppler-page-renderer.h>

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

struct PVPDF
{
  poppler::document *doc;
  std::vector<poppler::page *> pages;
};

static void
PVQuiet (const std::string &, void *)
{
  /* poppler's complaints about damaged files go nowhere. */
}

static poppler::page *
PVPage (PVPDF *pdf, int index)
{
  if (pdf == NULL || index < 0 || index >= (int) pdf->pages.size ())
    return NULL;
  if (pdf->pages[index] == NULL)
    pdf->pages[index] = pdf->doc->create_page (index);
  return pdf->pages[index];
}

static char *
PVCopyUString (const poppler::ustring &s)
{
  poppler::byte_array bytes = s.to_utf8 ();
  char *out;

  if (bytes.empty ())
    return NULL;
  out = (char *) malloc (bytes.size () + 1);
  if (out == NULL)
    return NULL;
  memcpy (out, &bytes[0], bytes.size ());
  out[bytes.size ()] = '\0';
  return out;
}

/* Quarter turns of the page's own /Rotate. */
static int
PVOwnQuarters (poppler::page *p)
{
  switch (p->orientation ())
    {
    case poppler::page::landscape: return 1;
    case poppler::page::upside_down: return 2;
    case poppler::page::seascape: return 3;
    default: return 0;
    }
}

extern "C" PVPDF *
PVPDFOpen (const char *path, int *locked)
{
  poppler::document *doc;
  PVPDF *pdf;

  poppler::set_debug_error_function (PVQuiet, NULL);
  if (locked != NULL)
    *locked = 0;
  doc = poppler::document::load_from_file (path);
  if (doc == NULL)
    return NULL;
  if (doc->is_locked ())
    {
      if (locked != NULL)
        *locked = 1;
      delete doc;
      return NULL;
    }
  pdf = new PVPDF;
  pdf->doc = doc;
  pdf->pages.assign (doc->pages () > 0 ? doc->pages () : 0, NULL);
  return pdf;
}

extern "C" void
PVPDFClose (PVPDF *pdf)
{
  if (pdf == NULL)
    return;
  for (size_t i = 0; i < pdf->pages.size (); i++)
    delete pdf->pages[i];
  delete pdf->doc;
  delete pdf;
}

extern "C" int
PVPDFPageCount (PVPDF *pdf)
{
  return pdf != NULL ? (int) pdf->pages.size () : 0;
}

extern "C" void
PVPDFPageSize (PVPDF *pdf, int index, double *width, double *height)
{
  poppler::page *p = PVPage (pdf, index);
  poppler::rectf r;

  *width = 612;
  *height = 792;
  if (p == NULL)
    return;
  r = p->page_rect (poppler::crop_box);
  if (r.width () <= 0 || r.height () <= 0)
    return;
  if (PVOwnQuarters (p) % 2 == 1)
    {
      *width = fabs (r.height ());
      *height = fabs (r.width ());
    }
  else
    {
      *width = fabs (r.width ());
      *height = fabs (r.height ());
    }
}

extern "C" unsigned char *
PVPDFRender (PVPDF *pdf, int index, double dpi, int quarters, int *width,
             int *height, int *stride)
{
  static const poppler::rotation_enum turns[] = {
    poppler::rotate_0, poppler::rotate_90, poppler::rotate_180,
    poppler::rotate_270
  };
  poppler::page *p = PVPage (pdf, index);
  poppler::page_renderer renderer;
  poppler::image image;
  unsigned char *out;
  int w, h, row, x, y;

  if (p == NULL || !poppler::page_renderer::can_render ())
    return NULL;
  renderer.set_render_hints (poppler::page_renderer::antialiasing
                             | poppler::page_renderer::text_antialiasing
                             | poppler::page_renderer::text_hinting);
  renderer.set_image_format (poppler::image::format_argb32);
  renderer.set_paper_color (0xffffffff);
  image = renderer.render_page (p, dpi, dpi, -1, -1, -1, -1,
                                turns[((quarters % 4) + 4) % 4]);
  if (!image.is_valid () || image.format () != poppler::image::format_argb32)
    return NULL;
  w = image.width ();
  h = image.height ();
  if (w <= 0 || h <= 0)
    return NULL;
  row = w * 3;
  out = (unsigned char *) malloc ((size_t) row * h);
  if (out == NULL)
    return NULL;
  /* argb32 is a native-endian 0xAARRGGBB word a pixel; the paper is
     opaque, so the colour is already the colour. */
  for (y = 0; y < h; y++)
    {
      const unsigned int *from = (const unsigned int *)
        (image.const_data () + (size_t) y * image.bytes_per_row ());
      unsigned char *to = out + (size_t) y * row;

      for (x = 0; x < w; x++)
        {
          unsigned int v = from[x];

          to[3 * x] = (v >> 16) & 255;
          to[3 * x + 1] = (v >> 8) & 255;
          to[3 * x + 2] = v & 255;
        }
    }
  *width = w;
  *height = h;
  *stride = row;
  return out;
}

extern "C" char *
PVPDFInfo (PVPDF *pdf, const char *key)
{
  if (pdf == NULL)
    return NULL;
  return PVCopyUString (pdf->doc->info_key (key));
}

extern "C" time_t
PVPDFDate (PVPDF *pdf, const char *key)
{
  time_t t;

  if (pdf == NULL)
    return 0;
  t = pdf->doc->info_date_t (key);
  return t == (time_t) -1 ? 0 : t;
}

static PVRect
PVFromRect (const poppler::rectf &r)
{
  PVRect out;

  out.x = r.left ();
  out.y = r.top ();
  out.w = r.width ();
  out.h = r.height ();
  return out;
}

extern "C" int
PVPDFText (PVPDF *pdf, int index, PVText *text)
{
  poppler::page *p = PVPage (pdf, index);
  std::vector<poppler::text_box> boxes;
  size_t total = 0, i, j;
  int n = 0;

  memset (text, 0, sizeof (*text));
  if (p == NULL)
    return -1;
  boxes = p->text_list ();
  for (i = 0; i < boxes.size (); i++)
    total += boxes[i].text ().size ();
  if (total == 0)
    return 0;
  text->chars = (unsigned short *) calloc (total, sizeof (unsigned short));
  text->rects = (PVRect *) calloc (total, sizeof (PVRect));
  text->flags = (unsigned char *) calloc (total, 1);
  if (text->chars == NULL || text->rects == NULL || text->flags == NULL)
    {
      PVTextFree (text);
      return -1;
    }
  for (i = 0; i < boxes.size (); i++)
    {
      poppler::ustring s = boxes[i].text ();
      poppler::rectf box = boxes[i].bbox ();

      for (j = 0; j < s.size (); j++)
        {
          poppler::rectf r = boxes[i].char_bbox (j);

          /* A ligature is one glyph and two letters: share its box. */
          if (r.width () <= 0 && r.height () <= 0)
            r = box;
          text->chars[n] = (unsigned short) s[j];
          text->rects[n] = PVFromRect (r);
          text->flags[n] = 0;
          n++;
        }
      if (n == 0 || s.size () == 0)
        continue;
      if (i + 1 < boxes.size ())
        {
          poppler::rectf next = boxes[i + 1].bbox ();
          double mid = box.top () + box.height () / 2;
          double nextMid = next.top () + next.height () / 2;
          double tall = box.height () > next.height () ? box.height ()
            : next.height ();

          /* The next word starts another line when it is lower or
             higher by more than half a line, or back to the left. */
          if (fabs (nextMid - mid) > tall / 2
              || next.left () < box.left () - tall)
            text->flags[n - 1] |= PVGlyphLine;
          else if (boxes[i].has_space_after ())
            text->flags[n - 1] |= PVGlyphSpace;
        }
    }
  text->count = n;
  return 0;
}

extern "C" void
PVTextFree (PVText *text)
{
  free (text->chars);
  free (text->rects);
  free (text->flags);
  memset (text, 0, sizeof (*text));
}

extern "C" int
PVPDFSearch (PVPDF *pdf, int index, const char *utf8, PVRect **rects)
{
  poppler::page *p = PVPage (pdf, index);
  poppler::ustring what;
  poppler::rectf r;
  std::vector<PVRect> found;
  int guard = 0;

  *rects = NULL;
  if (p == NULL || utf8 == NULL || utf8[0] == '\0')
    return 0;
  what = poppler::ustring::from_utf8 (utf8);
  if (!p->search (what, r, poppler::page::search_from_top,
                  poppler::case_insensitive))
    return 0;
  do
    {
      PVRect m = PVFromRect (r);

      /* poppler can find the same match again at the end. */
      if (!found.empty ()
          && fabs (found.back ().x - m.x) < 0.01
          && fabs (found.back ().y - m.y) < 0.01)
        break;
      found.push_back (m);
    }
  while (++guard < 10000
         && p->search (what, r, poppler::page::search_next_result,
                       poppler::case_insensitive));
  *rects = (PVRect *) malloc (found.size () * sizeof (PVRect));
  if (*rects == NULL)
    return 0;
  memcpy (*rects, &found[0], found.size () * sizeof (PVRect));
  return (int) found.size ();
}
