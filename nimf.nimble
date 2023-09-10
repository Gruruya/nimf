# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

version     = "0.5.0"
author      = "Gruruya"
description = "File finder"
license     = "AGPL-3.0-only"

srcDir = "src"
skipDirs = @["tests"]
installExt = @["nim", "csv"]
namedBin["nimf"] = "f"

# Dependencies
requires "nim >= 2.0.0"
requires "malebolgia"
requires "cligen >= 1.6.6 & < 2.0.0"
requires "lscolors#head"
requires "stack_strings"

taskRequires "test", "https://github.com/disruptek/balls.git >= 3.0.0"

task test, "run tests":
  let balls =
    when defined(windows):
          "balls.cmd"
    else: "balls"
  exec balls & " --backend:c --mm:arc --define:danger"
