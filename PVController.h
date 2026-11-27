/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PVController: Preview's application delegate: the menus, opening files
 * (from File Viewer, Open, Open Recent and the command line) and the
 * appearance.
 */

#ifndef _PV_CONTROLLER_H_
#define _PV_CONTROLLER_H_

#import <AppKit/AppKit.h>

@interface PVController : NSObject
{
  NSMutableArray *viewers;
  NSMenu *recentMenu;
  BOOL launched;
}
- (BOOL) openPath: (NSString *)path;
@end

#endif
