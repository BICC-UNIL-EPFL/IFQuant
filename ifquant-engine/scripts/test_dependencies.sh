#!/bin/bash

# Copyright (C) 2022 Julien Dorier and UNIL (University of Lausanne).
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

#set -e: Any subsequent commands which fail will cause the shell script to exit immediately
#set -u unset variables treated as an error.
#set -o pipefail: sets the exit code of a pipeline to that of the rightmost command to exit with a non-zero status, or to zero if all commands of the pipeline exit successfully.
set -euo pipefail

echo "bfconvert:"
bfconvert -version 
echo

#echo "montage (ImageMagick):"
#montage -version
#echo

echo "vips:"
vips --version
echo

echo "tiffinfo:"
command -v tiffinfo 
echo
