version     = "0.0.0"
author      = "Gruruya"
description = "A template to jump start your Nim library or project."
license     = "AGPL-3.0-only"

srcDir = "src"
skipDirs = @["tests"]
#bin = @["nimtemplate"]
# uncomment if this program includes a binary
# also add nimble build -y to the run field of the build and test job in .github/workflows/build.yml

# Dependencies
#requires "nim >= 1.9.3"
# Uncomment if you require features from a specific Nim version

when declared(taskRequires):
  when (NimMajor, NimMinor) >= (1, 7) and not defined(windows) and not defined(macosx):
        taskRequires "test", "https://github.com/disruptek/balls >= 3.0.0"
  else: taskRequires "test", "https://github.com/disruptek/balls#head"
else:
  requires "https://github.com/disruptek/balls >= 3.0.0 & < 4.0.0"
  before test: exec "nimble install -y"

task test, "run tests":
  let balls =
    when defined(windows):
          "balls.cmd"
    else: "balls"
  exec balls & " --backend:c --mm:arc --mm:refc --define:danger"
