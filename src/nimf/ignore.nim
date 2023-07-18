# Paths to ignore --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

import std/sets, ./find

const ignoredDirs* = toHashSet([
  ".git",
  ".cache", "nimcache", "__pycache__",
  "venv", "node_modules"])

func filename(path: string): string {.inline.} =
  if path.len > 1 and path[0] == '/': # Doesn't strip `./`
    let lastSlash = path.rfind(['/'], start = 1, last = path.high)
    if lastSlash.isSome: path[lastSlash.unsafeGet + 1..path.high]
    else: path[1 .. ^1]
  else: path

func ignoreDir*(dir: string): bool {.inline.} =
  dir.filename in ignoredDirs
