version     = "0.0.6"
author      = "Gruruya"
description = "Text finder"
license     = "AGPL-3.0-only"

srcDir = "src"
skipDirs = @["tests"]
namedBin["nimf"] = "f"

# Dependencies
requires "nim >= 1.9.3"
requires "malebolgia"
requires "cligen"

taskRequires "test", "https://github.com/disruptek/balls >= 3.0.0"

task test, "run tests":
  let balls =
    when defined(windows):
          "balls.cmd"
    else: "balls"
  exec balls & " --backend:c --mm:arc --mm:refc --define:danger"
