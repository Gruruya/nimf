[
Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
SPDX-License-Identifier: CC-BY-SA-4.0
]:#

# nimf

`find`-like, quickly search for files in a directory hierarchy.

Highlights:
* Multithreaded and efficient
* Mostly intuitive, and simple interface

Usage
---
```sh
Usage:
  f [optional-params] [input: string...]

Entered `input` may be a pattern OR a path to search.
The pattern will only match with the filename unless you include a `/`.

Options:
  -h, --help                                   print this cligen-erated help
  --help-syntax                                advanced: prepend,plurals,..
  --version              bool           false  print version
  -t=, --types=          set(filetype)  any    Select which file kind(s) to match. File kinds include any|file|directory|link.
  -e=, --execute=        strings        {}     Execute a command for each matching search result in parallel.
                                               Alternatively, end this argument with "+" to execute the command once with all results as arguments.
                                               Example: f .nim -e "$EDITOR"+
                                               The following placeholders are substituted before the command is executed:
                                               "{}":   path (of the current search result)
                                               "{/}":  basename
                                               "{//}": parent directory
                                               "{.}":  path without file extension
                                               "{/.}": basename without file extension
                                               Example: f .jpg -e 'convert {} {.}.png'
                                               If no placeholder is present, an implicit " {}" at the end is assumed.
  -d=, --max-depth=      int            0      set max_depth
  -L, --follow-symlinks  bool           false  set follow_symlinks
  -0, --null             bool           false  Separate search results and split stdin with null characters `\0` instead of newlines `\n`.
  -c, --color            flag           auto   Enable or disable colored printing. Default is based on the `NO_COLOR` environment variable.
  --hyperlink            flag           false  Enable clickable hyperlinks in supported terminals.
```

---
[![GitHub CI](../../actions/workflows/build.yml/badge.svg?branch=master)](../../actions/workflows/build.yml)
[![Minimum supported Nim version](https://img.shields.io/badge/Nim-1.9.3+-informational?logo=Nim&labelColor=232733&color=F3D400)](https://nim-lang.org)
[![License](https://img.shields.io/github/license/Gruruya/nimf?logoColor=000000&logo=GNU&labelColor=FFFFFF&color=663366)](LICENSE.md)
