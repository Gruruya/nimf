# nimtemplate --- A template to jump start your Nim library or project.
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
#
# This file is part of nimtemplate.
#
# nimtemplate is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, version 3 of the License.
#
# nimtemplate is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with nimtemplate.  If not, see <http://www.gnu.org/licenses/>.

## Script to rebrand this template repository.

import std/[os, strutils]

let input = commandLineParams()
if input.len notin {2, 4}:
  echo "Usage: rebrand [PROJECT NAME] [DESCRIPTION] [AUTHOR] [EMAIL]"
  quit 1

let name = input[0]
let description = input[1]

for file in ["README.md", "nimtemplate.nimble", "src/nimtemplate.nim", "src/nimtemplate/common.nim", "tests/test.nim", ".github/workflows/build.yml", ".github/workflows/documentation.yml", ".github/workflows/nim-run/action.yml"]:
  file.writeFile file.readFile.multiReplace(("nimtemplate", name), ("A template to jump start your Nim library or project.", description))

if input.len == 4:
  let author = input[2]
  let email = input[3]

  for file in ["README.md", "nimtemplate.nimble", "src/nimtemplate.nim", "src/nimtemplate/common.nim", "tests/test.nim", ".github/workflows/build.yml", ".github/workflows/documentation.yml", ".github/workflows/nim-run/action.yml"]:
    file.writeFile file.readFile.multiReplace(("Gruruya", author), ("gruruya.chi4c@slmails.com", email))

  "rebrand.nim".writeFile "rebrand.nim".readFile.multiReplace(("nimtemplate", name), ("A template to jump start your Nim library or project.", description), ("Gruruya", author), ("gruruya.chi4c@slmails.com", email))
else:
  "rebrand.nim".writeFile "rebrand.nim".readFile.multiReplace(("nimtemplate", name), ("A template to jump start your Nim library or project.", description))

moveFile("nimtemplate.nimble", name & ".nimble")
moveFile("src/nimtemplate.nim", "src/" & name & ".nim")
moveDir("src/nimtemplate", "src/" & name)

echo "Done"
