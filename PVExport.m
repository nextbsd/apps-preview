/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PVExport.h"
#import "PVImage.h"
#import "PVStyle.h"
#import <GNUstepBase/GNUstep.h>

#define PVWidth 460
#define PVLabelWidth 90

@implementation PVExport

- (void) dealloc
{
  [NSObject cancelPreviousPerformRequestsWithTarget: self];
  RELEASE (panel);
  RELEASE (folders);
  RELEASE (bitmap);
  RELEASE (pdfPath);
  RELEASE (pageLabel);
  RELEASE (sourcePath);
  [super dealloc];
}

static NSTextField *
PVText (NSRect frame, NSString *s, NSColor *color, NSTextAlignment align)
{
  NSTextField *t = AUTORELEASE ([[NSTextField alloc] initWithFrame: frame]);

  [t setStringValue: s];
  [t setEditable: NO];
  [t setSelectable: NO];
  [t setBordered: NO];
  [t setBezeled: NO];
  [t setDrawsBackground: NO];
  [t setFont: [PVStyle fontOfSize: 12.5 bold: NO]];
  [t setTextColor: color];
  [t setAlignment: align];
  return t;
}

- (PVFormat) format
{
  return (PVFormat) [[formatPopup selectedItem] tag];
}

- (BOOL) copiesPDF
{
  return [self format] == PVFormatPDF && pdfPath != nil;
}

- (int) reduction
{
  return [sizePopup indexOfSelectedItem] == 1 ? 2 : 1;
}

- (NSString *) qualityWord
{
  float q = [qualitySlider floatValue];

  if (q < 0.35)
    return @"Low";
  if (q < 0.65)
    return @"Medium";
  if (q < 0.9)
    return @"High";
  return @"Best";
}

/* The bytes that would be saved. */
- (NSData *) data
{
  NSBitmapImageRep *rep = bitmap;

  if ([self copiesPDF])
    return [NSData dataWithContentsOfFile: pdfPath];
  if ([self reduction] > 1)
    rep = [PVImage bitmap: rep reducedBy: [self reduction]];
  return [PVImage dataForBitmap: rep format: [self format]
                        quality: [qualitySlider floatValue]];
}

- (void) updateEstimate
{
  NSData *d = [self data];
  long long n = [d length];

  if (d == nil)
    [estimate setStringValue: @"This can't be saved in that format."];
  else if ([self copiesPDF])
    [estimate setStringValue: [PVStyle sizeString: n]];
  else
    {
      NSString *s = n < 1000 * 1000
        ? [NSString stringWithFormat: @"About %@", [PVStyle sizeString: n]]
        : [NSString stringWithFormat: @"About %.1f MB", n / 1e6];

      /* A PDF's page as a picture: say which. */
      if (pdfPath != nil && pageLabel != nil)
        s = [NSString stringWithFormat: @"%@, %@ only", s,
                      [pageLabel lowercaseString]];
      [estimate setStringValue: s];
    }
}

- (void) changed: (id)sender
{
  BOOL jpeg = [self format] == PVFormatJPEG;
  NSString *name = [[nameField stringValue] stringByDeletingPathExtension];

  [qualitySlider setEnabled: jpeg];
  [qualityLabel setStringValue: jpeg ? [self qualityWord] : @""];
  [qualityLabel setTextColor: [PVStyle dim]];
  [sizePopup setEnabled: ![self copiesPDF]];
  if ([name length] > 0)
    {
      NSString *dir = [folders objectAtIndex:
                                 MIN ((NSUInteger) MAX (0, [wherePopup indexOfSelectedItem]),
                                      [folders count] - 1)];
      NSString *ext = [PVImage extensionForFormat: [self format]];

      /* Never the file itself: a copy beside it. */
      if ([[[dir stringByAppendingPathComponent:
                   [name stringByAppendingPathExtension: ext]]
             stringByStandardizingPath]
            isEqual: [sourcePath stringByStandardizingPath]])
        name = [name stringByAppendingString: @" copy"];
      [nameField setStringValue: [name stringByAppendingPathExtension: ext]];
    }
  [estimate setStringValue: @"Working out the size…"];
  [NSObject cancelPreviousPerformRequestsWithTarget: self
                                           selector: @selector(updateEstimate)
                                             object: nil];
  [self performSelector: @selector(updateEstimate) withObject: nil
             afterDelay: 0.15
                inModes: [NSArray arrayWithObjects: NSDefaultRunLoopMode,
                                  NSModalPanelRunLoopMode, nil]];
}

- (void) whereChanged: (id)sender
{
  NSInteger i = [wherePopup indexOfSelectedItem];

  /* The last item is Other… */
  if (i == [wherePopup numberOfItems] - 1)
    {
      NSOpenPanel *open = [NSOpenPanel openPanel];

      [open setCanChooseDirectories: YES];
      [open setCanChooseFiles: NO];
      [open setTitle: @"Where"];
      if ([open runModalForDirectory: [folders objectAtIndex: 0] file: nil
                               types: nil] == NSOKButton)
        {
          NSString *dir = [open filename];

          [folders insertObject: dir atIndex: 0];
          [wherePopup insertItemWithTitle: [dir lastPathComponent]
                                  atIndex: 0];
        }
      [wherePopup selectItemAtIndex: 0];
    }
}

- (void) cancel: (id)sender
{
  [NSApp stopModalWithCode: NSCancelButton];
}

- (void) export: (id)sender
{
  [NSApp stopModalWithCode: NSOKButton];
}

- (NSPopUpButton *) popup: (NSRect)frame
{
  NSPopUpButton *p = AUTORELEASE ([[NSPopUpButton alloc]
                                    initWithFrame: frame pullsDown: NO]);

  [p setTarget: self];
  [p setAction: @selector(changed:)];
  return p;
}

- (void) addRow: (NSString *)title y: (CGFloat)y to: (NSView *)content
{
  [content addSubview: PVText (NSMakeRect (20, y + 3, PVLabelWidth, 18),
                               title, [PVStyle dim], NSRightTextAlignment)];
}

- (void) buildWithName: (NSString *)name folder: (NSString *)folder
{
  NSView *content;
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *places = [NSArray arrayWithObjects: folder,
                             [NSHomeDirectory () stringByAppendingPathComponent: @"Desktop"],
                             [NSHomeDirectory () stringByAppendingPathComponent: @"Documents"],
                             [NSHomeDirectory () stringByAppendingPathComponent: @"Pictures"],
                             nil];
  CGFloat x = 20 + PVLabelWidth + 10, w = PVWidth - x - 20, y;
  CGFloat height = 300;
  PVFormat start;
  NSButton *button;
  NSUInteger i;
  int halfW = MAX (1, (int) [bitmap pixelsWide] / 2);
  int halfH = MAX (1, (int) [bitmap pixelsHigh] / 2);
  BOOL isDir;

  panel = [[NSPanel alloc]
            initWithContentRect: NSMakeRect (0, 0, PVWidth, height)
                      styleMask: NSTitledWindowMask
                        backing: NSBackingStoreBuffered
                          defer: NO];
  [panel setTitle: @"Export"];
  [panel setBackgroundColor: [PVStyle window]];
  content = [panel contentView];

  y = height - 16 - 20;
  {
    NSTextField *title = PVText (NSMakeRect (20, y, 300, 20), @"Export",
                                 [PVStyle text], NSLeftTextAlignment);

    [title setFont: [PVStyle fontOfSize: 14 bold: YES]];
    [content addSubview: title];
  }

  y -= 34;
  [self addRow: @"Save as" y: y to: content];
  nameField = AUTORELEASE ([[NSTextField alloc]
                             initWithFrame: NSMakeRect (x, y, w, 24)]);
  [content addSubview: nameField];

  y -= 32;
  [self addRow: @"Where" y: y to: content];
  wherePopup = [self popup: NSMakeRect (x, y, w, 24)];
  [wherePopup setAction: @selector(whereChanged:)];
  folders = [[NSMutableArray alloc] init];
  for (i = 0; i < [places count]; i++)
    {
      NSString *p = [[places objectAtIndex: i] stringByStandardizingPath];

      if ([folders containsObject: p]
          || ![fm fileExistsAtPath: p isDirectory: &isDir] || !isDir)
        continue;
      [folders addObject: p];
      [wherePopup addItemWithTitle: [p lastPathComponent]];
    }
  [wherePopup addItemWithTitle: @"Other…"];
  [content addSubview: wherePopup];

  y -= 32;
  [self addRow: @"Format" y: y to: content];
  formatPopup = [self popup: NSMakeRect (x, y, w, 24)];
  [formatPopup addItemWithTitle: @"PNG"];
  [[formatPopup lastItem] setTag: PVFormatPNG];
  [formatPopup addItemWithTitle: @"JPEG"];
  [[formatPopup lastItem] setTag: PVFormatJPEG];
  [formatPopup addItemWithTitle: @"TIFF"];
  [[formatPopup lastItem] setTag: PVFormatTIFF];
  [formatPopup addItemWithTitle: @"PDF"];
  [[formatPopup lastItem] setTag: PVFormatPDF];
  [content addSubview: formatPopup];

  y -= 32;
  qualityTitle = PVText (NSMakeRect (20, y + 3, PVLabelWidth, 18), @"Quality",
                         [PVStyle dim], NSRightTextAlignment);
  [content addSubview: qualityTitle];
  qualitySlider = AUTORELEASE ([[NSSlider alloc]
                                 initWithFrame: NSMakeRect (x, y + 2,
                                                            w - 70, 20)]);
  [qualitySlider setMinValue: 0.1];
  [qualitySlider setMaxValue: 1.0];
  [qualitySlider setFloatValue: 0.8];
  [qualitySlider setContinuous: YES];
  [qualitySlider setTarget: self];
  [qualitySlider setAction: @selector(changed:)];
  [content addSubview: qualitySlider];
  qualityLabel = PVText (NSMakeRect (x + w - 62, y + 3, 62, 18), @"",
                         [PVStyle dim], NSLeftTextAlignment);
  [content addSubview: qualityLabel];

  y -= 32;
  [self addRow: @"Size" y: y to: content];
  sizePopup = [self popup: NSMakeRect (x, y, w, 24)];
  [sizePopup addItemWithTitle:
               [NSString stringWithFormat: @"Full size: %ld × %ld",
                         (long) [bitmap pixelsWide],
                         (long) [bitmap pixelsHigh]]];
  [sizePopup addItemWithTitle:
               [NSString stringWithFormat: @"Half size: %d × %d",
                         halfW, halfH]];
  [content addSubview: sizePopup];

  y -= 26;
  estimate = PVText (NSMakeRect (x, y, w, 18), @"", [PVStyle dim],
                     NSLeftTextAlignment);
  [estimate setFont: [PVStyle fontOfSize: 12 bold: NO]];
  [content addSubview: estimate];

  button = AUTORELEASE ([[NSButton alloc]
                          initWithFrame: NSMakeRect (PVWidth - 20 - 90, 16,
                                                     90, 28)]);
  [button setTitle: @"Export"];
  [button setTarget: self];
  [button setAction: @selector(export:)];
  [button setKeyEquivalent: @"\r"];
  [content addSubview: button];
  button = AUTORELEASE ([[NSButton alloc]
                          initWithFrame: NSMakeRect (PVWidth - 20 - 90 - 8
                                                     - 90, 16, 90, 28)]);
  [button setTitle: @"Cancel"];
  [button setTarget: self];
  [button setAction: @selector(cancel:)];
  [button setKeyEquivalent: @"\e"];
  [content addSubview: button];

  if (pageLabel != nil)
    name = [NSString stringWithFormat: @"%@ %@", name,
                     [pageLabel lowercaseString]];
  start = pdfPath != nil ? PVFormatPDF : sourceFormat;
  if (start != PVFormatJPEG && start != PVFormatTIFF && start != PVFormatPDF)
    start = PVFormatPNG;
  [formatPopup selectItemAtIndex: [formatPopup indexOfItemWithTag: start]];
  [nameField setStringValue:
               [name stringByAppendingPathExtension:
                       [PVImage extensionForFormat: start]]];
  [self changed: nil];
}

- (BOOL) save
{
  NSString *name = [[nameField stringValue] stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *dir = [folders objectAtIndex:
                             MIN ((NSUInteger) [wherePopup indexOfSelectedItem],
                                  [folders count] - 1)];
  NSString *to;
  NSData *data;

  if ([name length] == 0 || [name rangeOfString: @"/"].location != NSNotFound)
    {
      NSRunAlertPanel (@"Give the copy a name.",
                       @"A name can't be empty or have a slash in it.",
                       @"OK", nil, nil);
      return NO;
    }
  to = [dir stringByAppendingPathComponent: name];
  if (pdfPath != nil && [[to stringByStandardizingPath]
                          isEqual: [pdfPath stringByStandardizingPath]])
    {
      NSRunAlertPanel (@"That's the PDF itself.",
                       @"Choose another name or place for the copy.",
                       @"OK", nil, nil);
      return NO;
    }
  if ([[NSFileManager defaultManager] fileExistsAtPath: to]
      && NSRunAlertPanel ([NSString stringWithFormat:
                                      @"“%@” already exists. Do you want to "
                                    @"replace it?", name],
                          @"The file in %@ will be replaced.", @"Replace",
                          @"Cancel", nil, [dir lastPathComponent])
           != NSAlertDefaultReturn)
    return NO;
  data = [self data];
  if (data == nil || ![data writeToFile: to atomically: YES])
    {
      NSRunAlertPanel (@"The copy couldn't be saved.",
                       @"%@ couldn't be written in %@.", @"OK", nil, nil,
                       name, [dir lastPathComponent]);
      return NO;
    }
  return YES;
}

+ (void) runForWindow: (NSWindow *)window
               bitmap: (NSBitmapImageRep *)rep
                 path: (NSString *)path
            pageLabel: (NSString *)label
{
  PVExport *e = AUTORELEASE ([[PVExport alloc] init]);
  NSRect f = [window frame];

  e->bitmap = RETAIN (rep);
  if ([PVImage isPDFPath: path])
    e->pdfPath = [path copy];
  e->pageLabel = [label copy];
  e->sourceFormat = [PVImage formatForPath: path];
  e->sourcePath = [path copy];
  [e buildWithName: [[path lastPathComponent] stringByDeletingPathExtension]
            folder: [path stringByDeletingLastPathComponent]];
  /* Over the top of the window, as a sheet is. */
  [e->panel setFrameTopLeftPoint:
              NSMakePoint (NSMidX (f) - [e->panel frame].size.width / 2,
                           NSMaxY (f) - 60)];
  [e->panel makeFirstResponder: e->nameField];
  for (;;)
    {
      if ([NSApp runModalForWindow: e->panel] != NSOKButton)
        break;
      if ([e save])
        break;
    }
  [e->panel orderOut: nil];
}

@end
