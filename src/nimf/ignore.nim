# Paths to ignore --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

import std/sets

const ignoredDirs* = toHashSet([
  ".git",
  ".cache", "nimcache", "__pycache__",
  "venv", "node_modules"])
