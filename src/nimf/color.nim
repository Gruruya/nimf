# CLI coloring --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

## Color support for the CLI, parsed from `LS_COLORS`
import ./common, pkg/lscolors/entrytypes,
       std/[posix, os, tables, options], adix/lptabz
import pkg/lscolors except parseLsColors, LsColors
from   std/terminal import ansiResetCode
from   std/strutils import split
export entrytypes, ansiResetCode

type
  LSColors* = object
    ## Holds parsed LS_COLORS
    types*: TableRef[EntryType, string]
    patterns*: LPTabz[string, string, int8, 6]
    extensions*: LPTabz[string, string, int8, 6]
    lnTarget*: bool
  RawRule = object
    ## Basically a string pair
    pattern*: string
    color*: string

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
  # result.types = initLPTabz[EntryType, string, int8, 6]()
  result.types = newTable[EntryType, string]()
  result.patterns = initLPTabz[string, string, int8, 6]()
  result.extensions = initLPTabz[string, string, int8, 6]()

  let raw = rawParse(str)
  for rule in raw:
    template code: untyped = "\e[" & rule.color & 'm'
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
    if S_ISBLK(found.stat.st_mode): etBlockDevice
    elif S_ISCHR(found.stat.st_mode): etCharacterDevice
    elif S_ISFIFO(found.stat.st_mode): etFIFO
    elif S_ISSOCK(found.stat.st_mode): etSocket
    elif (found.stat.st_mode.cint and S_ISUID) != 0'i32: etSetuid
    elif (found.stat.st_mode.cint and S_ISGID) != 0'i32: etSetgid
    elif (found.stat.st_mode.cint and S_ISVTX) != 0'i32: etSticky
    elif S_ISREG(found.stat.st_mode):
      # Check if this file is executable
      if (found.stat.st_mode.cint and S_IXUSR) != 0'i32 or
         (found.stat.st_mode.cint and S_IXGRP) != 0'i32 or
         (found.stat.st_mode.cint and S_IXOTH) != 0'i32: etExecutableFile
      else: etRegularFile
    else: etNormal

proc styleForDirEntry*(lsc: LSColors, entry: Entry): string =
  ## Returns the style which should be used for this specific entry
  # Special case: inherit style from target
  if entry.typ == etSymbolicLink and lsc.lnTarget:
    let target = entry.path.expandSymlink
    return styleForDirEntry(lsc, Entry(path: target, typ: target.pathEntryType()))

  # Pick style from type
  elif entry.typ != etNormal and entry.typ != etRegularFile:
    # result = if lsc.types.hasKey(entry.typ): lsc.types[entry.typ] else: defaultStyle()
    return lsc.types.getOrDefault(entry.typ, ansiResetCode)

  # Pick style from path
  else:
    try: return lsc.extensions[entry.path.getExtension]
    except:
      for pattern, style in lsc.patterns.pairs:
        if entry.path == pattern:
          return style
  result = ansiResetCode

proc styleForPath*(lsc: LSColors, found: Found): string {.inline.} =
  styleForDirEntry(lsc, Entry(path: found.path.string, typ: found.pathEntryType()))
