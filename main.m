/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Preview.app: shows pictures and PDFs, as Preview on NeXTSTEP and macOS
 * (nextbsd/nextbsd#716).
 */

#import <AppKit/AppKit.h>
#import "PVController.h"

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  PVController *controller;

  [NSApplication sharedApplication];
  controller = [[PVController alloc] init];
  [NSApp setDelegate: controller];
  [NSApp run];
  RELEASE (controller);
  RELEASE (pool);
  return 0;
}
