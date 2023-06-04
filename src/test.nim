import ./f
import pkg/criterion
import strutils

var cfg = newDefaultConfig()

benchmark cfg:
  proc findba() {.measure.} =
    blackBox f.find("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaabaaaaaaaaaA", "ba")
