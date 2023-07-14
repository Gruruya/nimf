# Main file/CLI --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## The CLI interface for nimf
import ./nimf/[find, findFiles, color, handling],
       pkg/[cligen, cligen/argcvt],
       std/[paths, terminal, exitprocs]
import std/os except getCurrentDir
from   std/strutils import startsWith, toLowerAscii
from   std/sequtils import mapIt, anyIt
from   std/typetraits import enumLen

type Flag {.pure.} = enum
  ## `bool` but with `auto` and `inverse`
  ## `always` and `never` mean explicitly always enable and disable
  ##  while `auto` and `inverse` act as "sane defaults" and are contigent on something else (like if we're outputting to a tty)
  always, never, auto, inverse

func toBool(flag: Flag; auto = true, inverse = false, always = true, never = false): bool =
  case flag
  of Flag.auto: auto
  of Flag.inverse: inverse
  of Flag.always: true
  of Flag.never: false

func substitute[T](x: var seq[T], y: seq[T], i: Natural) =
  ## Overwrites `x[i]` with `y`
  if i == x.high:
    if i == x.low: x = y
    else: x.setLen(x.len - 1); x.add y
  else:
    x.setLen(x.len + y.len - 1)
    x[i + y.len .. x.high] = x[i + 1 .. x.high + 1 - y.len]
    x[i ..< i + y.len] = y

proc cliFind*(color = Flag.auto; execute = newSeq[string](); followSymlinks = false; null = false; hyperlink = Flag.never; input: seq[string]): int =
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
    let toatty = stdout.isatty # We only write to stdout for explicit `yes` options
    let displayColor = color.toBool(auto = toatty and getEnv("NO_COLOR").len == 0, inverse = toatty and getEnv("NO_COLOR").len != 0)
    let hyperlink = hyperlink.toBool(auto = toatty)
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
proc argParse*(dst: var Flag, dfl: Flag, a: var ArgcvtParams): bool =
  if len(a.val) > 0:
    case a.val.toLowerAscii  # Like `argParse(dst: var bool...)` but we also accept a&i
    of "t", "true" , "yes", "y", "1", "on", "always": dst = Flag.always
    of "f", "false", "no" , "n", "0", "off", "never": dst = Flag.never
    of "a", "auto": dst = Flag.auto
    of "i", "inv", "inverse", "invert", "inverted": dst = Flag.inverse
    of "d", "default": dst = dfl
    else:
      a.msg = "Flag option \"$1\" non-flag argument (\"$2\")\n$3" %
              [ a.key, a.val, a.help ]
      return false
  else: # No option arg => reverse of default
    dst =
      case dfl
      of Flag.always, Flag.auto: Flag.inverse
      of Flag.never, Flag.inverse: Flag.auto
  return true

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
                    "color": "Enable or disable colored printing. Default is based on the `NO_COLOR` environment variable.",
                    "null": "Separate search results and split stdin with null characters `\\\\0` instead of newlines `\\\\n`.",
                    "hyperlink": "Enable clickable hyperlinks in supported terminals."})

when isMainModule:
  f()
