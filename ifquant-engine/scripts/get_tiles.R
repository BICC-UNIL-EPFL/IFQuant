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

##########################################
#parse command line options
##########################################
          
args=commandArgs(trailingOnly = TRUE)

library(optparse)

usage="
  %prog [options] image"

description="
Positional arguments:
\timage
\t\ta qptiff image."

epilogue="Notes:
 - showinf must be in the PATH (bftools https://www.openmicroscopy.org/bio-formats/).
 - Output list of tiles with size <tile-size>x<tile-size> to standard output (or file specified with --output),
   with one tile per line, using the following format x,y,width,height. (x,y) is the upper left corner the tile
   while width, height define its size (image coordinate system, in pixel).
"

#default=NA => mandatory, default=NULL => optional.
option_list=list( 
    make_option(c("--tile-size"), type="integer", default=2000,metavar="N",
                help="Generate tiles of sizes NxN pixels [default %default]."),
    make_option(c("--overlap"), type="integer", default=500,metavar="O",
                help="Overlap between neighboring tiles [default %default]."),
    make_option(c("--clip"), type="character", default=NULL,metavar="FILENAME",
                help="File with a region.
\t\tComma separated file with header in first row, one row per points and 3 columns id,x and y.
\t\tx and y coordinates in qptiff image coordinate system, i.e. pixels with origin at the upper left corner.
\t\tEverything outside of the bounding box of this region will be ignored."),
    make_option(c("--output"), type="character", default=NULL,metavar="FILENAME",
                help="Output file (txt file). If not specified, output to stdout.")
)


opt=parse_args(OptionParser(option_list=option_list,
                            usage=usage,
                            description=description,
                            epilogue=epilogue
                            ),positional_arguments=1,args=args)

##check all options are set, and print them
for(o in option_list)
{
    n=slot(o,"dest")
    f=c(slot(o,"short_flag"),slot(o,"long_flag"))
    f=paste(f[!is.na(f)],sep=",")
    if(!is.null(opt$options[[n]])) ##Default NULL => optional.
    {
        if(is.na(opt$options[[n]])) ##Default NA => mandatory
            stop("option ",f," is mandatory")
        ##check type
        if(typeof(opt$options[[n]])!=slot(o,"type"))
            stop("option ",f," must be ",slot(o,"type"))
        ##print
        if(slot(o,"action")!="store_true")
            cat(slot(o,"long_flag"),"=",opt$options[[n]],"\n",sep="",file=stderr())
        if(slot(o,"action")=="store_true"&&opt$options[[n]]==TRUE)
            cat(slot(o,"long_flag"),"\n",sep="",file=stderr())
    }
}
cat("positional arguments: ",paste(opt$args,collapse=" "),"\n",sep="",file=stderr())

tile.size=opt$options[["tile-size"]]
overlap=opt$options[["overlap"]]
clipfile=opt$options[["clip"]]
outputfile=opt$options[["output"]]


##positional arguments
inputfile=opt$args[1]



if(!is.null(outputfile))
    dir.create(dirname(outputfile),showWarnings=FALSE,recursive=TRUE)


###get info on image
cat("reading image information\n",file=stderr())
image.metadata=system2("showinf",args=c("-no-upgrade",paste0("\"",inputfile,"\""),"-nopix"),stdout=TRUE)

###WARNING:
## bftools coordinate systems (pixels) is 0-based, i.e. origin pixel is at position (0,0).
## R coordinate systems (pixels) is 1-based, i.e. origin pixel is at position (1,1).
image.width.pixel=as.numeric(gsub(".*: ","",grep("ImageWidth",image.metadata,value=TRUE)))
image.height.pixel=as.numeric(gsub(".*: ","",grep("ImageLength",image.metadata,value=TRUE)))

clip.region=c(x.min=0,y.min=0,x.max=image.width.pixel,y.max=image.height.pixel)
if(!is.null(clipfile))
{
    tmp=read.table(clipfile,sep=",",header=TRUE)
    clip.region=c(x.min=min(tmp$x),y.min=min(tmp$y),x.max=max(tmp$x),y.max=max(tmp$y))
}

x.min=max(0,clip.region["x.min"])
x.max=min(image.width.pixel,clip.region["x.max"])
y.min=max(0,clip.region["y.min"])
y.max=min(image.height.pixel,clip.region["y.max"])

tiles=NULL
if(x.max>x.min&&y.max>y.min)
{
    tiles.x=lapply(0:max(0,ceiling((x.max-x.min-tile.size)/(tile.size-overlap))),function(i){
        c(x=x.min+i*(tile.size-overlap),width=min(tile.size,x.max-x.min-i*(tile.size-overlap)))
    })
    tiles.y=lapply(0:max(0,ceiling((y.max-y.min-tile.size)/(tile.size-overlap))),function(i){
        c(y=y.min+i*(tile.size-overlap),height=min(tile.size,y.max-y.min-i*(tile.size-overlap)))
    })
    ##keep only tiles with finite sizes
    tiles.x=tiles.x[sapply(tiles.x,function(x){x["width"]>0})]
    tiles.y=tiles.y[sapply(tiles.y,function(x){x["height"]>0})]
    
    tiles=do.call("rbind",unlist(lapply(tiles.x,function(t.x){
        lapply(tiles.y,function(t.y){
            c(t.x["x"],t.y["y"],t.x["width"],t.y["height"])
        })
    }),recursive=FALSE))
}


if(!is.null(outputfile))cat("creating",outputfile,"\n",file=stderr())
if(is.null(outputfile))outputfile=""
write.table(tiles,file=outputfile,quote=FALSE,sep=",",row.names=FALSE,col.names=FALSE)
