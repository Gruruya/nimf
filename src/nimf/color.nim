# CLI coloring --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## Color support for the CLI, parsed from `LS_COLORS`
import ./[common, text], pkg/lscolors/entrytypes,
       std/[posix, os, options, tables]
import pkg/lscolors except parseLsColors, LsColors
from   std/strutils import split

type
  LSColors* = object
    ## Holds parsed LS_COLORS
    types*: TableRef[EntryType, string]
    patterns*: TableRef[string, string]
    extensions*: TableRef[string, string]
    lnTarget*: bool
  RawRule = object
    ## Basically a string pair
    pattern*: string
    color*: string

func init*(T: type LSColors): LSColors =
  result.types = newTable[EntryType, string]()
  result.patterns = newTable[string, string]()
  result.extensions = newTable[string, string]()

const ansiResetCode* = "\e[0m"
const ansiDefaultForeground* = "\e[00m"

template ansiCode*(s: string): string =
  "\e[" & s & 'm'

proc rawParse(str: string): seq[RawRule] =
  for rule in str.split(':'):
    let splitted = rule.split('=')
    if splitted.len == 2:
      result.add(RawRule(pattern: splitted[0], color: splitted[1]))

proc getExtension*(path: string): string {.inline.} =
  for i in countDown(path.high, path.low):
    case path[i]
    of '/': break
    of '.': return path[i + 1..^1]
    else: discard

proc parseLSColors*(str: string): LSColors =
  ## Parse a LS_COLORS string
  result = LSColors.init()
  let raw = rawParse(str)
  for rule in raw:
    template code: untyped = ansiCode(rule.color)
    if rule.pattern == "ln" and rule.color == "target":
      result.lnTarget = true
    else:
      if (let entryType = rule.pattern.strToEntryType; entryType.isSome):
        result.types[entryType.get] = code
      else:
        if rule.pattern.len > 2 and rule.pattern[0..1] == "*.":
              result.extensions[rule.pattern.getExtension] = code
        else: result.patterns[rule.pattern] = code

proc parseLSColorsEnv*(varName = "LS_COLORS"): LSColors =
  ## Parses the LS_COLORS environment variable. Defaults to `defaultLsColors`
  ## when no such environment variable exists
  if existsEnv(varName):
    parseLSColors(getEnv(varName))
  else:
    const default = "rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.zst=01;31:*.tzst=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.wim=01;31:*.swm=01;31:*.dwm=01;31:*.esd=01;31:*.jpg=01;35:*.jpeg=01;35:*.mjpg=01;35:*.mjpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.oga=00;36:*.opus=00;36:*.spx=00;36:*.xspf=00;36:"
    parseLSColors(default)

proc pathEntryType*(found: Found): EntryType =
  ## Determines the entry type of this path
  case found.kind
  of pcDir: etDirectory
  of pcLinkToDir: etSymbolicLink
  of pcLinkToFile:
    if found.broken: etOrphanedSymbolicLink
    else: etSymbolicLink
  else:
    let mode =
      if found.stat.isNone:
        var stat : Stat
        discard lstat(found.path.cstring, stat)
        stat.st_mode
      else: found.stat.unsafeGet.st_mode
    if S_ISBLK(mode): etBlockDevice
    elif S_ISCHR(mode): etCharacterDevice
    elif S_ISFIFO(mode): etFIFO
    elif S_ISSOCK(mode): etSocket
    elif (mode.cint and S_ISUID) != 0'i32: etSetuid
    elif (mode.cint and S_ISGID) != 0'i32: etSetgid
    elif (mode.cint and S_ISVTX) != 0'i32: etSticky
    elif S_ISREG(mode):
      # Check if this file is executable
      if (mode.cint and S_IXUSR) != 0'i32 or
         (mode.cint and S_IXGRP) != 0'i32 or
         (mode.cint and S_IXOTH) != 0'i32: etExecutableFile
      else: etRegularFile
    else: etNormal

proc styleForDirEntry*(lsc: LSColors, entry: Entry): string =
  ## Returns the style which should be used for this specific entry
  # Special case: inherit style from target
  if entry.typ == etSymbolicLink and lsc.lnTarget:
    let target = entry.path.expandSymlink
    styleForDirEntry(lsc, Entry(path: target, typ: target.pathEntryType()))

  # Pick style from type
  elif entry.typ != etNormal and entry.typ != etRegularFile:
    # result = if lsc.types.hasKey(entry.typ): lsc.types[entry.typ] else: defaultStyle()
    lsc.types.getOrDefault(entry.typ, ansiResetCode)

  # Pick style from path
  else:
    try: return lsc.extensions[entry.path.getExtension]
    except:
      for pattern, style in lsc.patterns.pairs:
        if entry.path == pattern:
          return style
    lsc.types.getOrDefault(entry.typ, ansiResetCode)

proc styleForPath*(lsc: LSColors, found: Found): string {.inline.} =
  styleForDirEntry(lsc, Entry(path: found.path.string, typ: found.pathEntryType()))

template add(x: var string, y: varargs[string]) =
  for j in y: system.add(x, j)


var colorConf*: LSColors

proc color*(found: Found, patterns: openArray[string]): string =
  template path: untyped = found.path.string
  let parentSep =
    if path.len == 1: -1
    else: path.rfind("/", last = path.high - 1).getIt(it.int, -1)

  let dirColor = colorConf.types.getOrDefault(etDirectory, ansiResetCode)
  let fileColor =
    if found.kind == pcDir: dirColor # optimization
    else: colorConf.styleForPath(found)
  let highlightColor =
    if likely ansiCode("01;31") notin [dirColor, fileColor]: ansiCode("01;31") # Bright red
    elif ansiCode("01;33") notin [dirColor, fileColor]: ansiCode("01;33") # Bright yellow
    else: ansiCode("01;36") # Bright cyan (other colors are red and yellow)

  if patterns == @[""]:
    if parentSep != -1: result = dirColor & path[0..parentSep]
    result.add fileColor & path[parentSep + 1..^1] & ansiResetCode
  else:
    var start = 0
    for i in 0..found.matches.high:
      let matchStart = found.matches[i][0]
      let matchEnd = found.matches[i][1]

      if parentSep < start:
        result.add fileColor, path[start ..< matchStart]
      elif dirColor == fileColor or parentSep >= matchStart:
        result.add dirColor, path[start ..< matchStart]
      else:
        result.add dirColor, path[start .. parentSep]
        result.add fileColor, path[parentSep + 1 ..< matchStart]

      result.add highlightColor, path[matchStart..matchEnd]
      start = matchEnd + 1

    if start != path.len:
      if start > parentSep or dirColor == fileColor:
        result.add fileColor, path[start..path.high]
      else:
        result.add dirColor, path[start .. parentSep]
        result.add fileColor, path[parentSep + 1 .. path.high]

    result.add ansiResetCode

when isMainModule:
  colorConf = parseLSColorsEnv()
  let lo = Found(path: Path "color.nim", matches: @[(2, 3)])
  echo color(lo, @["lo"])
