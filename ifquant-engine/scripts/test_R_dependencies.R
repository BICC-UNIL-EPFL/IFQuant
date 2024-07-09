#!/usr/bin/env Rscript

## Copyright (C) 2022 Julien Dorier and UNIL (University of Lausanne).
##
## This program is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or (at
## your option) any later version.
##
## This program is distributed in the hope that it will be useful, but
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
## General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program. If not, see <https://www.gnu.org/licenses/>.

packages=c(
"parallel",
"data.table",
"ggplot2",
"gridExtra",
"EBImage",
"NMF",
"viridis",
"gplots",
"KernSmooth",
"RColorBrewer",
"R.utils",
"writexl",
"geometry",
"igraph",
"RANN",
"rmarkdown",
"fastcluster",
"polyclip",
"RTriangle",
"optparse",
"sp"
)

success=sapply(packages,function(f){
    require(f,quietly=TRUE,character.only=TRUE,warn.conflicts=FALSE)
})

options(width=75)
sessionInfo()

if(!all(success))
{
    cat("Missing packages:\n")
    cat(paste(" ",packages[!success],collapse="\n"),"\n")
    quit(status=1)
}
