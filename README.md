[
Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
SPDX-License-Identifier: CC-BY-SA-4.0
]:#

# nimf

`find`-like, search for files in a directory hierarchy.

Features:
* Multithreaded and efficient ([faster than](#benchmarks) `find` and `fd`)
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
  -a, --all              bool           false  Search all directories, normally a few choice directories are skipped.
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

Benchmarks
---
#### 375,000 file directory:
|              | No pattern | 231,970 matches |
|--------------|------------|-----------------|
| f -ac=never  | 0.95s      | 0.55s           |
| fd -uc=never | 1.10s      | 0.73s           |
| f -a         | 1.17s      | 0.84s           |
| find         | 1.23s      | 0.96s           |
| fd -u        | 1.29s      | 0.96s           |

#### 1.75m file directory:
|       | No pattern | 1,028,205 matches | 14,075 matches |
|-------|------------|-------------------|----------------|
| f -a  | 6.91s      | 4.16s             | 0.38s          |
| find  | 7.30s      | 4.83s             | 1.25s          |
| fd -u | 9.62s      | 4.92s             | 0.96s          |

#### 4m file directory (my root dir):
|        | No pattern | 2,241,660 matches | 3 matches |
|--------|------------|-------------------|-----------|
| f -a   | 13.59s     | 9.54s             | 0.65s     |
| find   | 15.32s     | 10.88s            | 2.68s     |
| fd[^1] | 25.16s     | 11.32s            | N/A       |

[^1]: These measurements may be inaccurate, `fd` would not stop searching my drive (and pinning my CPU) so I had to watch for when it stopped printing results and SIGQUIT.  
As the **3 matches** search finished printing its results much earlier than it finished searching, I could not measure it. But for brevity, `fd` (when lucky) finished printing the 3 results in around 1.5s. With this same measuring, `f` finishes in around 0.35s and `find` around 0.7s.

---
[![GitHub CI](../../actions/workflows/build.yml/badge.svg?branch=master)](../../actions/workflows/build.yml)
[![Minimum supported Nim version](https://img.shields.io/badge/Nim-1.9.3+-informational?logo=Nim&labelColor=232733&color=F3D400)](https://nim-lang.org)
[![License](https://img.shields.io/github/license/Gruruya/nimf?logoColor=000000&logo=GNU&labelColor=FFFFFF&color=663366)](LICENSE.md)
