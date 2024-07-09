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
 - bfconvert and showinf must be in the PATH (bftools https://www.openmicroscopy.org/bio-formats/)
 - This script will create a directory <output>/saturation/ and populate it with saturation
   (i.e. pixels with any channel==255) mask tiles with name tile_<n>_<x>_<y>.png,
   with <n> the tile number (numbered by row), <x> and <y> the coordinates of the upper left corner. 
 - The saturation mask is green for regions without saturation and red for regions with at least one saturating channel.
"

#default=NA => mandatory, default=NULL => optional.
option_list=list( 
    make_option(c("--tmpdir"), type="character", default=NULL,metavar="DIRNAME",
                help="Directory to save temporary images [Default R tempdir()].
\t\tConsider using /dev/shm/."),
    make_option(c("--nprocesses"), type="integer", default=1,metavar="N",
                help="Number of processes [default %default].
\t\tEach process will create one image of size tile-size*tile-size  per channel on temp directory"),
    make_option(c("--clip"), type="character", default=NULL,metavar="FILENAME",
                help="File with a region.
\t\tAll pixels outside of the bounding box of this region will be set to 0.
\t\tComma separated file with header in first row, one row per points and 3 columns id,x and y.
\t\tx and y coordinates in qptiff image coordinate system, i.e. pixels with origin at the upper left corner."),
    make_option(c("--tile-size"), type="integer", default=2000,metavar="N",
                help="Work with tiles of sizes NxN pixels [default %default]."),
    make_option(c("--output"), type="character", default=NA,metavar="DIRNAME",
                help="Output directory [mandatory].")
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
            cat(slot(o,"long_flag"),"=",opt$options[[n]],"\n",sep="")
        if(slot(o,"action")=="store_true"&&opt$options[[n]]==TRUE)
            cat(slot(o,"long_flag"),"\n",sep="")
    }
}
cat("positional arguments: ",paste(opt$args,collapse=" "),"\n",sep="")

tmpdir=opt$options[["tmpdir"]]
nprocesses=opt$options[["nprocesses"]]
input.clip=opt$options[["clip"]]
tile.size=opt$options[["tile-size"]]
outputdir=opt$options[["output"]]


##check
if(is.null(tmpdir))
{
    tmpdir=tempdir()
    cat("using tmpdir=",tmpdir,"\n",sep="")
}
if(!(is.finite(nprocesses)&nprocesses>0))
{
    stop("--nprocesses must be a positive integer")
}


##positional arguments
input.image=opt$args[1]


library(parallel)
library(EBImage)
options(scipen=13)


dir.create(outputdir,showWarnings=FALSE,recursive=TRUE)

##temporary directory
tmpdir=paste0(tempfile(pattern="tmp",tmpdir=tmpdir),"/")
dir.create(tmpdir,showWarnings=FALSE,recursive=TRUE)

##temporary directory cleaning
clean=function(){
    cat(paste0("[",format(Sys.time()),"] "),"removing",tmpdir,"\n")
    unlink(tmpdir, recursive=TRUE)
}
##erase temporary directory on error    
if(!interactive())
    options(error=function(){clean();quit(status = 1)})


############################################
##functions
############################################

convert.image.to.tile.position.x=function(x,image.info){
    x-image.info[["tile.x"]]+1
}
convert.image.to.tile.position.y=function(y,image.info){
    y-image.info[["tile.y"]]+1
}


##############################################
##load image information
##############################################
###get info on image
cat(paste0("[",format(Sys.time()),"] "),"reading image information\n")
image.metadata=system2("showinf",args=c("-no-upgrade",paste0("\"",input.image,"\""),"-nopix"),stdout=TRUE)

###WARNING:
## bftools coordinate systems (pixels) is 0-based, i.e. origin pixel is at position (0,0).
## R coordinate systems (pixels) is 1-based, i.e. origin pixel is at position (1,1).
image.resolutionunit=gsub(".*: ","",grep("ResolutionUnit",image.metadata,value=TRUE))
image.xresolution=as.numeric(gsub(".*: ","",grep("XResolution",image.metadata,value=TRUE)))
image.yresolution=as.numeric(gsub(".*: ","",grep("YResolution",image.metadata,value=TRUE)))
image.xoffset=as.numeric(gsub(".*: ","",grep("XPosition",image.metadata,value=TRUE)))
image.yoffset=as.numeric(gsub(".*: ","",grep("YPosition",image.metadata,value=TRUE)))
image.width.pixel=as.numeric(gsub(".*: ","",grep("ImageWidth",image.metadata,value=TRUE)))
image.height.pixel=as.numeric(gsub(".*: ","",grep("ImageLength",image.metadata,value=TRUE)))
image.exposure.times=gsub(".*: ","",grep("^ExposureTime #",image.metadata,value=TRUE)) #qptiff
if(length(image.exposure.times)==0)
    image.exposure.times=strsplit(gsub(".*\\[(.*)\\]","\\1",grep("^ExposureTime:",image.metadata,value=TRUE)),", ")[[1]] #ome.tif
image.exposure.times=as.numeric(image.exposure.times)
names(image.exposure.times)=paste0("channel_",(1:length(image.exposure.times))-1)
image.channel.names=gsub(".*: ","",grep("^Name #",image.metadata,value=TRUE)) #qptiff
if(length(image.channel.names)==0)
    image.channel.names=strsplit(gsub(".*\\[(.*)\\]","\\1",grep("^Name:",image.metadata,value=TRUE)),", ")[[1]] #ome.tif
names(image.channel.names)=paste0("channel_",(1:length(image.channel.names))-1)
image.info=list(
    image.resolutionunit=image.resolutionunit,
    image.xresolution=image.xresolution,
    image.yresolution=image.yresolution,
    image.xoffset=image.xoffset,
    image.yoffset=image.yoffset,
    image.width.pixel=image.width.pixel,
    image.height.pixel=image.height.pixel,
    image.exposure.times=image.exposure.times/1e6, ##convert from microseconds to seconds
    image.channel.names=image.channel.names
)



##clip region
clip.region=c(x.min=0,y.min=0,x.max=image.info$image.width.pixel,y.max=image.info$image.height.pixel)
if(!is.null(input.clip))
{
    tmp=read.table(input.clip,sep=",",header=TRUE)
    clip.region=c(x.min=min(tmp$x),y.min=min(tmp$y),x.max=max(tmp$x),y.max=max(tmp$y))
}





##############################################
##tile list
##############################################

##prepare tiles list
tiles.x=lapply(0:floor(image.width.pixel/tile.size),function(i){
    c(x=i*tile.size,width=min(tile.size,image.width.pixel-i*tile.size))
})
tiles.y=lapply(0:floor(image.height.pixel/tile.size),function(i){
    c(y=i*tile.size,height=min(tile.size,image.height.pixel-i*tile.size))
})
##keep only tiles with finite sizes
tiles.x=tiles.x[sapply(tiles.x,function(x){x["width"]>0})]
tiles.y=tiles.y[sapply(tiles.y,function(x){x["height"]>0})]
##by rows
tiles=unlist(lapply(tiles.y,function(t.y){
    lapply(tiles.x,function(t.x){
        c(t.x,t.y)
    })
}),recursive=FALSE)

##add n
for(n in 1:length(tiles))
    tiles[[n]]=c(tiles[[n]],n=n)

cat(paste0("[",format(Sys.time()),"] "),length(tiles),"tiles\n")


###############################
##create tiles
###############################

d=paste0(outputdir,"/saturation")
cat(paste0("[",format(Sys.time()),"] "),"creating",d,"\n")    
dir.create(d,showWarnings=FALSE,recursive=TRUE)



cl <- makeCluster(nprocesses,outfile="")
clusterEvalQ(cl, {
    library(data.table)
    library(EBImage)
    setDTthreads(1)
    options(scipen=13)
})
clusterExport(cl, c("input.image","tmpdir","image.info","outputdir","clip.region","convert.image.to.tile.position.x","convert.image.to.tile.position.y"))


invisible(parLapply(cl,tiles,function(tile){
    cat(paste0("[",format(Sys.time()),"] "),"Tile",tile[["n"]],": x=",tile[["x"]]," y=",tile[["y"]]," width=",tile[["width"]]," height=",tile[["height"]],"\n")

    
    tmpfile=tempfile(fileext="_channel_%c.png",tmpdir=tmpdir)
    cat(paste0("[",format(Sys.time()),"] "),"temp file:",tmpfile,"\n")
    cat(paste0("[",format(Sys.time()),"] "),"bfconvert","-no-upgrade",paste0("-crop ",tile[["x"]],",",tile[["y"]],",",tile[["width"]],",",tile[["height"]]),"-series 0",input.image,tmpfile,"\n")
    system2("bfconvert",args=c("-no-upgrade",paste0("-crop ",tile[["x"]],",",tile[["y"]],",",tile[["width"]],",",tile[["height"]]),"-series 0",paste0("\"",input.image,"\""),paste0("\"",tmpfile,"\"")))

    files=list.files(tmpdir,pattern=gsub("_channel_%c.png","_channel_[0-9]*.png",basename(tmpfile)),full.name=TRUE)
    image.saturation=Reduce("|",lapply(files,function(f)
    {
        channel=gsub(".*_(channel_[0-9]*).*","\\1",basename(f))
        image=readImage(f)
        image=image
        file.remove(f)
        image>0.99999
    }))


    ##ignore regions outside clip.region
    image.info.tile=image.info
    image.info.tile$tile.x=tile[["x"]]
    image.info.tile$tile.y=tile[["y"]]
    image.info.tile$tile.width=tile[["width"]]
    image.info.tile$tile.height=tile[["height"]]
    clip.region.tile=c(convert.image.to.tile.position.x(clip.region["x.min"],image.info.tile),
                       convert.image.to.tile.position.y(clip.region["y.min"],image.info.tile),
                       convert.image.to.tile.position.x(clip.region["x.max"],image.info.tile),
                       convert.image.to.tile.position.y(clip.region["y.max"],image.info.tile))
    clip.region.tile=c(x.min=min(image.info.tile$tile.width+1,max(1,clip.region.tile["x.min"])),
                       y.min=min(image.info.tile$tile.height+1,max(1,clip.region.tile["y.min"])),
                       x.max=min(image.info.tile$tile.width,max(0,clip.region.tile["x.max"])),
                       y.max=min(image.info.tile$tile.height,max(0,clip.region.tile["y.max"])))
    if(clip.region.tile["x.min"]>1)
        image.saturation[1:(clip.region.tile["x.min"]-1),]=0
    if(clip.region.tile["y.min"]>1)
        image.saturation[,1:(clip.region.tile["y.min"]-1)]=0
    if(clip.region.tile["x.max"]<image.info.tile$tile.width)
        image.saturation[(clip.region.tile["x.max"]+1):image.info.tile$tile.width,]=0
    if(clip.region.tile["y.max"]<image.info.tile$tile.height)
        image.saturation[,(clip.region.tile["y.max"]+1):image.info.tile$tile.height]=0
    
    ##convert to rgb.
    image.saturation=rgbImage(image.saturation,1-image.saturation,image.saturation*0)

    ##save
    filename=paste0(outputdir,"/saturation/tile_",sprintf("%09d", tile[["n"]]),"_",tile[["x"]],"_",tile[["y"]],".png")
    cat(paste0("[",format(Sys.time()),"] "),"creating",filename,"\n")
    writeImage(image.saturation,filename)
    return(NULL)
}))

stopCluster(cl)

clean()
cat(paste0("[",format(Sys.time()),"] "),"Done\n")
