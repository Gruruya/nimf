# Files to ignore --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

import std/sets

const ignoreDirSet* = toHashSet([
  ".git",
  ".cache", "__pycache__",
  "venv", "node_modules"])

func ignoreDir*(s: string): bool {.inline.} =
  s in ignoreDirSet
