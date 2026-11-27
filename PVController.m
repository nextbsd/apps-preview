/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PVController.h"
#import "PVImage.h"
#import "PVStyle.h"
#import "PVViewer.h"
#import <GNUstepBase/GNUstep.h>

#define PVRecentKey @"PreviewRecentFiles"
#define PVRecentMost 10

static id<NSMenuItem>
PVAddItem (NSMenu *menu, NSString *title, SEL action, NSString *key,
           unsigned int modifiers)
{
  id<NSMenuItem> item = [menu addItemWithTitle: title action: action
                                 keyEquivalent: key];

  if (modifiers != 0)
    [item setKeyEquivalentModifierMask: modifiers];
  return item;
}

static NSMenu *
PVSubmenu (NSMenu *menu, NSString *title)
{
  NSMenu *sub = AUTORELEASE ([[NSMenu alloc] initWithTitle: title]);
  id<NSMenuItem> item = [menu addItemWithTitle: title action: NULL
                                 keyEquivalent: @""];

  [menu setSubmenu: sub forItem: item];
  return sub;
}

@implementation PVController

- (id) init
{
  if ((self = [super init]) != nil)
    viewers = [[NSMutableArray alloc] init];
  return self;
}

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [[NSDistributedNotificationCenter defaultCenter] removeObserver: self];
  RELEASE (viewers);
  RELEASE (recentMenu);
  [super dealloc];
}

/* ---- menus ---- */

- (void) rebuildRecent
{
  NSArray *recent = [[NSUserDefaults standardUserDefaults]
                      arrayForKey: PVRecentKey];
  id<NSMenuItem> item;
  NSUInteger i;

  while ([recentMenu numberOfItems] > 0)
    [recentMenu removeItemAtIndex: 0];
  for (i = 0; i < [recent count]; i++)
    {
      NSString *p = [recent objectAtIndex: i];

      item = [recentMenu addItemWithTitle: [p lastPathComponent]
                                   action: @selector(openRecent:)
                            keyEquivalent: @""];
      [item setRepresentedObject: p];
      [item setTarget: self];
    }
  if ([recent count] > 0)
    [recentMenu addItem: [NSMenuItem separatorItem]];
  item = [recentMenu addItemWithTitle: @"Clear Menu"
                               action: @selector(clearRecent:)
                        keyEquivalent: @""];
  [item setTarget: self];
}

- (void) noteRecent: (NSString *)path
{
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  NSMutableArray *recent = [NSMutableArray arrayWithArray:
                                             [defs arrayForKey: PVRecentKey]];

  [recent removeObject: path];
  [recent insertObject: path atIndex: 0];
  while ([recent count] > PVRecentMost)
    [recent removeLastObject];
  [defs setObject: recent forKey: PVRecentKey];
  [self rebuildRecent];
}

- (void) makeMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Preview"]);
  NSMenu *file, *edit, *view, *go, *tools, *windows, *help;
  unsigned int cmd = NSCommandKeyMask;

  PVAddItem (menu, @"About Preview", @selector(orderFrontStandardInfoPanel:),
             @"", 0);

  file = PVSubmenu (menu, @"File");
  PVAddItem (file, @"Open…", @selector(openDocument:), @"o", 0);
  recentMenu = RETAIN (PVSubmenu (file, @"Open Recent"));
  [self rebuildRecent];
  [file addItem: [NSMenuItem separatorItem]];
  PVAddItem (file, @"Close", @selector(performClose:), @"w", 0);
  PVAddItem (file, @"Save", @selector(saveDocument:), @"s", 0);
  PVAddItem (file, @"Export…", @selector(exportDocument:), @"e", 0);
  [file addItem: [NSMenuItem separatorItem]];
  PVAddItem (file, @"Get Info", @selector(showInfo:), @"i", 0);

  edit = PVSubmenu (menu, @"Edit");
  PVAddItem (edit, @"Cut", @selector(cut:), @"x", 0);
  PVAddItem (edit, @"Copy", @selector(copy:), @"c", 0);
  PVAddItem (edit, @"Paste", @selector(paste:), @"v", 0);
  PVAddItem (edit, @"Select All", @selector(selectAll:), @"a", 0);
  [edit addItem: [NSMenuItem separatorItem]];
  PVAddItem (edit, @"Find…", @selector(find:), @"f", 0);
  PVAddItem (edit, @"Find Next", @selector(findNext:), @"g", 0);
  PVAddItem (edit, @"Find Previous", @selector(findPrevious:), @"G", 0);

  view = PVSubmenu (menu, @"View");
  PVAddItem (view, @"Hide Sidebar", @selector(toggleSidebar:), @"s",
             cmd | NSAlternateKeyMask);
  [view addItem: [NSMenuItem separatorItem]];
  PVAddItem (view, @"Zoom In", @selector(zoomIn:), @"+", 0);
  PVAddItem (view, @"Zoom Out", @selector(zoomOut:), @"-", 0);
  PVAddItem (view, @"Zoom to Fit", @selector(zoomToFit:), @"0", 0);
  PVAddItem (view, @"Actual Size", @selector(actualSize:), @"1", 0);
  [view addItem: [NSMenuItem separatorItem]];
  PVAddItem (view, @"Slideshow", @selector(startSlideshow:), @"F", 0);

  go = PVSubmenu (menu, @"Go");
  PVAddItem (go, @"Previous", @selector(goPrevious:), @"", 0);
  PVAddItem (go, @"Next", @selector(goNext:), @"", 0);
  PVAddItem (go, @"First", @selector(goFirst:), @"", 0);
  PVAddItem (go, @"Last", @selector(goLast:), @"", 0);

  tools = PVSubmenu (menu, @"Tools");
  PVAddItem (tools, @"Rotate Left", @selector(rotateLeft:), @"l", 0);
  PVAddItem (tools, @"Rotate Right", @selector(rotateRight:), @"r", 0);

  windows = PVSubmenu (menu, @"Window");
  PVAddItem (windows, @"Minimize", @selector(performMiniaturize:), @"m", 0);
  PVAddItem (windows, @"Close", @selector(performClose:), @"", 0);
  [NSApp setWindowsMenu: windows];

  help = PVSubmenu (menu, @"Help");
  PVAddItem (help, @"Preview Help", @selector(showHelp:), @"?", 0);

  PVAddItem (menu, @"Hide", @selector(hide:), @"h", 0);
  PVAddItem (menu, @"Quit", @selector(terminate:), @"q", 0);
  [NSApp setMainMenu: menu];
}

/* ---- opening ---- */

- (BOOL) openPath: (NSString *)path
{
  PVViewer *viewer;
  NSUInteger i;

  path = [path stringByStandardizingPath];
  for (i = 0; i < [viewers count]; i++)
    {
      viewer = [viewers objectAtIndex: i];
      if ([[viewer path] isEqual: path])
        {
          [[viewer window] makeKeyAndOrderFront: nil];
          return YES;
        }
    }
  if (![PVImage isPDFPath: path] && ![PVImage isImagePath: path])
    {
      NSRunAlertPanel (@"Preview can't open this file.",
                       @"%@ isn't a picture or a PDF.", @"OK", nil, nil,
                       [path lastPathComponent]);
      return NO;
    }
  NS_DURING
    viewer = [PVViewer viewerWithPath: path];
  NS_HANDLER
    {
      NSLog (@"Preview: opening %@: %@", path, localException);
      NSRunAlertPanel (@"The file couldn't be opened.", @"%@: %@", @"OK",
                       nil, nil, [path lastPathComponent],
                       [localException reason]);
      viewer = nil;
    }
  NS_ENDHANDLER
  if (viewer == nil)
    return NO;
  [viewers addObject: viewer];
  [viewer show];
  [self noteRecent: path];
  return YES;
}

- (NSArray *) openableTypes
{
  return [[PVImage imageExtensions] arrayByAddingObject: @"pdf"];
}

- (void) openDocument: (id)sender
{
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  NSArray *files;
  NSUInteger i;

  [panel setAllowsMultipleSelection: YES];
  [panel setTitle: @"Open"];
  if ([panel runModalForDirectory: nil file: nil
                            types: [self openableTypes]] != NSOKButton)
    return;
  files = [panel filenames];
  for (i = 0; i < [files count]; i++)
    [self openPath: [files objectAtIndex: i]];
}

- (void) openRecent: (id)sender
{
  NSString *path = [sender representedObject];

  if (path != nil)
    [self openPath: path];
}

- (void) clearRecent: (id)sender
{
  [[NSUserDefaults standardUserDefaults] removeObjectForKey: PVRecentKey];
  [self rebuildRecent];
}

- (BOOL) application: (NSApplication *)app openFile: (NSString *)file
{
  return [self openPath: file];
}

- (void) application: (NSApplication *)app openFiles: (NSArray *)files
{
  NSUInteger i;

  for (i = 0; i < [files count]; i++)
    [self openPath: [files objectAtIndex: i]];
}

- (void) viewerClosed: (NSNotification *)n
{
  id viewer = [n object];

  /* It's in the middle of closing: let it finish first. */
  AUTORELEASE (RETAIN (viewer));
  [viewers removeObjectIdenticalTo: viewer];
}

/* ---- appearance ---- */

- (void) settingsChanged: (NSNotification *)n
{
  NSString *key = [[n userInfo] objectForKey: @"key"];

  if (key != nil && ![key isEqual: @"NBAppearance"])
    return;
  [PVStyle reload];
  [[NSNotificationCenter defaultCenter]
    postNotificationName: PVStyleChangedNotification object: nil];
}

/* ---- the application ---- */

- (void) applicationWillFinishLaunching: (NSNotification *)n
{
  [self makeMenu];
  [[NSNotificationCenter defaultCenter]
    addObserver: self selector: @selector(viewerClosed:)
           name: PVViewerClosedNotification object: nil];
  [[NSDistributedNotificationCenter defaultCenter]
    addObserver: self selector: @selector(settingsChanged:)
           name: @"org.nextbsd.DesktopSettingsChanged" object: nil];
}

/* Files named on the command line: "Preview picture.png". */
- (void) openArguments
{
  NSArray *args = [[NSProcessInfo processInfo] arguments];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSUInteger i;
  NSString *a;

  for (i = 1; i < [args count]; i++)
    {
      a = [args objectAtIndex: i];
      if ([a hasPrefix: @"-"])
        {
          i++;			/* -Default value */
          continue;
        }
      if ([fm fileExistsAtPath: a])
        [self openPath: a];
    }
}

- (void) offerOpen
{
  /* Started on its own, with nothing to show: ask what to open. */
  if ([viewers count] == 0)
    [self openDocument: nil];
}

- (void) applicationDidFinishLaunching: (NSNotification *)n
{
  launched = YES;
  [self openArguments];
  if (![[NSUserDefaults standardUserDefaults]
         boolForKey: @"PreviewNoOpenPanel"])
    [self performSelector: @selector(offerOpen) withObject: nil
               afterDelay: 0.5];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)a
{
  return NO;
}

- (NSApplicationTerminateReply) applicationShouldTerminate: (NSApplication *)a
{
  NSUInteger i;

  /* A turned picture is offered to be saved first. */
  for (i = 0; i < [viewers count]; i++)
    if (![[viewers objectAtIndex: i] canClose])
      return NSTerminateCancel;
  return NSTerminateNow;
}

@end
