# Files to ignore --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

import std/sets

const ignoreDirSet* = toHashSet([
  ".git",
  "node_modules",
  "venv"])

func ignoreDir*(s: string): bool {.inline.} =
  s in ignoreDirSet
