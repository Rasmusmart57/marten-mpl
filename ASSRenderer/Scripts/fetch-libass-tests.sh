#!/bin/bash
# libass's own test suite (github.com/libass/libass-tests, ISC like libass), for `LibassRegressionTests`: scripts with the pictures
# libass draws of them, and scripts that once made it crash. 34 MB, so fetched, not kept in the repo. Pinned: a new commit's
# pictures may change with a newer libass than the one Package.swift pins.
#
# usage: Vendor/ASSRenderer/Scripts/fetch-libass-tests.sh      (then `swift test` in Vendor/ASSRenderer finds it)
set -euo pipefail
COMMIT=205c63e601ad21f195528d1b1f112d9c542064d3
DEST="${LIBASS_TESTS:-$HOME/Library/Caches/MartenASS/libass-tests}"
if [ -d "$DEST/.git" ] && [ "$(git -C "$DEST" rev-parse HEAD)" = "$COMMIT" ]; then echo "$DEST"; exit 0; fi
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
git clone -q https://github.com/libass/libass-tests "$DEST"
git -C "$DEST" checkout -q "$COMMIT"
echo "$DEST"
