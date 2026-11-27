# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Preview.app: shows pictures and PDFs, as Preview on NeXTSTEP and macOS
# (nextbsd/nextbsd#716). Installed in the SYSTEM domain, as
# /System/Applications/Preview.app.
#
# Pictures are read by GNUstep's NSBitmapImageRep (BMP by Preview itself).
# PDFs are rendered, searched and their text read by Poppler: poppler-cpp
# (libpoppler-cpp.so.3 and its headers in /usr/include/poppler/cpp, from
# NextBSD-gnustep-support, and in the GNUstep SDK), through PVPoppler.cc,
# the only C++ in it. zlib compresses the pictures Export writes as PDF.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

APP_NAME = Preview
Preview_OBJC_FILES = main.m PVController.m PVViewer.m PVViews.m PVStyle.m \
	PVImage.m PVPDFDocument.m PVExport.m PVSlideshow.m
Preview_CC_FILES = PVPoppler.cc
Preview_HEADER_FILES = PVController.h PVViewer.h PVViews.h PVStyle.h \
	PVImage.h PVPDFDocument.h PVExport.h PVSlideshow.h PVPoppler.h
Preview_RESOURCE_FILES = Resources/Preview.png Resources/Preview.help
Preview_APPLICATION_ICON = Preview.png
Preview_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
Preview_CCFLAGS = -Wall -Wextra -Wno-unused-parameter -std=c++17
Preview_GUI_LIBS += -lpoppler-cpp -lz -lm

include $(GNUSTEP_MAKEFILES)/application.make
