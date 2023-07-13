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
type Param[T] = object
  val*: T
  set*: bool
  input*: string
proc filled[T](val: sink T): Param[T] {.inline.} =
  result.set = true
  result.val = val
proc blank[T](val: sink T): Param[T] {.inline.} =
  result.set = false
  result.val = val
proc blank(T: typedesc): Param[T] {.inline.} = Param[T]()
proc blank[T]: Param[T] {.inline.} = blank(T)
proc isSet[T](self: Param[T]): bool {.inline.} = self.set
proc isUnset[T](self: Param[T]): bool {.inline.} = not self.set

func substitute[T](x: var seq[T], y: seq[T], i: Natural) =
  ## Overwrites `x[i]` with `y`
  if i == x.high:
    if i == x.low: x = y
    else: x.setLen(x.len - 1); x.add y
  else:
    x.setLen(x.len + y.len - 1)
    x[i + y.len .. x.high] = x[i + 1 .. x.high + 1 - y.len]
    x[i ..< i + y.len] = y

proc cliFind*(color = blank(bool); execute = newSeq[string](); followSymlinks = false; null = false;
  hyperlink = false; input: seq[string]): int =
  var patterns = newSeq[string]()
  var paths = newSeq[Path]()
  var input = input
  if not stdin.isatty: # Add stdin to `input`
    if input.len == 0:
      input = stdin.readAll().split(if null: '\0' else: '\n')
      if input[^1].len == 0: input.setLen(input.len - 1)
    else:
      var si = stdin.readAll().split(if null: '\0' else: '\n')
      if si[^1].len == 0: si.setLen(si.len - 1)
      var i = input.low
      while i <= input.high:
        if input[i] in ["-", "/dev/stdin"]: input.substitute(si, i); inc(i, si.len)
        else: inc i

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
    let isatty = stdout.isatty
    let envColorEnabled = isatty and getEnv("NO_COLOR").len == 0
    let displayColor = color.isUnset and envColorEnabled or
                       color.isSet and (if color.input.len == 0: (if not isatty: false else: not envColorEnabled) else: color.val)
    let hyperlink = isatty and hyperlink
    if displayColor:
      lscolors = parseLSColorsEnv()
      exitprocs.addExitProc(resetAttributes)
      discard traverse(runOption.init(coloredPrint, null, hyperlink))
      stdout.flushFile()
    else:
      discard traverse(runOption.init(plainPrint, null, hyperlink))
  else:
    if anyIt(execute, it.endsWith("+")):
      run(execute, traverse(runOption(kind: collect)))
    else:
      let cmds = execute.mapIt(Command.init(it))
      discard traverse(runOption(kind: exec, cmds: cmds))

# Special argument parsing
proc argParse[T](dst: var Param[T], dfl: Param[T], a: var ArgcvtParams): bool =
  var uw: T # An unwrapped value
  result = argParse(uw, (if dfl.isSet: dfl.val else: uw), a)
  if result: dst = filled uw; dst.input = a.val
proc argHelp[T](dfl: Param[T]; a: var ArgcvtParams): seq[string] =
  @[a.argKeys, $T, (if dfl.isSet: $dfl.val else: "?")]

proc f*() =
  dispatch(cliFind,
           cmdName = "f",
           usage = (try: getAppFilename().lastPathPart except: "f") & " $args\n\n" &
                    "Entered `input` may be a pattern OR a path to search.\n" &
                    "The pattern will only match with the filename unless you include a `/`.\n" &
                    "\nOptions:\n$options",
           short = {"followSymlinks": 'L', "null": '0'},
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
                              "If no placeholder is present, an implicit \" {}\" at the end is assumed.",
                    "null": "Separate search results and split stdin with null characters `\\\\0` instead of newlines `\\\\n`.",
                    "hyperlink": "Enable clickable hyperlinks in supported terminals."})

when isMainModule:
  f()
