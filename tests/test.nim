# Tests --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

#TODO: This module

import pkg/balls
import ../src/nimf/find

suite "finding":
  block basic:
    check "hello, world!".find("w") == "hello, world!".rfind("w")
