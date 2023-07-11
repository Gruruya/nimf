# Main file/CLI --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## The CLI interface for nimf
import ./nimf/[find, findFiles, color, handling],
       pkg/[cligen, cligen/argcvt],
       std/[paths, terminal, exitprocs]
import std/os except getCurrentDir
from   std/strutils import startsWith
from   std/sequtils import mapIt, anyIt
from   std/typetraits import enumLen

# `options.Option` but also stores the input so we can negate flags without values like `-c`
type Flag[T] = object
  val*: T
  has*: bool
  input*: string
proc some[T](val: sink T): Flag[T] {.inline.} =
  result.has = true
  result.val = val
proc none[T](val: sink T): Flag[T] {.inline.} =
  result.has = false
  result.val = val
proc none(T: typedesc): Flag[T] {.inline.} = Flag[T]()
proc none[T]: Flag[T] {.inline.} = none(T)
proc isSome[T](self: Flag[T]): bool {.inline.} = self.has
proc isNone[T](self: Flag[T]): bool {.inline.} = not self.has
proc unsafeGet[T](self: Flag[T]): lent T {.inline.} =
  assert self.isSome
  result = self.val

proc cliFind*(color = none bool, execute = newSeq[string](), followSymlinks = false, input: seq[string]): int =
  var patterns = newSeq[string]()
  var paths = newSeq[Path]()

  proc isChildOf(path, potParent: string): bool =
    let aPotParent = absolutePath(Path(potParent))
    let aPath = absolutePath(Path(path))
    if aPath == aPotParent:
      true
    else:
      for parent in aPath.parentDirs:
        if aPotParent == parent:
          return true
      false

  proc alreadyAdded(paths: seq[Path]; arg: string): bool {.inline.} =
    anyIt(paths, arg.isChildOf(it.string))

  if input.len > 0:
    for i in input.low..input.high:
      let arg = input[i]
      if arg != "/" and (dirExists(arg) or fileExists(arg) and (arg.startsWith("./") or absolutePath(Path(arg)).parentDir != getCurrentDir())) and not paths.alreadyAdded(arg):
        paths.add Path(arg)
      else:
        patterns.add arg
  if patterns.len == 0: patterns = @[""]
  if paths.len == 0: paths = @[Path(".")]

  template traverse(andDo: runOption): untyped =
    traverseFind(paths, patterns, {pcFile, pcDir, pcLinkToFile, pcLinkToDir}, followSymlinks, andDo)

  if execute.len == 0:
    let envColorEnabled = stdout.isatty and getEnv("NO_COLOR").len == 0
    let displayColor = color.isNone and envColorEnabled or
                       color.isSome and (if color.input.len == 0: not envColorEnabled else: color.unsafeGet)
    if displayColor:
      lscolors = parseLSColorsEnv()
      exitprocs.addExitProc(resetAttributes)
      discard traverse(coloredPrint)
      stdout.flushFile()
    else:
      discard traverse(plainPrint)
  else:
    run(execute, traverse(collect))

# Special argument parsing
proc argParse[T](dst: var Flag[T], dfl: Flag[T], a: var ArgcvtParams): bool =
  var uw: T # An unwrapped value
  result = argParse(uw, (if dfl.isSome: dfl.unsafeGet else: uw), a)
  if result: dst = some uw; dst.input = a.val
proc argHelp[T](dfl: Flag[T]; a: var ArgcvtParams): seq[string] =
  @[a.argKeys, $T, (if dfl.isSome: $dfl.unsafeGet else: "?")]

proc f*() =
  dispatch(cliFind,
           cmdName = "f",
           usage = (try: getAppFilename().lastPathPart except: "f") & " $args\n\n" &
                    "Entered `input` may be a pattern OR a path to search.\n" &
                    "The pattern will only match with the filename unless you include a `/`.\n" &
                    "\nOptions:\n$options",
           short = {"followSymlinks": 'L'},
           help = {"execute": "Execute a command for each matching search result in parallel.\n" &
                              "Alternatively, end this argument with \"+\" to execute the command once with all results as arguments.\n" & 
                              "Example: f .nim -e \"$EDITOR\"+\n" &
                              "The following placeholders are substituted before the command is executed:\n" &
                              "\"{}\":   path (of the current search result)\n" &
                              "\"{/}\":  basename\n" &
                              "\"{//}\": parent directory\n" &
                              "\"{.}\":  path without file extension\n" &
                              "\"{/.}\": basename without file extension\n" &
                              "Example: f .jpg -e 'convert {} {.}.png'\n" &
                              "If no placeholder is present, an implicit \" {}\" at the end is assumed."})

when isMainModule:
  f()
