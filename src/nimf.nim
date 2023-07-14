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

type
  Flag {.pure.} = enum
    ## `bool` but with `auto` and `contra`
    ## `true` and `false` mean explicitly always enable and disable
    ##  while `auto` and `contra` act as "sane defaults" and are contigent on something else (like if we're outputting to a tty)
    true, false, auto, contra

func toBool(flag: Flag; auto = true, contra = false, true: static bool = true, false: static bool = false): bool {.inline.} =
  case flag
  of Flag.auto: auto
  of Flag.contra: contra
  of Flag.true: true
  of Flag.false: false

func substitute[T](x: var seq[T], y: seq[T], i: Natural) =
  ## Overwrites `x[i]` with `y`
  if i == x.high:
    if i == x.low: x = y
    else: x.setLen(x.len - 1); x.add y
  else:
    x.setLen(x.len + y.len - 1)
    x[i + y.len .. x.high] = x[i + 1 .. x.high + 1 - y.len]
    x[i ..< i + y.len] = y

proc cliFind*(types = {pcFile, pcDir, pcLinkToFile, pcLinkToDir}; execute = newSeq[string](); followSymlinks = false; null = false; color = Flag.auto; hyperlink = Flag.false; input: seq[string]): int =
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
    traverseFind(paths, patterns, types, followSymlinks, andDo)

  if execute.len == 0:
    let toatty = stdout.isatty # We only write to stdout for explicit `yes` options
    let displayColor = color.toBool(auto = toatty and getEnv("NO_COLOR").len == 0, contra = toatty and getEnv("NO_COLOR").len != 0)
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
func argParse*(dst: var Flag, dfl: Flag, a: var ArgcvtParams): bool =
  if len(a.val) > 0:
    case a.val.toLowerAscii  # Like `argParse(dst: var bool...)` but we also accept a&i
    of "t", "true" , "yes", "y", "1", "on", "always": dst = Flag.true
    of "f", "false", "no" , "n", "0", "off", "never": dst = Flag.false
    of "a", "auto": dst = Flag.auto # "a" could be confused for "always"
    of "c", "contra", "contraauto", "contrauto": dst = Flag.contra
    of "d", "default", "unset": dst = dfl
    else:
      a.msg = "Flag option \"$1\" non-flag argument (\"$2\")\n$3" %
              [ a.key, a.val, a.help ]
      return false
  else: # No option arg => reverse of default
    dst =
      case dfl
      of Flag.true, Flag.auto: Flag.contra
      of Flag.false, Flag.contra: Flag.auto
  return true

type FileKind = enum
  file, directory, link, any

func to(filetype: FileKind, T: type set[PathComponent]): T =
  case filetype
  of file: {pcFile}
  of directory: {pcDir}
  of link: {pcLinkToFile, pcLinkToDir}
  of any: {pcFile, pcDir, pcLinkToFile, pcLinkToDir}

proc argParse*(dst: var set[PathComponent], dfl: set[PathComponent], a: var ArgcvtParams): bool =
  var first = false; once: first = true
  result = true
  try:
    proc argAggSplit(a: var ArgcvtParams, split=true): set[PathComponent] =
      ## Similar to `argAggSplit` but specialized for set[PathComponent] using the `FileKind` enum for English options
      let toks = if split: a.val[1..^1].split(a.val[0]) else: @[ move(a.val) ]
      let old = a.sep; a.sep = ""
      for i, tok in toks:

        var parsed, default: set[FileKind]
        a.val = tok

        if not argParse(parsed, default, a):
          result = {}; a.sep = old
          raise newException(ElementError, "Bad element " & $i)

        for t in parsed:
          result.incl t.to(set[PathComponent])
      a.sep = old #probably don't need to restore, but eh.

    if a.sep.len <= 1:                      # no sep|no op => append
      if first: dst = argAggSplit(a, false) # overwrite defaults if first sep is `=`
      else: dst.incl argAggSplit(a, false)
      return
    if   a.sep == "+=": dst.incl argAggSplit(a, false)
    elif a.sep == "-=": dst.excl argAggSplit(a, false)
    elif a.val == "" and a.sep == ",=":     # just clobber
      dst = {}
    elif a.sep == ",@=":                    # split-clobber-assign
      dst = argAggSplit(a)
    elif a.sep == ",=" or a.sep == ",+=":   # split-include
      dst.incl argAggSplit(a)
    elif a.sep == ",-=":                    # split-exclude
      dst.excl argAggSplit(a)
    else:
      a.msg = "Bad operator (\"$1\") for set of types, param $2\n" % [a.sep, a.key]
      raise newException(ElementError, "Bad operator")
  except:
    return false

func argHelp*(dfl: set[PathComponent], a: var ArgcvtParams): seq[string]=
  var typ = "filetype"; var df: string
  var dflSeq: seq[string]
  if dfl == {pcFile, pcDir, pcLinkToFile, pcLinkToDir}:
    dflSeq = @["any"]
  else:
    for d in dfl: dflSeq.add($d)
  argAggHelp(dflSeq, "set", typ, df)
  result = @[ a.argKeys, typ, df ]

proc f*() =
  dispatch(cliFind,
           cmdName = "f",
           usage = (try: getAppFilename().lastPathPart except: "f") & " $args\n\n" &
                    "Entered `input` may be a pattern OR a path to search.\n" &
                    "The pattern will only match with the filename unless you include a `/`.\n" &
                    "\nOptions:\n$options",
           short = {"followSymlinks": 'L', "null": '0', "types": 't'},
           help = {"types": "Select which file kind(s) to match. File kinds include any|file|directory|link.",
                   "execute": "Execute a command for each matching search result in parallel.\n" &
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
