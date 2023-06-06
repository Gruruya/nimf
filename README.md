# nimf

`find`-like  
_search for files in a directory hierarchy_

Usage
---
```sh
Usage:
  f [optional-params] [input: string...]
Options:
  -h, --help                    print this cligen-erated help
  --help-syntax                 advanced: prepend,plurals,..
  -c, --color    bool     true  set color
  -x=, --exec=   strings  {}    Execute a command for each matching search result in parallel.
                                Alternatively, end this argument with "+" to execute the command once with all results as arguments.
                                Example: f .nim -x "$EDITOR"+
                                The following placeholders are substituted before the command is executed:
                                "{}":   path (of the current search result)
                                "{/}":  basename
                                "{//}": parent directory
                                "{.}":  path without file extension
                                "{/.}": basename without file extension
                                Example: f .jpg -x 'convert {} {.}.png'
                                If no placeholder is present, an implicit "{}" at the end is assumed.
```

---
[![GitHub CI](../../actions/workflows/build.yml/badge.svg?branch=master)](../../actions/workflows/build.yml)
[![Minimum supported Nim version](https://img.shields.io/badge/Nim-1.9.3+-informational?logo=Nim&labelColor=232733&color=F3D400)](https://nim-lang.org)
[![License](https://img.shields.io/github/license/Gruruya/nimf?logo=GNU&logoColor=000000&labelColor=FFFFFF&color=663366)](LICENSE.md)
