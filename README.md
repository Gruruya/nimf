# nimtemplate:scroll:

A template to jump start your Nim library or project.

* Tests using [balls](https://github.com/disruptek/balls)
* GitHub Actions [workflows](../../actions)
  * Runs tests on multiple OSes and ISAs
  * Builds and deploys [API reference on GitHub Pages](https://Gruruya.github.io/nimtemplate/nimtemplate.html)

_Click [here](../../../nimtemplate/generate) to begin_  

---
[![GitHub CI](../../actions/workflows/build.yml/badge.svg?branch=master)](../../actions/workflows/build.yml)
[![Minimum supported Nim version](https://img.shields.io/badge/Nim-1.6.12+-informational?logo=Nim&labelColor=232733&color=F3D400)](https://nim-lang.org)
[![License](https://img.shields.io/github/license/Gruruya/nimtemplate?logo=GNU&logoColor=000000&labelColor=FFFFFF&color=663366)](LICENSE.md)

Usage
---
You're gonna want to change the names in the project. I made a small utility for this, you can use it this way:
```sh
nim r rebrand.nim "PROJECT NAME" "DESCRIPTION" "AUTHOR" "EMAIL"
```

#### Note on the License
You can change the license freely in your project generated with this template.
