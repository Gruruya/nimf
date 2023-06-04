# f --- Text finder
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
#
# This file is part of f.
#
# f is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, version 3 of the License.
#
# f is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with f.  If not, see <http://www.gnu.org/licenses/>.

## This is just an example to get you started. You may wish to put all of your
## tests into a single file, or separate them into multiple `test1`, `test2
## etc. files (better names are recommended, just make sure the name starts with
## the letter 't').
##
## To run these tests, simply execute `nimble test`.

import pkg/balls
import ./f

suite "example":
  block operation:
    check 1 + 1 == 2
