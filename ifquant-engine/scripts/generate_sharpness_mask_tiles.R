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
 - Rownames in unmixing-parameters must correspond to channel names in the qptiff image
   metadata (field \"Name #\" in output of showinf -nopix <inputfile>)
 - This script will create a directory <output>/sharpnes/ and populate it with DAPI sharpness mask
   tiles with name tile_<n>_<x>_<y>.png, with <n> the tile number (numbered by row),
   <x> and <y> the coordinates of the upper left corner.
 - Color coding in the sharpness mask: empty region (white), low dapi (grey),
   DAPI sharpness failed (red), DAPI sharpness warning (yellow), DAPI sharpness OK (green).
"

#default=NA => mandatory, default=NULL => optional.
option_list=list( 
    make_option(c("--tmpdir"), type="character", default=NULL,metavar="DIRNAME",
                help="Directory to save temporary images [Default R tempdir()].
\t\tConsider using /dev/shm/."),
    make_option(c("--nprocesses"), type="integer", default=1,metavar="N",
                help="Number of processes [default %default].
\t\tEach process will create one image of size tile-size*tile-size per channel on temp directory"),
    make_option(c("--clip"), type="character", default=NULL,metavar="FILENAME",
                help="File with a region.
\t\tAll pixels outside of the bounding box of this region will be set to 0.
\t\tComma separated file with header in first row, one row per points and 3 columns id,x and y.
\t\tx and y coordinates in qptiff image coordinate system, i.e. pixels with origin at the upper left corner."),
    make_option(c("--tile-size"), type="integer", default=2000,metavar="N",
                help="Work with tiles of sizes NxN pixels [default %default]."),
    make_option(c("--metadata"), type="character", default=NA,metavar="FILENAME",
                help="File with panel metadata [mandatory].
\t\tTab separated file with header in the first row and at least three columns
\t\t * channel: channel number (0,1,2,...). Should correspond to channel number in the qptiff image, using 0-based indexing.
\t\t * name: channel name (DAPI, CD15,...).
\t\t * type: channel type, must take one the following values (multiple values must be comma separated, e.g. \"tumor,nucleus2\"):
\t\t   - nucleus: channel used for nuclei segmentation. Exactly one channel should have type \"nucleus\".
\t\t   - nucleus2: additional channel used for nuclei segmentation. Several channels can have type \"nucleus2\".
\t\t               It is strongly discouraged to use an additional channel for nucleus segmentation
\t\t   - tumor: channel used for tissue segmentation. Exactly one channel should have type \"tumor\".
\t\t   - AF: autofluorescence channel. Exactly one channel should have type \"AF\".
\t\t   - NA: other channels."),
    make_option(c("--unmixing-parameters"), type="character", default=NA,metavar="FILENAME",
                help="File with unmixing parameters (output of get_unmixing_parameters.R) [mandatory]."),
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
input.metadata=opt$options[["metadata"]]
input.unmix.params=opt$options[["unmixing-parameters"]]
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
##parameters
############################################
sharpness.diameter.micron=20 ##sharpness is evaluated by averaging gradient over a disc of diameter sharpness.diameter.micron (in micron).
sharpness.low.threshold=0.5 ##sharpness below this cutoff is considered as WARNING
sharpness.high.threshold=3 ##sharpness above this cutoff is considered as good
watershed.low.dapi=1 ##everything with blurred dapi signal <=watershed.low.signal is considered as no dapi (when searching for nuclei).
blur.sigma.nosignal.micron=2.5 #To detect regions without dapi signal: blur dapi image
threshold.low.dapi=watershed.low.dapi

############################################
##functions
############################################
##simple unmixing method
unmix_images=function(images.list,unmixing.parameters){
    if(!identical(sort(colnames(unmixing.parameters$W_inv)),sort(names(images.list))))
    {
        cat("ERROR: could not match unmixing parameters channel names to image channel names\n")
        cat(" unmixing paramters channel names:\n")
        cat("  ",paste(colnames(unmixing.parameters$W_inv),collapse=", "),"\n")
        cat(" Image channel names:\n")
        cat("  ",paste(names(images.list),collapse=", "),"\n")
        stop("unmix_images(): problem with unmixing parameters")
    }
    
    unmixed.images=images.list
    names(unmixed.images)=rownames(unmixing.parameters$W_inv)
    for(e in rownames(unmixing.parameters$W_inv))
    {
        unmixed.images[[e]]=unmixed.images[[e]]*0
        for(r in colnames(unmixing.parameters$W_inv))
        {
            unmixed.images[[e]]=unmixed.images[[e]]+unmixing.parameters$W_inv[e,r]*(images.list[[r]]-unmixing.parameters$Offset[r])
        }
        unmixed.images[[e]][unmixed.images[[e]]<0]=0
    }
    unmixed.images
}

convert.image.to.tile.position.x=function(x,image.info){
    x-image.info[["tile.x"]]+1
}
convert.image.to.tile.position.y=function(y,image.info){
    y-image.info[["tile.y"]]+1
}

convert.slide.to.tile.length=function(x,image.info){
    if(image.info[["image.xresolution"]]!=image.info[["image.yresolution"]])
        stop("cannot convert a length to micron when XResolution!=YResolution")
    round(x*image.info[["image.xresolution"]]/10000)
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

metadata=read.table(input.metadata,header=TRUE,stringsAsFactors=FALSE,sep="\t")
rownames(metadata)=paste0("channel_",metadata$channel)

##add channel name from image info
metadata$image.channel.name=image.info$image.channel.names[rownames(metadata)]

##load unmixing parameters
tmp=read.table(input.unmix.params,sep=",",header=TRUE,check.names=FALSE)
tmp.basis=as.matrix(tmp[,-c(1,2)])
rownames(tmp.basis)=tmp[,1]
tmp.offset=as.vector(tmp[,2])
names(tmp.offset)=tmp[,1]
unmixing.parameters=list(W=tmp.basis,W_inv=solve(tmp.basis),Offset=tmp.offset)
##check measured channel names 
if(!all(rownames(unmixing.parameters$W)%in%metadata$image.channel.name)||!all(metadata$image.channel.name%in%rownames(unmixing.parameters$W)))
{
    cat("ERROR: could not match unmixing parameters channel names to image channel names\n")
    cat(" unmixing paramters channel names:\n")
    cat("  ",paste(rownames(unmixing.parameters$W),collapse=", "),"\n")
    cat(" Image channel names:\n")
    cat("  ",paste(metadata$image.channel.name,collapse=", "),"\n")
    stop("problem with unmixing parameters (not the same channel names as image)")
}
##rename  measured channel to channel_*
ind=match(rownames(unmixing.parameters$W),metadata$image.channel.name)
rownames(unmixing.parameters$W)=rownames(metadata)[ind]
names(unmixing.parameters$Offset)=rownames(metadata)[ind]
colnames(unmixing.parameters$W_inv)=rownames(metadata)[ind]

##find match between fluorophores and channels and rename to channel_*
ind=match(gsub(".*af.*|.*autofluo.*","autofluo",gsub(".*dapi.*","dapi",gsub(".*[o].*[^0-9]([0-9]+)","\\1",tolower(colnames(unmixing.parameters$W))))),gsub(".*af.*|.*autofluo.*","autofluo",gsub(".*dapi.*","dapi",gsub(".*[o].*[^0-9]([0-9]+)","\\1",tolower(metadata$image.channel.name)))))
if(any(is.na(ind)))
{
    cat("ERROR: could not match unmixing parameters fluorophore names to image channel names\n")
    cat(" unmixing paramters fluorophores names:\n")
    cat("  ",paste(colnames(unmixing.parameters$W),collapse=", "),"\n")
    cat(" Image channel names:\n")
    cat("  ",paste(metadata$image.channel.name,collapse=", "),"\n")
    stop("problem with unmixing parameters (not the same channel names as image)")
}
colnames(unmixing.parameters$W)=rownames(metadata)[ind]
rownames(unmixing.parameters$W_inv)=rownames(metadata)[ind]


##clip region
clip.region=c(x.min=0,y.min=0,x.max=image.info$image.width.pixel,y.max=image.info$image.height.pixel)
if(!is.null(input.clip))
{
    tmp=read.table(input.clip,sep=",",header=TRUE)
    clip.region=c(x.min=min(tmp$x),y.min=min(tmp$y),x.max=max(tmp$x),y.max=max(tmp$y))
}


sharpness.diameter.pixel=convert.slide.to.tile.length(sharpness.diameter.micron,image.info)
blur.sigma.nosignal=convert.slide.to.tile.length(blur.sigma.nosignal.micron,image.info)

input.dapi=rownames(metadata)[sapply(strsplit(metadata$type,","),function(x){"nucleus"%in%x})]

##find alternative nucleus channels (channels with type "nucleus2")
input.nuc2.list=rownames(metadata)[sapply(strsplit(metadata$type,","),function(x){"nucleus2"%in%x})]

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

d=paste0(outputdir,"/sharpness")
cat(paste0("[",format(Sys.time()),"] "),"creating",d,"\n")    
dir.create(d,showWarnings=FALSE,recursive=TRUE)



cl <- makeCluster(nprocesses,outfile="")
clusterEvalQ(cl, {
    library(data.table)
    library(EBImage)
    setDTthreads(1)
    options(scipen=13)
})
clusterExport(cl, c("input.image","tmpdir","image.info","unmix_images","unmixing.parameters","metadata","outputdir","clip.region","convert.image.to.tile.position.x","convert.image.to.tile.position.y","sharpness.diameter.pixel","sharpness.low.threshold","sharpness.high.threshold","blur.sigma.nosignal","threshold.low.dapi","input.dapi","input.nuc2.list"))


invisible(parLapply(cl,tiles,function(tile){
    cat(paste0("[",format(Sys.time()),"] "),"Tile",tile[["n"]],": x=",tile[["x"]]," y=",tile[["y"]]," width=",tile[["width"]]," height=",tile[["height"]],"\n")

    ##add margin to avoid boundary effect
    margin.x1=max(1,ceiling(sharpness.diameter.pixel/2)+1)
    margin.x2=max(1,ceiling(sharpness.diameter.pixel/2)+1)
    margin.y1=max(1,ceiling(sharpness.diameter.pixel/2)+1)
    margin.y2=max(1,ceiling(sharpness.diameter.pixel/2)+1)
    margin.x1=min(margin.x1,tile[["x"]])
    margin.y1=min(margin.y1,tile[["y"]])
    margin.x2=min(margin.x2,image.info[["image.width.pixel"]]-(tile[["x"]]+tile[["width"]]))
    margin.y2=min(margin.y2,image.info[["image.height.pixel"]]-(tile[["y"]]+tile[["height"]]))

    
    tmpfile=tempfile(fileext="_channel_%c.png",tmpdir=tmpdir)
    cat(paste0("[",format(Sys.time()),"] "),"temp file:",tmpfile,"\n")
    cat(paste0("[",format(Sys.time()),"] "),"bfconvert","-no-upgrade",paste0("-crop ",tile[["x"]]-margin.x1,",",tile[["y"]]-margin.y1,",",tile[["width"]]+margin.x1+margin.x2,",",tile[["height"]]+margin.y1+margin.y2),"-series 0",input.image,tmpfile,"\n")
    system2("bfconvert",args=c("-no-upgrade",paste0("-crop ",tile[["x"]]-margin.x1,",",tile[["y"]]-margin.y1,",",tile[["width"]]+margin.x1+margin.x2,",",tile[["height"]]+margin.y1+margin.y2),"-series 0",paste0("\"",input.image,"\""),paste0("\"",tmpfile,"\"")))
    files=list.files(tmpdir,pattern=gsub("_channel_%c.png","_channel_[0-9]*.png",basename(tmpfile)),full.name=TRUE)
    images=lapply(files,function(f)
    {
        channel=gsub(".*_(channel_[0-9]*).*","\\1",basename(f))
        image=readImage(f)
        image=image/image.info$image.exposure.times[channel]
        file.remove(f)
        image
    })
    names(images)=gsub(".*_(channel_[0-9]*).*","\\1",basename(files))

    ##ignore regions with all values at zero (set to NA)
    image.is.valid=sign(Reduce("+",images))!=0 #TRUE if not all zero, FALSE if all channels at 0
    ##ignore regions outside clip.region
    image.info.tile=image.info
    image.info.tile$tile.x=tile[["x"]]-margin.x1
    image.info.tile$tile.y=tile[["y"]]-margin.y1
    image.info.tile$tile.width=tile[["width"]]+margin.x1+margin.x2
    image.info.tile$tile.height=tile[["height"]]+margin.y1+margin.y2
    clip.region.tile=c(convert.image.to.tile.position.x(clip.region["x.min"],image.info.tile),
                       convert.image.to.tile.position.y(clip.region["y.min"],image.info.tile),
                       convert.image.to.tile.position.x(clip.region["x.max"],image.info.tile),
                       convert.image.to.tile.position.y(clip.region["y.max"],image.info.tile))
    clip.region.tile=c(x.min=min(image.info.tile$tile.width+1,max(1,clip.region.tile["x.min"])),
                       y.min=min(image.info.tile$tile.height+1,max(1,clip.region.tile["y.min"])),
                       x.max=min(image.info.tile$tile.width,max(0,clip.region.tile["x.max"])),
                       y.max=min(image.info.tile$tile.height,max(0,clip.region.tile["y.max"])))
    if(clip.region.tile["x.min"]>1)
        image.is.valid[1:(clip.region.tile["x.min"]-1),]=0
    if(clip.region.tile["y.min"]>1)
        image.is.valid[,1:(clip.region.tile["y.min"]-1)]=0
    if(clip.region.tile["x.max"]<image.info.tile$tile.width)
        image.is.valid[(clip.region.tile["x.max"]+1):image.info.tile$tile.width,]=0
    if(clip.region.tile["y.max"]<image.info.tile$tile.height)
        image.is.valid[,(clip.region.tile["y.max"]+1):image.info.tile$tile.height]=0
    
    flag_none_isvalid=all(imageData(image.is.valid)==FALSE)
    if(flag_none_isvalid)##no need to unmix
    {
        cat(paste0("[",format(Sys.time()),"] "),"all pixels/channel=0. No unmixing and AF removal.\n")
    }
    if(flag_none_isvalid==FALSE)
    {
        ##unmix image
        cat(paste0("[",format(Sys.time()),"] "),"unmixing and removing AF\n")
        images=unmix_images(images,unmixing.parameters)
    }
    
    ##keep only dapi
    image.dapi=images[[input.dapi]]
    if(length(input.nuc2.list)>0)
    {
        ##In case of alternative nucleus channels, image dapi contains average over all channels used for nucleus segmentation (name kept for backward compatibility)
        for(input.nuc2 in input.nuc2.list)
        {
            image.dapi=image.dapi+images[[input.nuc2]]
        }
        image.dapi=image.dapi/(length(input.nuc2.list)+1)
    }
    rm(images)

    image.dapi[!image.is.valid]=0

    mask.low.dapi=(gblur(image.dapi,sigma=blur.sigma.nosignal)>threshold.low.dapi)&image.is.valid

    image.dapi=gblur(image.dapi,1)
    image.dapi[image.dapi<0]=0
    image.dapi=sqrt(image.dapi)
    sobel= matrix(c(1, 2, 1, 0, 0, 0, -1, -2, -1), nrow = 3)
    tenengrad.x=filter2(image.dapi,t(sobel),boundary="replicate")
    tenengrad.y=filter2(image.dapi,sobel,boundary="replicate")
    rm(image.dapi)

    tenengrad=tenengrad.x**2+tenengrad.y**2
    disc=makeBrush(2*floor(sharpness.diameter.pixel/2)+1, shape="disc")
    disc=disc/sum(disc)
    image.dapi.sharpness=filter2(tenengrad,disc,boundary="replicate")-filter2(tenengrad.x,disc,boundary="replicate")**2-filter2(tenengrad.y,disc,boundary="replicate")**2
    rm(tenengrad)
    rm(tenengrad.x)
    rm(tenengrad.y)

    
    tmp.r=0*mask.low.dapi
    tmp.g=0*mask.low.dapi
    tmp.b=0*mask.low.dapi
    ##bad
    tmp.r[image.dapi.sharpness<=sharpness.low.threshold]=1
    tmp.g[image.dapi.sharpness<=sharpness.low.threshold]=0
    tmp.b[image.dapi.sharpness<=sharpness.low.threshold]=0
    ##warning
    tmp.r[image.dapi.sharpness>sharpness.low.threshold]=1
    tmp.g[image.dapi.sharpness>sharpness.low.threshold]=1
    tmp.b[image.dapi.sharpness>sharpness.low.threshold]=0
    ##good
    tmp.r[image.dapi.sharpness>sharpness.high.threshold]=0
    tmp.g[image.dapi.sharpness>sharpness.high.threshold]=1
    tmp.b[image.dapi.sharpness>sharpness.high.threshold]=0
    ##low dapi
    tmp.r[!mask.low.dapi]=0.75
    tmp.g[!mask.low.dapi]=0.75
    tmp.b[!mask.low.dapi]=0.75
    ##not valid
    tmp.r[!image.is.valid]=1
    tmp.g[!image.is.valid]=1
    tmp.b[!image.is.valid]=1

    image.quality=rgbImage(tmp.r,tmp.g,tmp.b)


    ##save (remove margin)
    filename=paste0(outputdir,"/sharpness/tile_",sprintf("%09d", tile[["n"]]),"_",tile[["x"]],"_",tile[["y"]],".png")
    cat(paste0("[",format(Sys.time()),"] "),"creating",filename,"\n")
    writeImage(image.quality[(margin.x1+1):(tile[["width"]]+margin.x1),(margin.y1+1):(tile[["height"]]+margin.y1),],filename)
    return(NULL)
}))

stopCluster(cl)

clean()
cat(paste0("[",format(Sys.time()),"] "),"Done\n")
