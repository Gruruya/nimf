# Main file/CLI --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## The CLI interface for nimf
import ./nimf/[find, color, handling, text],
       pkg/[cligen, cligen/argcvt],
       std/[paths, exitprocs, macros, sets]
import std/os except getCurrentDir
from   std/terminal import isatty, resetAttributes
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

func incl*(a: var FileTypes, b: FileTypes) =
  a.kinds.incl b.kinds
  a.extensions.incl b.extensions

func excl*(a: var FileTypes, b: FileTypes) =
  a.kinds.excl b.kinds
  a.extensions.excl b.extensions

func substitute[T](x: var seq[T], y: seq[T], i: Natural) =
  ## Overwrites `x[i]` with `y`
  if i == x.high:
    if i == x.low: x = y
    else: x.setLen(x.len - 1); x.add y
  else:
    x.setLen(x.len + y.len - 1)
    x[i + y.len .. x.high] = x[i + 1 .. x.high + 1 - y.len]
    x[i ..< i + y.len] = y

template ctrlC(body: untyped): proc() {.noconv.} =
  proc() {.noconv.} =
    stopFind()
    body
    stdout.write "SIGINT: Interrupted by Ctrl-C.\n"
    quit(128 + 2)

proc cliFind*(all=false; exclude=newSeq[string](); types=FileTypes(); execute=newSeq[string](); max_depth=0; limit=(found: 0, time: 0.milliseconds); follow_symlinks=false; null=false; color=Flag.auto; hyperlink=Flag.false; input: seq[string]): int =
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

  macro traverse(andDo: RunOptionAction, args: varargs[typed]): untyped =
    var behavior = quote: RunOption.init(`andDo`, follow_symlinks, all, exclude, types, max_depth, limit.found, limit.time)
    for a in args: behavior.add a
    quote: traverseFind(paths, patterns, `behavior`)

  if execute.len == 0:
    let toatty = stdout.isatty # We only write to stdout for explicit `yes` options
    let displayColor = color.toBool(auto = toatty and getEnv("NO_COLOR").len == 0, contra = toatty and getEnv("NO_COLOR").len != 0)
    let hyperlink = hyperlink.toBool(auto = toatty)

    if hyperlink:
      setControlCHook(ctrlC do: stdout.write "\e]8;;\e\\"; stdout.resetAttributes())
      exitprocs.addExitProc(proc = stderr.write "\e]8;;\e\\"; stdout.write "\e]8;;\e\\")
    elif displayColor:
      setControlCHook(ctrlC do: stdout.resetAttributes())

    if displayColor:
      stdout.resetAttributes()
      exitprocs.addExitProc(proc = stderr.resetAttributes(); stdout.resetAttributes())
      lscolors = parseLSColorsEnv()
      discard traverse(coloredPrint, null, hyperlink)
    else:
      discard traverse(plainPrint, null, hyperlink)

  else:
    if anyIt(execute, it.endsWith("+")):
       run(execute, traverse(collect))
    else:
      let cmds = execute.mapIt(Command.init(it))
      discard traverse(exec, cmds)

  if (if limit.found > 0: numFound.load == 0 else: numMatches == 0):
    quit 101

#[ Special argument parsing ]#
func argParse*(dst: var Flag, dfl: Flag, a: var ArgcvtParams): bool =
  ## For `--flag=auto`, `contra` is equivalent to `--flag` without an argument (negating)
  if len(a.val) > 0:
    case a.val.toLowerAscii  # Like `argParse(dst: var bool...)` but we also accept a&i
    of "t", "true" , "yes", "y", "1", "on", "always": dst = Flag.true
    of "f", "false", "no" , "n", "0", "off", "never": dst = Flag.false
    of "a", "auto", "smart": dst = Flag.auto # "a" could be confused for "always"
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

proc argHelp*(dfl: Flag; a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys(argSep=""), "flag", $dfl ]
  if a.parSh.len > 0:
    a.shortNoVal.incl(a.parSh[0]) # flag can elide option arguments.
  a.longNoVal.add(move(a.parNm))  # So, add to *NoVal.

proc argHelp*(dfl: tuple[found: int, time: TimeInterval]; a: var ArgcvtParams): seq[string] =
  @[ a.argKeys, "int/ms/s", "0" ]

proc argParse*(dst: var tuple[found: int, time: TimeInterval], dfl: tuple[found: int, time: TimeInterval], a: var ArgcvtParams): bool =
  if a.val.endsWith("ms"):
    a.val.setLen(a.val.len - 2)
    var ms: int
    result = argParse(ms, dfl.found, a)
    dst.time = ms.milliseconds
  elif a.val.endsWith("s"):
    a.val.setLen(a.val.len - 1)
    var s: int
    result = argParse(s, dfl.found, a)
    dst.time = s.seconds
  else:
    result = argParse(dst.found, dfl.found, a)

proc argParse*(dst: var FileTypes, dfl: FileTypes, a: var ArgcvtParams): bool =
  ## Parse `set[PathComponent]` as a `set[FileKind]`
  var first = false; once: first = true
  result = true
  try:
    proc argAggSplit(a: var ArgcvtParams, split=true): FileTypes =
      ## Similar to `argAggSplit` but specialized for set[PathComponent] using the `FileKind` enum for English options
      type FileKind = enum
        file, directory, link, lfile, ldirectory, flink, dlink

      func to(filetype: FileKind, T: type set[PathComponent]): T =
        case filetype
        of file: {pcFile}
        of directory: {pcDir}
        of link: {pcLinkToFile, pcLinkToDir}
        of lfile, flink: {pcLinkToFile}
        of ldirectory, dlink: {pcLinkToDir}
      
      if a.val.len == 0:
        a.msg = "No value set for option \"$1$2\"\n" % [a.key, a.sep]
        raise newException(ElementError, "No value")

      let toks = if split: a.val[1..^1].split(a.val[0]) else: @[ move(a.val) ]
      let old = a.sep; a.sep = ""
      for i, tok in toks:

        a.val = tok

        if a.val[0] == '.':
          result.extensions.incl a.val

        elif a.val == "any":
          result = FileTypes()

        else:
          var parsed, default: set[FileKind]
          case a.val
          of "l":
            parsed.incl link
          of "f":
            parsed.incl {file, lfile}
          of "d":
            parsed.incl {directory, ldirectory}
          elif not argParse(parsed, default, a):
            result.extensions.incl '.' & a.val

          for t in parsed:
            result.kinds.incl t.to(set[PathComponent])
      a.sep = old #probably don't need to restore, but eh.

    if a.sep.len <= 1:                      # no sep|no op => append
      if first: dst = argAggSplit(a, false) # overwrite defaults if first use is assignment
      else: dst.incl argAggSplit(a, false)
      return

    if a.val == "" and a.sep == ",=": # clear
      dst = FileTypes(); return

    case a.sep
    of "+=": dst.incl argAggSplit(a, false)
    of "-=": dst.excl argAggSplit(a, false)
    of ",=":                          # split-assign
      if first: dst = argAggSplit(a)
      else: dst.incl argAggSplit(a)
    of ",@=": dst = argAggSplit(a)    # split-clobber-assign
    of ",+=": dst.incl argAggSplit(a) # split-include
    of ",-=": dst.excl argAggSplit(a) # split-exclude
    else:
      a.msg = "Bad operator (\"$1\") for set of types, param $2\n" % [a.sep, a.key]
      raise newException(ElementError, "Bad operator")
  except:
    return false

func argHelp*(dfl: FileTypes, a: var ArgcvtParams): seq[string]=
  result = @[a.argKeys, "filetypes", "any"]

proc f*() =
  const nimbleFile = staticRead(currentSourcePath().parentDir.parentDir / "nimf.nimble")
  const commitID = staticExec("git log -n 1 --format=%H").strip() # Not sure if `.strip()` is necessary, wasn't for me
  clCfg.version = "nimf " & nimbleFile.fromNimble("version") & " " & commitID

  dispatch(cliFind,
           cmdName = "f",
           usage = (try: getAppFilename().lastPathPart except: "f") & " $args\n\n" &
                    "Entered `input` may be a pattern OR a path to search.\n" &
                    "The pattern will only match with the filename unless you include a `/`.\n" &
                    "\nOptions:\n$options",
           short = {"exclude": 'x', "types": 't', "max_depth": 'd', "follow_symlinks": 'L', "null": '0'},
           help = {"all": "Search all directories, including those ignored by default/your `.config/nimf/ignore.csv` file.",
                   "exclude": "Add patterns to ignore.",
                   "types": "Select which file type(s) to match. File type may be any|{l}file|{l}directory|{f/d}link or a file extension.",
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
                   "max-depth": "Set a maximum of how deep in the directory tree to search.",
                   "limit": "Limit the search to a number of results, alternatively end this argument with `ms` or `s` to limit the search based on time.",
                   "follow-symlinks": "Enable traversing symlinks.",
                   "color": "Enable or disable colored printing. Default is based on the `NO_COLOR` environment variable.",
                   "null": "Separate search results and split stdin with null characters `\\\\0` instead of newlines `\\\\n`.",
                   "hyperlink": "Enable clickable hyperlinks in supported terminals."})

when isMainModule:
  f()
