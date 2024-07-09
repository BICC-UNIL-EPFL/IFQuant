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
 - bfconvert and showinf must be in the PATH (bftools https://www.openmicroscopy.org/bio-formats/).
 - Rownames in unmixing-parameters must correspond to channel names in the qptiff image metadata (field \"Name #\" in output of showinf -nopix <inputfile>)
 - Nucleus staining (e.g. DAPI), tumor staining (e.g. CK) and autofluorescence channels are found by matching the strings \"nucleus\", \"tumor\" and \"AF\" to column \"type\" of the panel metadata (--metadata).
"

#default=NA => mandatory, default=NULL => optional.
option_list=list(
    make_option(c("--tmpdir"), type="character", default=NULL,metavar="DIRNAME",
                help="Directory to save temporary images [Default R tempdir()].
\t\tConsider using /dev/shm/."),
    make_option(c("--nprocesses"), type="integer", default=1,metavar="N",
                help="Max number of threads to use (only for data.table) [default %default]."),
    make_option(c("--extended-nucleus"), type="integer", default=5,metavar="R",
                help="Extended nucleus region is obtained by growing the nucleus region by R (in micron) [default %default]."),
    make_option(c("--clip"), type="character", default=NULL,metavar="FILENAME",
                help="File with a region.
\t\tComma separated file with header in first row, one row per points and 3 columns id,x and y.
\t\tx and y coordinates in qptiff image coordinate system, i.e. pixels with origin at the upper left corner.
\t\tEverything outside of the bounding box of this region will be ignored."),
    make_option(c("--metadata"), type="character", default=NA,metavar="FILENAME",
                help="File with panel metadata [mandatory].
\t\tTab separated file with header in the first row and five columns
\t\t * channel: channel number (0,1,2,...). Should correspond to channel number in the qptiff image, using 0-based indexing.
\t\t * name: channel name (DAPI, CD15,...).
\t\t * filter: filter used for the corresponding channel (e.g. DAPI, Opal 570, Sample AF).
\t\t           Should correspond to the filter name in the qptiff image metadata.
\t\t * color: display color in R,G,B format  (with R,G,B=0,1,...,255).
\t\t * type: channel type, must take one the following values (multiple values must be comma separated, e.g. \"tumor,nucleus2\"):
\t\t   - nucleus: channel used for nuclei segmentation. Exactly one channel should have type \"nucleus\".
\t\t   - nucleus2: additional channel used for nuclei segmentation. Several channels can have type \"nucleus2\".
\t\t               It is strongly discouraged to use an additional channel for nucleus segmentation
\t\t   - tumor: channel used for tissue segmentation. Exactly one channel should have type \"tumor\".
\t\t   - AF: autofluorescence channel. Exactly one channel should have type \"AF\".
\t\t   - NA: other channels."),
    make_option(c("--unmixing-parameters"), type="character", default=NA,metavar="FILENAME",
                help="File with unmixing parameters (output of get_unmixing_parameters.R) [mandatory]."),
    make_option(c("--tile"), type="character", default=NA,metavar="X,Y,W,H",
                help="Use the region of the qptiff image with upper-left corner at position (X,Y), width W and heigth H [mandatory].
\t\tX,Y,W,H must be in the coordinate system specified with --tile-unit."),
    make_option(c("--tile-unit"), type="character", default="pixel",metavar="U",
                help="Specify the coordinate system for --tile=x,y,w,h [default %default].
\t\tCan take one of the following values:
\t\t * pixel: x,y,w,h are in pixels, in the image coordinate system (i.e. upper-left corner of the image is at position (0,0))
\t\t * micron: x,y,w,h are in microns, in the slide coordinate system (upper-left corner of the image is taken from image metadata XOffset,YOffset)."),
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
extended.nucleus.radius.micron=opt$options[["extended-nucleus"]]
input.clip=opt$options[["clip"]]
input.metadata=opt$options[["metadata"]]
input.unmix.params=opt$options[["unmixing-parameters"]]
tile.param=opt$options[["tile"]]
tile.unit=opt$options[["tile-unit"]]
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
tile.param=strsplit(tile.param,",")[[1]]
if(length(tile.param)!=4)
{
    cat("\n")
    cat("Invalid --tile. Please use --tile=x,y,w,h")
    cat("\n")
    quit(status=1)
}
tile.param=list(x=as.numeric(tile.param[1]),
                y=as.numeric(tile.param[2]),
                width=as.numeric(tile.param[3]),
                height=as.numeric(tile.param[4]))         
if(!tile.unit%in%c("pixel","micron"))
{
    stop("--tile-unit must be micron or pixel")
}

##positional arguments
input.image=opt$args[1]


dir.create(outputdir,showWarnings=FALSE,recursive=TRUE)

library(viridis) #color palettes
library(data.table)
library(EBImage)

#nb threads for data.table
setDTthreads(nprocesses)

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
options(scipen=13)
set.seed(1832)

####### nuclei detection #######
blur.sigma.micron=0.5 #To detect nuclei:  blur dapi image 
blur.sigma.nosignal.micron=2.5 #To detect regions without dapi signal: blur dapi image

watershed.low.dapi=1 ##everything with blurred dapi signal <=watershed.low.signal is considered as no dapi (when searching for nuclei).
threshold.dapi.positive=0.1 #a cell is "dapi positive" (i.e. kept) if median value on the nucleus  is above this threshold

dapi.thresholding.size.micron=7.5 #h,w parameters for local thresholding of dapi with thresh().

sharpness.diameter.micron=20 ##sharpness is evaluated by averaging gradient over a disc of diameter sharpness.diameter.micron (in micron).
sharpness.low.threshold=0.5 ##sharpness below this cutoff is considered as WARNING and filtered out
sharpness.high.threshold=3 ##sharpness above this cutoff is considered as good


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

plot_image=function(x,main="",cex.main=0.8,xlab="",ylab="",zlim=NULL,sqrt=TRUE,colors=inferno(256),show.legend=TRUE,mar=.1+c(0.5,0.5,4,3),...)
{

    par(mar=mar)
    if(is.null(zlim))zlim=range(x,na.rm=TRUE)
    if(is.na(zlim[1]))zlim[1]=min(x,na.rm=TRUE)
    if(is.na(zlim[2]))zlim[2]=max(x,na.rm=TRUE)
    if(zlim[2]<zlim[1])zlim=rev(zlim)
    if(max(x,na.rm=TRUE)>zlim[2])x[x>zlim[2]]=zlim[2]
    if(min(x,na.rm=TRUE)<zlim[1])x[x<zlim[1]]=zlim[1]

    legend.width=round(max(2,0.05*nrow(x)))
    yvals=1:ncol(x)
    xvals=1:(nrow(x))
    legend=NULL
    if(show.legend)
    {
        legend=matrix(rep(seq(zlim[2],zlim[1],length.out=length(yvals)),each=legend.width),nrow=legend.width)
        legend[1:(max(1,as.integer(0.2*nrow(legend)))),]=NA #add blank line
        xvals=1:(nrow(x)+nrow(legend))
    }    
    if(sqrt)
    {
        graphics::image(xvals,yvals,sqrt(rbind(x,legend)-zlim[1]),useRaster=TRUE,col=colors,zlim=sqrt(zlim-zlim[1]),xaxt="n",yaxt="n",main=main,xlab="",ylab="",asp=1,bty="n",ylim=c(ncol(x),1),cex.main=cex.main,...)
    }
    else
    {
        graphics::image(xvals,yvals,(rbind(x,legend)),useRaster=TRUE,col=colors,zlim=(zlim),xaxt="n",yaxt="n",main=main,xlab="",ylab="",asp=1,bty="n",ylim=c(ncol(x),1),cex.main=cex.main,...)
    }
    if(show.legend)
    {
        if(zlim[2]>zlim[1])
        {
            labels=pretty(zlim,10)
            labels=labels[labels>=zlim[1]&labels<=zlim[2]]
            axis(4,at=1+(ncol(x)-1)*(labels-zlim[2])/(zlim[1]-zlim[2]),labels=format(labels,trim=TRUE),cex.axis=0.7,las=2,tck= -0.01,hadj=0,pos=max(xvals)+0.5)
        }
        else #zlim[2]==zlim[1]
        {
            axis(4,at=c(1,ncol(x)/2,ncol(x)),labels=rep(zlim[1],3),cex.axis=0.7,las=2,tck= -0.01,hadj=0,pos=max(xvals)+0.5)
        }
    }
}

##draw contours of object (object=all points with same value).
get.contour.points=function(mask){
    contour.points=ocontour(mask)
    ##simplify contours
    lapply(contour.points,function(cntr)
    {
        ## true if points i-1,i,i+1 are not aligned
        to.keep=sapply(1:nrow(cntr),function(i){
            i0=((i-1)-1)%%nrow(cntr)+1
            i1=(i-1)%%nrow(cntr)+1
            i2=((i+1)-1)%%nrow(cntr)+1
            v0=cntr[i0,1:2]
            v1=cntr[i1,1:2]
            v2=cntr[i2,1:2]
            return(abs(det(cbind(v1-v0,v2-v0)))>1e-6)
        })
        cntr[to.keep,]+1 #+1 to convert to 1-based array index
    })
}

draw.contour.points=function(points,col="grey",...){
    for(i in seq_along(points))
    {
        polygon(points[[i]][,1],points[[i]][,2],border=col,...)
    }
}

##find point closest to center of mass
computeFeatures.center.position=function(nucleusMasks,image){
    ids=sort(unique(as.vector(nucleusMasks)))
    ids=ids[ids>0]
    if(length(ids)==0)return(NULL)
    tmp=data.table(reshape2::melt(imageData(nucleusMasks),varnames=c("x","y"),value.name="id"))
    tmp[,value:=reshape2::melt(imageData(image),varnames=c("x","y"),value.name="value")$value]
    tmp[,vx:=value*x]
    tmp[,vy:=value*y]
    tmp2=tmp[,.(mx=sum(vx)/sum(value),my=sum(vy)/sum(value)),by=id]
    setkey(tmp2,id)
    tmp=tmp2[tmp,on=.(id)]
    tmp[,d:=(x-mx)**2+(y-my)**2]
    ##keep only min dist per grou
    tmp=tmp[tmp[, .I[which.min(d)], by = id]$V1]
    setorder(tmp,id)
    tmp=as.data.frame(tmp[id>0][,.(id,x,y)])
    rownames(tmp)=ids
    tmp
}

computeFeatures.bounding.box=function(cellsMasks){
    ids=sort(unique(as.vector(cellsMasks)))
    ids=ids[ids>0]
    if(length(ids)==0)return(NULL)
    tmp=data.table(reshape2::melt(imageData(cellsMasks),varnames=c("x","y"),value.name="id"))
    tmp=tmp[id>0]

    tmp=tmp[,.(x.min=min(x),x.max=max(x),y.min=min(y),y.max=max(y)),by=.(id)]
    tmp=as.matrix(tmp[order(id)])
    rownames(tmp)=tmp[,"id"]
    tmp=tmp[,colnames(tmp)!="id",drop=FALSE]
    tmp
}


## Faster than EBImage::computeFeature.shape
computeFeatures.shape.area=function(nucleusMasks){
    ids=sort(unique(as.vector(nucleusMasks)))
    ids=ids[ids>0]
    if(length(ids)==0)return(NULL)
    ##area
    tmp=data.table(reshape2::melt(imageData(nucleusMasks),varnames=c("x","y"),value.name="id"))[id>0]
    tmp=tmp[,.(s.area=.N),by=id]
    setkey(tmp,id)
    setorder(tmp,id)
    tmp=as.matrix(tmp[ids][,.(s.area)])
    rownames(tmp)=ids
    tmp
}

##to replace EBImage::computeFeature.basic
##slightly faster
##WARNING: median is named "b.q050" instead of "b.q05" (as in computeFeatures.basic() )
computeFeatures.basic.v2=function(nucleusMasks,image){
    probs=c(0.01,0.05,0.25,0.5,0.75,0.95,0.99)
    ids=sort(unique(as.vector(nucleusMasks)))
    ids=ids[ids>0]
    if(length(ids)==0)return(NULL)
    ##area
    tmp=data.table(reshape2::melt(imageData(nucleusMasks),varnames=c("x","y"),value.name="id"))
    tmp[,value:=reshape2::melt(imageData(image),varnames=c("x","y"),value.name="value")$value]

    tmp1=tmp[id>0,.(b.mean=mean(value,na.rm=TRUE)),by=id]
    tmp2=tmp[id>0,as.list(quantile(value,probs=probs,names=FALSE,na.rm=TRUE)),by=id]
    setnames(tmp2,c("id",paste0("b.q",formatC(probs*100,width=3,format="d",flag="0"))))

    setkey(tmp1,id)
    setorder(tmp1,id)
    setkey(tmp2,id)
    setorder(tmp2,id)
    tmp=cbind(as.matrix(tmp1[ids][,.(b.mean)]),
              as.matrix(tmp2[ids][,colnames(tmp2)!="id",with=FALSE]))     
    rownames(tmp)=ids
    tmp
}

##quantify distribution around nucleus center:
## - for each (n.angles discretized) angle (from nucleus center to pixel) find max pixel value.
## - return quantiles of max pixel value over all (discretized) angles.
computeFeatures.circular=function(Masks,image,nucPos,n.angles=16){
    probs=c(0.05,0.1,0.25,0.5)
    ids=sort(unique(as.vector(Masks)))
    ids=ids[ids>0]
    if(length(ids)==0)return(NULL)
    tmp=data.table(reshape2::melt(imageData(Masks),varnames=c("x","y"),value.name="id"))
    tmp[,value:=reshape2::melt(imageData(image),varnames=c("x","y"),value.name="value")$value]
    tmp=tmp[id>0]
    tmp=tmp[data.table(nucPos)[id%in%ids,.(cell.x=x,cell.y=y,id)],on=.(id)]
    ##remove centerpoint
    tmp=tmp[!(cell.x==x&cell.y==y)]
    ##eval and discretize angle
    tmp[,angle:=ceiling(n.angles*(pi+atan2(x-cell.x,y-cell.y))/(2*pi))]
    ##summarize per angle (and add missing angles)
    tmp=tmp[,.(value=max(value,na.rm=TRUE)),by=.(id,angle)][CJ(id=ids,angle=1:n.angles),on=c("id","angle")][,as.list(quantile(value,probs=probs,names=FALSE,na.rm=TRUE)),by=id]
    setnames(tmp,c("id",paste0("circular.q",formatC(probs*100,width=3,format="d",flag="0"))))

    setkey(tmp,id)
    setorder(tmp,id)
    tmp=as.matrix(tmp[ids][,colnames(tmp)!="id",with=FALSE])
    rownames(tmp)=ids
    tmp
}


############# conversion between coordinate systems ##########
##There are 3 coordinate systems:
# Slide: in micron (used by inForm).
# Image (the qptiff image): image acquired by the microscope. In pixels. The origin is defined by XOffset,YOffset given in the image metadata (stored in image.info[["image.xoffset"]], image.info[["image.yoffset"]]) and does usually not correspond to the slide origin.
# Tile/Region (the qptiff image): region/tile used for processing. In pixels. Origin (in Image coordinate system) stored in image.info[["tile.x"]],image.info[["tile.y"]] and size (in pixel) stored in image.info[["tile.width"]] and image.info[["tile.height"]]



## conversion:
## Tile coordinate system (pixel) <-> Slide coordinate system (micron) (inForm units)
##position
convert.tile.to.slide.position.x=function(x,image.info){
    (x-1+image.info[["tile.x"]]+image.info[["image.xoffset"]]*image.info[["image.xresolution"]])*10000/image.info[["image.xresolution"]]
}
convert.slide.to.tile.position.x=function(x,image.info){
    round(x*image.info[["image.xresolution"]]/10000 - image.info[["tile.x"]]-image.info[["image.xoffset"]]*image.info[["image.xresolution"]]+1)
}
convert.tile.to.slide.position.y=function(y,image.info){
    (y-1+image.info[["tile.y"]]+image.info[["image.yoffset"]]*image.info[["image.yresolution"]])*10000/image.info[["image.yresolution"]]
}
convert.slide.to.tile.position.y=function(y,image.info){
    round(y*image.info[["image.yresolution"]]/10000 - image.info[["tile.y"]]-image.info[["image.yoffset"]]*image.info[["image.yresolution"]]+1)
}
##length
convert.tile.to.slide.length=function(x,image.info){
    if(image.info[["image.xresolution"]]!=image.info[["image.yresolution"]])
        stop("cannot convert a length to micron when XResolution!=YResolution")
    x*10000/image.info[["image.xresolution"]]
}
convert.slide.to.tile.length=function(x,image.info){
    if(image.info[["image.xresolution"]]!=image.info[["image.yresolution"]])
        stop("cannot convert a length to micron when XResolution!=YResolution")
    round(x*image.info[["image.xresolution"]]/10000)
}
##area
convert.tile.to.slide.area=function(x,image.info){
    x*(10000/image.info[["image.xresolution"]])*(10000/image.info[["image.yresolution"]])
}
convert.slide.to.tile.area=function(x,image.info){
    round(x*(image.info[["image.xresolution"]]/10000)*(image.info[["image.yresolution"]]/10000))
}

## conversion:
## Tile coordinate system (pixel) <-> Image coordinate system (pixel)
##position
convert.tile.to.image.position.x=function(x,image.info){
    x+image.info[["tile.x"]]-1 
}
convert.tile.to.image.position.y=function(y,image.info){
    y+image.info[["tile.y"]]-1
}
convert.image.to.tile.position.x=function(x,image.info){
    x-image.info[["tile.x"]]+1
}
convert.image.to.tile.position.y=function(y,image.info){
    y-image.info[["tile.y"]]+1
}
##length
convert.tile.to.image.length=function(x,image.info){
    x
}
convert.image.to.tile.length=function(x,image.info){
    x
}
##area
convert.tile.to.image.area=function(x,image.info){
    x
}
convert.image.to.tile.area=function(x,image.info){
    x
}

## conversion:
## Slide coordinate system (micron) (inForm units) <-> Image coordinate system (pixel)
convert.image.to.slide.position.x=function(x,image.info){
    (x+image.info[["image.xoffset"]]*image.info[["image.xresolution"]])*10000/image.info[["image.xresolution"]]
}
convert.slide.to.image.position.x=function(x,image.info){
    round(x*image.info[["image.xresolution"]]/10000-image.info[["image.xoffset"]]*image.info[["image.xresolution"]])
}
convert.image.to.slide.position.y=function(y,image.info){
    (y+image.info[["image.yoffset"]]*image.info[["image.yresolution"]])*10000/image.info[["image.yresolution"]]
}
convert.slide.to.image.position.y=function(y,image.info){
    round(y*image.info[["image.yresolution"]]/10000-image.info[["image.yoffset"]]*image.info[["image.yresolution"]])
}
##length
convert.image.to.slide.length=function(x,image.info){
    if(image.info[["image.xresolution"]]!=image.info[["image.yresolution"]])
        stop("cannot convert a length to micron when XResolution!=YResolution")
    x*10000/image.info[["image.xresolution"]]
}
convert.slide.to.image.length=function(x,image.info){
    if(image.info[["image.xresolution"]]!=image.info[["image.yresolution"]])
        stop("cannot convert a length to micron when XResolution!=YResolution")
    round(x*image.info[["image.xresolution"]]/10000)
}
##area
convert.image.to.slide.area=function(x,image.info){
    x*(10000/image.info[["image.xresolution"]])*(10000/image.info[["image.yresolution"]])
}
convert.slide.to.image.area=function(x,image.info){
    round(x*(image.info[["image.xresolution"]]/10000)*(image.info[["image.yresolution"]]/10000))
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


###convert tile to  pixels (in image coordinate system)
if(tile.unit=="micron")
{
    tile=list(x=as.integer(round(tile.param[["x"]]*image.info[["image.xresolution"]]/10000 - image.info[["image.xoffset"]]*image.info[["image.xresolution"]])),
              y=as.integer(round(tile.param[["y"]]*image.info[["image.yresolution"]]/10000 - image.info[["image.yoffset"]]*image.info[["image.yresolution"]])),
              width=as.integer(round(tile.param[["width"]]*image.info[["image.xresolution"]]/10000)),
              height=as.integer(round(tile.param[["height"]]*image.info[["image.xresolution"]]/10000)))
}
if(tile.unit=="pixel")
{
    tile=lapply(tile.param,function(x){as.integer(round(x))})
}

image.info=c(image.info,list(
    tile.x=tile[["x"]],
    tile.y=tile[["y"]],
    tile.width=tile[["width"]],
    tile.height=tile[["height"]]
))
cat(paste0("[",format(Sys.time()),"] "),"Final tile size in image coordinate (pixels):\n")
cat(paste0("[",format(Sys.time()),"] ")," x=",image.info[["tile.x"]],"\n")
cat(paste0("[",format(Sys.time()),"] ")," y=",image.info[["tile.y"]],"\n")
cat(paste0("[",format(Sys.time()),"] ")," width=",image.info[["tile.width"]],"\n")
cat(paste0("[",format(Sys.time()),"] ")," height=",image.info[["tile.height"]],"\n")
##check tile size
if(!(image.info[["tile.x"]]+image.info[["tile.width"]]<=image.info[["image.width.pixel"]]&&image.info[["tile.y"]]+image.info[["tile.height"]]<=image.info[["image.height.pixel"]]&&image.info[["tile.x"]]>=0&&image.info[["tile.y"]]>=0))
{
    stop("Invalid tile coordinates")
}



############################################
##generate images
############################################
tmpfile=tempfile(fileext="_channel_%c.png",tmpdir=tmpdir)
cat(paste0("[",format(Sys.time()),"] "),"Extracting images with file names:",gsub("%c","*",tmpfile),"\n")
system2("bfconvert",args=c("-no-upgrade",paste0("-crop ",image.info[["tile.x"]],",",image.info[["tile.y"]],",",image.info[["tile.width"]],",",image.info[["tile.height"]]),"-series 0",paste0("\"",input.image,"\""),paste0("\"",tmpfile,"\"")))


input.images.tmp=list.files(tmpdir,pattern=gsub("_channel_%c.png","_channel_[0-9]*.png",basename(tmpfile)),full.names=TRUE)


############################################
##load
############################################

clip.region=c(x.min=0,y.min=0,x.max=image.info$image.width.pixel,y.max=image.info$image.height.pixel)
if(!is.null(input.clip))
{
    tmp=read.table(input.clip,sep=",",header=TRUE)
    clip.region=c(x.min=min(tmp$x),y.min=min(tmp$y),x.max=max(tmp$x),y.max=max(tmp$y))
}

metadata=read.table(input.metadata,header=TRUE,stringsAsFactors=FALSE,sep="\t")
##check channel names do not contain problematic chars (will be used as filename)
forbidden.char=c("/","*")
for(ch in forbidden.char)
{
    if(any(grepl(ch,metadata$name,fixed=TRUE)))
        stop("channel name (",paste0(grep(ch,metadata$name,fixed=TRUE,value=TRUE),collapse=", "),") with invalid character (",ch,") in file ",input.metadata)
}
tmp=data.frame(file=c(input.images.tmp),stringsAsFactors=FALSE)
tmp$channel=as.integer(gsub(".*_channel_([0-9]*).*","\\1",basename(tmp$file)))
tmp=unique(tmp)
if(any(duplicated(tmp$channel)))
{
    stop("two input files with same channel")
}
if(any(duplicated(tmp$file)))
{
    stop("two input files with same name")
}
metadata=merge(metadata,tmp,by="channel",all.y=TRUE)
if(any(is.na(metadata$name)))
{
    stop("missing metadata")
}
metadata=metadata[!is.na(metadata$file),]
rownames(metadata)=paste0("channel_",metadata$channel)
##add channel name from image info
metadata$image.channel.name=image.info$image.channel.names[rownames(metadata)]
##find dapi and autofluorescence channel
channel.dapi=metadata[sapply(strsplit(metadata$type,","),function(x){"nucleus"%in%x}),"channel"]
channel.autofluorescence=metadata[sapply(strsplit(metadata$type,","),function(x){"AF"%in%x}),"channel"]
input.dapi=rownames(metadata)[metadata$channel==channel.dapi]
input.autofluorescence=rownames(metadata)[metadata$channel==channel.autofluorescence]
if(length(input.dapi)!=1)
{
    stop("Channel with type \"nucleus\" missing in panel metadata.")
}
if(length(input.autofluorescence)!=1)
{
    stop("Channel with type \"AF\" missing in panel metadata.")
}
##find alternative nucleus channels (channels with type "nucleus2")
input.nuc2.list=rownames(metadata)[sapply(strsplit(metadata$type,","),function(x){"nucleus2"%in%x})]

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

##load other channels
images=lapply(rownames(metadata),function(channel){
    f=metadata[channel,"file"]
    image=readImage(f)
    image=image/image.info$image.exposure.times[channel]
    file.remove(f)
    image
})
names(images)=rownames(metadata)

##ignore regions with all values at zero (set to NA)
image.is.valid=sign(Reduce("+",images))!=0 #TRUE if not all zero (valid), FALSE if all channels at 0 (not valid)
##ignore regions outside clip.region
clip.region.tile=c(convert.image.to.tile.position.x(clip.region["x.min"],image.info),
                   convert.image.to.tile.position.y(clip.region["y.min"],image.info),
                   convert.image.to.tile.position.x(clip.region["x.max"],image.info),
                   convert.image.to.tile.position.y(clip.region["y.max"],image.info))
clip.region.tile=c(x.min=min(image.info$tile.width+1,max(1,clip.region.tile["x.min"])),
                   y.min=min(image.info$tile.height+1,max(1,clip.region.tile["y.min"])),
                   x.max=min(image.info$tile.width,max(0,clip.region.tile["x.max"])),
                   y.max=min(image.info$tile.height,max(0,clip.region.tile["y.max"])))
if(clip.region.tile["x.min"]>1)
    image.is.valid[1:(clip.region.tile["x.min"]-1),]=0
if(clip.region.tile["y.min"]>1)
    image.is.valid[,1:(clip.region.tile["y.min"]-1)]=0
if(clip.region.tile["x.max"]<image.info$tile.width)
    image.is.valid[(clip.region.tile["x.max"]+1):image.info$tile.width,]=0
if(clip.region.tile["y.max"]<image.info$tile.height)
    image.is.valid[,(clip.region.tile["y.max"]+1):image.info$tile.height]=0


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

for(f in names(images))
{
    images[[f]][!image.is.valid]=0
}

##eval max umixed value
unmixed.images.max.values=sapply(images,max,na.rm=TRUE)

image.dapi=images[[input.dapi]]
image.dapi.label=metadata[input.dapi,"name"]
if(length(input.nuc2.list)>0)
{
    ##In case of alternative nucleus channels, image dapi contains average over all channels used for nucleus segmentation (name kept for backward compatibility)
    for(input.nuc2 in input.nuc2.list)
    {
        image.dapi=image.dapi+images[[input.nuc2]]
    }
    image.dapi=image.dapi/(length(input.nuc2.list)+1)
    image.dapi.label=paste0("mean(",paste(metadata[unique(c(input.dapi,input.nuc2.list)),"name"],collapse=","),")")
}


## ########################
## eval dapi sharpness
## ########################
cat(paste0("[",format(Sys.time()),"] "),image.dapi.label,"sharpness\n")
extended.nucleus.radius.pixel=convert.slide.to.tile.length(extended.nucleus.radius.micron,image.info)
sharpness.diameter.pixel=convert.slide.to.tile.length(sharpness.diameter.micron,image.info)

if(flag_none_isvalid)##all 0
{
    tenengrad.x=images[[1]]*0
    tenengrad.y=images[[1]]*0
    tenengrad=images[[1]]*0
    image.dapi.sharpness=images[[1]]*0
}
if(flag_none_isvalid==FALSE)
{
    ##Estimate sharpnes as the sum of the gradient variance (estimated using sobel operator) in x and in y directions: sharpness=var(tenengrad.x)+var(tenengrad.y)
    image.tmp=gblur(image.dapi,1)
    image.tmp[image.tmp<0]=0
    image.tmp=sqrt(image.tmp)
    sobel= matrix(c(1, 2, 1, 0, 0, 0, -1, -2, -1), nrow = 3)
    tenengrad.x=filter2(image.tmp,t(sobel),boundary="replicate")
    tenengrad.y=filter2(image.tmp,sobel,boundary="replicate")
    rm(image.tmp)
    tenengrad=tenengrad.x**2+tenengrad.y**2
    disc=makeBrush(2*floor(sharpness.diameter.pixel/2)+1, shape="disc")
    disc=disc/sum(disc)
    image.dapi.sharpness=filter2(tenengrad,disc,boundary="replicate")-filter2(tenengrad.x,disc,boundary="replicate")**2-filter2(tenengrad.y,disc,boundary="replicate")**2
}

############################################
## Nuclei detection
############################################
cat(paste0("[",format(Sys.time()),"] "),"nuclei detection\n")

##mask low dapi regions as well as invalid regions (i.e. all channel 0). Valid regions are eroded by dapi.thresholding.size to avoid detection of spurious nuclei at the border of valid regions.
dapi.thresholding.size=convert.slide.to.tile.length(dapi.thresholding.size.micron,image.info)
blur.sigma=convert.slide.to.tile.length(blur.sigma.micron,image.info)
blur.sigma.nosignal=convert.slide.to.tile.length(blur.sigma.nosignal.micron,image.info)
threshold.low.dapi=watershed.low.dapi
mask.low.dapi=(gblur(image.dapi,sigma=blur.sigma.nosignal)>threshold.low.dapi)&erode(image.is.valid,makeBrush(2*dapi.thresholding.size+1,"box"))

##Blur
cat(paste0("[",format(Sys.time()),"] "),"blur",image.dapi.label,"\n")
image.dapi.blur=gblur(image.dapi,sigma=blur.sigma)

cat(paste0("[",format(Sys.time()),"] "),"thresholding\n")
nucleusMasks=thresh(image.dapi.blur, w=dapi.thresholding.size, h=dapi.thresholding.size, offset=1)
nucleusMasks[!mask.low.dapi]=0
nucleusMasks = opening(nucleusMasks, makeBrush(5, shape="disc"))
nucleusMasks = fillHull(nucleusMasks)


cat(paste0("[",format(Sys.time()),"] "),"watershed\n")
##on smoothed distance map (more robust)
nucleusMasks = EBImage::watershed(gblur(distmap(nucleusMasks),sigma=1)*(nucleusMasks!=0), tolerance=0.5)

### "erode" nuclei
##Note: too small nucleus might disappear, or nucleus can be split in two disconnected components
cat(paste0("[",format(Sys.time()),"] "),"computeFeatures.bounding.box\n")
bb=computeFeatures.bounding.box(nucleusMasks)
cat(paste0("[",format(Sys.time()),"] "),"cleaning nuclei (erosion)\n")
if(!is.null(bb))
{
    if(!identical(as.character(seq_along(rownames(bb))),rownames(bb)))##check that row index corresponds to cell id
    {
        stop("problem with bounding boxes")
    }
    brush=makeBrush(5, shape="disc")
    toremove=0*nucleusMasks
    for(id in seq_along(rownames(bb)))
    {
        rx=max(1,bb[id,"x.min"]-2):min(nrow(nucleusMasks),bb[id,"x.max"]+2) ##increase bounding box to avoid border effects in opening()
        ry=max(1,bb[id,"y.min"]-2):min(ncol(nucleusMasks),bb[id,"y.max"]+2)
        toremove[rx,ry]=toremove[rx,ry]+(nucleusMasks[rx,ry]==id)&!opening(nucleusMasks[rx,ry]==id, brush)
    }
    nucleusMasks[toremove!=0]=0
}

##renumber with consecutive ID (in case some are missing
cat(paste0("[",format(Sys.time()),"] "),"renumbering cells\n")
map.id=c(0L,rep(NA,max(nucleusMasks)))
cellids=sort(unique(as.vector(nucleusMasks)))
cellids=cellids[cellids!=0]
map.id[cellids+1]=1:length(cellids)
imageData(nucleusMasks)=matrix(map.id[as.vector(nucleusMasks)+1],ncol=ncol(nucleusMasks))

##shuffle ID
cat(paste0("[",format(Sys.time()),"] "),"shuffling cell.IDs\n")
map.id=c(0L,sample.int(max(nucleusMasks)))
imageData(nucleusMasks)=matrix(map.id[as.vector(nucleusMasks)+1],ncol=ncol(nucleusMasks))
##find centers
cat(paste0("[",format(Sys.time()),"] "),"nucleus centers\n")
nucPos=computeFeatures.center.position(nucleusMasks,image.dapi.blur)
if(is.null(nucPos))
{
    nucPos=data.frame(id=integer(0),x=integer(0),y=integer(0))
}
if(nrow(nucPos)>0)
{
    ##EBImage::watershed() can return regions with more than one connected component.
    ##This is problematic for EBImage::ocontour (used in computeFeatures.shape function), which assumes objects to be connected.
    ##In ocontour(), "objects" are sets of pixels with the same unique integer value. Two pixels at position (x1,y1) and (x2,y2) are "neighbors" <=> x1==x2 and abs(y1-y2)==1 or abs(x1-x2)==1 and y1==y2.
    ## E.g. 1 and 2 are neighbors:
    ## 0 0 0    0 2 0    0 0 0    0 0 0
    ## 0 1 2 ,  0 1 0 ,  2 1 0 ,  0 1 0
    ## 0 0 0    0 0 0    0 0 0    0 2 0
    ## E.g. 1 and 2 are not neighbors:
    ## 0 0 2    2 0 0    0 0 0    0 0 0
    ## 0 1 0 ,  0 1 0 ,  0 1 0 ,  0 1 0
    ## 0 0 0    0 0 0    2 0 0    0 0 2
    ## An object (set of pixels with same unique integer value) is connected if for all pairs of pixels p1 and p2 in the set, a path of pixels (q1,q2,q3,...qn) exists such that p1 and q1 are neighbors, q1 and q2 are neighbors, q2 and q3 are neighbors, ..., qn and p2 are neighbors.
    ## When an object consists in multiple componenent, ocontour (and computeFeature*) arbitrarly picks one component and ignore the other components.
    ##
    ## Our problem is that EBImage::watershed can return objects (sets of pixels with same unique integer value) that are disconnected according to this definition, e.g. the region formed by all pixels with value 1
    ## 0 0 0 0 0 0 0 0 0
    ## 0 1 0 0 0 0 0 0 0
    ## 0 0 1 1 0 1 1 0 0
    ## 0 0 1 1 1 1 1 1 0
    ## 0 1 1 1 1 1 1 0 0
    ## 0 0 1 1 1 1 0 0 0
    ## 0 0 0 0 1 0 1 1 0
    ## This object consists in 3 connected regions (labelled 1, 2 and 3):
    ## 0 0 0 0 0 0 0 0 0
    ## 0 1 0 0 0 0 0 0 0
    ## 0 0 2 2 0 2 2 0 0
    ## 0 0 2 2 2 2 2 2 0
    ## 0 2 2 2 2 2 2 0 0
    ## 0 0 2 2 2 2 0 0 0
    ## 0 0 0 0 2 0 3 3 0
    ##
    ## To avoid arbitrarily keeping only component 1, we explicitely check if region contains multiple components, and if yes, we keep the component containing the nucleus positoin (nucPos) and set the other components to 0 (i.e. ignored)

    ##1) "quickly" find regions that could contain multiple components, i.e. with
    ## id1 id2     id2 id1
    ## id3 id1  or id1 id3
    ## with  id1!=id2 and id1!=id3
    ##filters
    cat(paste0("[",format(Sys.time()),"] "),"searching for nucleus with multiple components\n")
    filt_d=matrix(c(0,0,0,0,1,0,0,0,-1),ncol=3)
    filt_h=matrix(c(0,0,0,0,1,-1,0,0,0),ncol=3)
    filt_v=matrix(c(0,0,0,0,1,0,0,-1,0),ncol=3)
    to.check=(nucleusMasks!=0)
    to.check=to.check&abs(filter2(nucleusMasks,filt_d,boundary="replicate"))<0.01
    to.check=to.check&abs(filter2(nucleusMasks,filt_h,boundary="replicate"))>0.01
    to.check=to.check&abs(filter2(nucleusMasks,filt_v,boundary="replicate"))>0.01
    ids.to.check=unique(nucleusMasks[to.check])
    to.check=(nucleusMasks!=0)
    to.check=to.check&abs(filter2(nucleusMasks,flip(filt_d),boundary="replicate"))<0.01
    to.check=to.check&abs(filter2(nucleusMasks,flip(filt_h),boundary="replicate"))>0.01
    to.check=to.check&abs(filter2(nucleusMasks,flip(filt_v),boundary="replicate"))>0.01
    ids.to.check=c(ids.to.check,unique(nucleusMasks[to.check]))
    ##1) search for true multi component regions (i.e. completely separated)
    ids.to.check=unique(c(ids.to.check,unique(data.table(id=as.vector(nucleusMasks),component=as.vector(bwlabel(nucleusMasks))))[id>0,.(ncomp=.N),by=id][ncomp>1,id]))
    ##2) clean multi components regions
    if(length(ids.to.check)>0)
    {
        cat(paste0("[",format(Sys.time()),"] "),"cleaning",length(ids.to.check),"candidate multi-component nucleus\n")
        for(id in ids.to.check)
        {
            ##split into  connected component
            components=bwlabel(nucleusMasks==id)
            ##check which  component (comp.id) contains the nucleus and set to 0
            comp.id=as.integer(components[nucPos[nucPos[,"id"]==id,"x"],nucPos[nucPos[,"id"]==id,"y"]])
            components[components==comp.id]=0
            ##set nucleusMasks to zero for all other components:
            nucleusMasks[components!=0]=0
        }
    }
}

##check nucPos[,"id"] corresponds to nucleusMask
if(!all(sapply(seq_along(nucPos[,"x"]),function(i){
    nucPos[i,"id"]==nucleusMasks[nucPos[i,"x"],nucPos[i,"y"]]
})))
{
    stop("inconsistent nucleus ids")
}
if(!identical(sort(unique(as.integer(c(0L,as.vector(nucleusMasks))))),sort(unique(as.integer(c(0L,nucPos[,"id"]))))))
{
    stop("inconsistent nucleus ids")
}

cat(paste0("[",format(Sys.time()),"] "),"cells Cnt=",nrow(nucPos),"\n")


## ########################
##quantify nucleus features per channel
## ########################
nucleusFeatures=NULL
if(nrow(nucPos)>0)
{
    ##output of computeFeatures.*() has one row per value in nucleusMasks, ordered by increasing order of nucleusMasks
    nucPos=nucPos[order(nucPos[,"id"]),,drop=FALSE]
    cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.shape\n")
    cf.shape=EBImage::computeFeatures.shape(nucleusMasks)
    cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.bounding.box\n")
    cf.bounding.box=computeFeatures.bounding.box(nucleusMasks)
    colnames(cf.bounding.box)=paste0("nucleus.",colnames(cf.bounding.box))
    cf.dapi.sharpness=computeFeatures.basic.v2(nucleusMasks,image.dapi.sharpness)
    nucleusFeatures=lapply(rownames(metadata),function(f){
        channel.name=metadata[f,"name"]
        cat(paste0("[",format(Sys.time()),"] "),"Quantifying Channel ",channel.name,"\n")
        cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.basic\n")
        cf.basic=computeFeatures.basic.v2(nucleusMasks,images[[f]])
        cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.circular\n")
        cf.circular=computeFeatures.circular(nucleusMasks,images[[f]],nucPos)
        cf.moment=NULL
        if(f==input.dapi)
        {
            ##Use image.dapi (i.e. average over all channels used for nucleus segmentation)
            cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.moment\n")
            cf.moment=EBImage::computeFeatures.moment(nucleusMasks,image.dapi)
            ##set invalid values to NA
            invalid=(cf.basic[,"b.mean"]<1e-15)&(cf.moment[,"m.cx"]<1e-15)&(cf.moment[,"m.cy"]<1e-15)
            cf.moment[invalid,]=NA
        }
        cat(paste0("[",format(Sys.time()),"] ")," done\n")
        cbind(cell.ID=nucPos[,"id"],cf.moment,cf.basic,cf.circular)
    })
    names(nucleusFeatures)=rownames(metadata)
    nucleusFeatures=c(list(shape=cbind(cell.ID=nucPos[,"id"],nucleus.x=nucPos[,"x"],nucleus.y=nucPos[,"y"],cf.bounding.box,cf.shape,sharpness=cf.dapi.sharpness[,"b.mean"])),
                    nucleusFeatures)
    ##rename columns
    colnames(nucleusFeatures[["shape"]])=gsub("^s\\.","nucleus.",colnames(nucleusFeatures[["shape"]]))
    for(f in rownames(metadata))
    {
        colnames(nucleusFeatures[[f]])=gsub("^(m|b)\\.","",colnames(nucleusFeatures[[f]]))
    }
    ##WARNING: nucleusFeatures[[input.dapi]] columns cx, cy, majoraxis, eccentricity and theta are evaluated on the average over all channels used for nucleus segmentation, not dapi. These features should characterize distribution of signal in the nucleus channel, but are attached to channel dapi for backward compatibility


    ##Filter out nucleus with zero dapi (and zero alternative nucleus channels)
    cat(paste0("[",format(Sys.time()),"] "),"Filtering nucleus with low ",image.dapi.label,"\n")
    nuc.signal=nucleusFeatures[[input.dapi]][,"q050"]
    for(input.nuc2 in input.nuc2.list)
    {
        nuc.signal=nuc.signal+nucleusFeatures[[input.nuc2]][,"q050"]
    }
    nuc.signal=nuc.signal/(length(input.nuc2.list)+1)
    idx=which(!(nuc.signal > threshold.dapi.positive))
    cat(paste0("[",format(Sys.time()),"] "),"removing",length(idx),"nucleus with low ",image.dapi.label,"\n")
    if(length(idx)>0)
    {
        cell.IDs=nucleusFeatures[["shape"]][idx,"cell.ID"]
        for(n in names(nucleusFeatures))
        {
            nucleusFeatures[[n]]=nucleusFeatures[[n]][-idx,,drop=FALSE]
        }
        nucPos=nucPos[-idx,,drop=FALSE]
        nucleusMasks[nucleusMasks %in% cell.IDs]=0.0
    }
    cat(paste0("[",format(Sys.time()),"] "),"Retained cells Cnt=",nrow(nucleusFeatures[["shape"]]),"\n")
    if(nrow(nucleusFeatures[["shape"]])==0)
        nucleusFeatures=NULL

    if(!is.null(nucleusFeatures))
    {
        ##Filter out nucleus with sharpness below threshold
        cat(paste0("[",format(Sys.time()),"] "),"Filtering low",image.dapi.label,"sharpness nucleus (<",sharpness.low.threshold,")\n")
        idx=which(!(nucleusFeatures[["shape"]][,"sharpness"] > sharpness.low.threshold))
        cat(paste0("[",format(Sys.time()),"] "),"removing",length(idx),"nucleus with low",image.dapi.label,"sharpness\n")
        if(length(idx)>0)
        {
            cell.IDs=nucleusFeatures[["shape"]][idx,"cell.ID"]
            for(n in names(nucleusFeatures))
            {
                nucleusFeatures[[n]]=nucleusFeatures[[n]][-idx,,drop=FALSE]
            }
            nucPos=nucPos[-idx,,drop=FALSE]
            nucleusMasks[nucleusMasks %in% cell.IDs]=0.0
        }
        cat(paste0("[",format(Sys.time()),"] "),"Retained cells Cnt=",nrow(nucleusFeatures[["shape"]]),"\n")
        if(nrow(nucleusFeatures[["shape"]])==0)
            nucleusFeatures=NULL
    }
}

###########################
##relabel cells and check
###########################
if(!is.null(nucleusFeatures))
{
    cat(paste0("[",format(Sys.time()),"] "),"relabelling cells\n")
    ##relabel (map.labels[old]=new)
    old.labels=sort(unique(as.vector(nucleusMasks[nucleusMasks>0])))
    map.labels=vector(mode="integer",length=max(old.labels,na.rm=TRUE))
    map.labels[old.labels]=1:length(old.labels)

    nucleusMasks[nucleusMasks>0]=map.labels[nucleusMasks[nucleusMasks>0]]
    for(f in names(nucleusFeatures))
    {
        nucleusFeatures[[f]][nucleusFeatures[[f]][,"cell.ID"]>0,"cell.ID"]=map.labels[nucleusFeatures[[f]][nucleusFeatures[[f]][,"cell.ID"]>0,"cell.ID"]]
        rownames(nucleusFeatures[[f]])=nucleusFeatures[[f]][,"cell.ID"]
    }
    nucPos[nucPos[,"id"]>0,"id"]=map.labels[nucPos[nucPos[,"id"]>0,"id"]]


    ##check cell.ID correspond to nucleusMasks at nucleus.x, nucleus.y and at cx,cy
    if(!all(sapply(1:nrow(nucleusFeatures[["shape"]]),function(i){
        nucleusFeatures[["shape"]][i,"cell.ID"]==nucleusMasks[nucleusFeatures[["shape"]][i,"nucleus.x"],nucleusFeatures[["shape"]][i,"nucleus.y"]]
    })))
    {
        stop("Inconsistent nucleus ids")
    }
    ##check that nucleus.x,nucleus.y are inside the bounding box
    if(!all(nucleusFeatures[["shape"]][,"nucleus.x"]>=nucleusFeatures[["shape"]][,"nucleus.x.min"]&
            nucleusFeatures[["shape"]][,"nucleus.x"]<=nucleusFeatures[["shape"]][,"nucleus.x.max"]&
            nucleusFeatures[["shape"]][,"nucleus.y"]>=nucleusFeatures[["shape"]][,"nucleus.y.min"]&
            nucleusFeatures[["shape"]][,"nucleus.y"]<=nucleusFeatures[["shape"]][,"nucleus.y.max"]))
    {
        stop("inconsistent nucleus ids (nucleus.x,nucleus.y outside bounding box)")
    }
    for(f in rownames(metadata))
    {
        if(!identical(nucleusFeatures[["shape"]][,"cell.ID"],nucleusFeatures[[f]][,"cell.ID"]))
        {
            stop("Inconsistent nucleus ids")
        }

        ##check that nucleus.x,nucleus.y and cx,cy are inside the bounding box (only for dapi)
        if(f==input.dapi)
        {
            ind=which(is.finite(nucleusFeatures[[f]][,"cx"])&is.finite(nucleusFeatures[[f]][,"cy"])&nucleusFeatures[[f]][,"cx"]>0&nucleusFeatures[[f]][,"cy"]>0)
            if(!all(round(nucleusFeatures[[f]][ind,"cx"])>=nucleusFeatures[["shape"]][ind,"nucleus.x.min"]&
                    round(nucleusFeatures[[f]][ind,"cx"])<=nucleusFeatures[["shape"]][ind,"nucleus.x.max"]&
                    round(nucleusFeatures[[f]][ind,"cy"])>=nucleusFeatures[["shape"]][ind,"nucleus.y.min"]&
                    round(nucleusFeatures[[f]][ind,"cy"])<=nucleusFeatures[["shape"]][ind,"nucleus.y.max"]))
            {
                stop("inconsistent nucleus ids (cx,cy outside bounding box)")
            }
        }
    }
    if(!all(sort(unique(as.vector(nucleusMasks[nucleusMasks>0])))==sort(unique(nucleusFeatures[[1]][,"cell.ID"]))))
    {
        stop("inconsistent nucleus ids")
    }
    if(!all(nucleusFeatures[[1]][,"cell.ID"]==1:nrow(nucleusFeatures[[1]])))
    {
        stop("inconsistent nucleus ids")
    }

}



############################################
## Extended nucleus region (i.e. "cell" region)
############################################
if(is.null(nucleusFeatures))
{
    extendedNucleusMasks=nucleusMasks*1
}
if(!is.null(nucleusFeatures))
{
    cat(paste0("[",format(Sys.time()),"] "),"extended nucleus regions\n")
    ##Etended nucleus (voronoi up to extended.nucleus.radius.pixel from nucleus border)
    disc=makeBrush(2*floor(extended.nucleus.radius.pixel)+1, shape="disc")
    mask=filter2(nucleusMasks>0,disc,boundary="replicate")>0.5
    ##reassign original values and propagate
    extendedNucleusMasks=propagate(mask,nucleusMasks, mask=mask, lambda=10000)
}

##output of computeFeatures.*() has one row per value in extendedNucleusMasks, ordered by increasing order of extendedNucleusMasks
extendedNucleusFeatures=NULL
if(!is.null(nucleusFeatures))
{
    cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.shape.area\n")
    cf.shape=computeFeatures.shape.area(extendedNucleusMasks)
    cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.bounding.box\n")
    cf.bounding.box=computeFeatures.bounding.box(extendedNucleusMasks)
    colnames(cf.bounding.box)=paste0("extended.nucleus.",colnames(cf.bounding.box))
    extendedNucleusFeatures=lapply(rownames(metadata),function(f){
        channel.name=metadata[f,"name"]
        cat(paste0("[",format(Sys.time()),"] "),"Quantifying Channel ",channel.name,"\n")
        cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.basic\n")
        cf.basic=computeFeatures.basic.v2(extendedNucleusMasks,images[[f]])
        cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.circular\n")
        cf.circular=computeFeatures.circular(extendedNucleusMasks,images[[f]],data.table(nucleusFeatures[["shape"]])[,.(id=cell.ID,x=nucleus.x,y=nucleus.y)])
        cat(paste0("[",format(Sys.time()),"] ")," done\n")
        cbind(cell.ID=nucleusFeatures[["shape"]][,"cell.ID"],cf.basic,cf.circular)
    })
    names(extendedNucleusFeatures)=rownames(metadata)
    extendedNucleusFeatures=c(list(shape=cbind(cell.ID=nucleusFeatures[["shape"]][,"cell.ID"],cf.bounding.box,cf.shape)),
                              extendedNucleusFeatures)
    ##rename columns
    colnames(extendedNucleusFeatures[["shape"]])=gsub("^s\\.","extended.nucleus.",colnames(extendedNucleusFeatures[["shape"]]))
    for(f in rownames(metadata))
    {
        colnames(extendedNucleusFeatures[[f]])=gsub("^(m|b)\\.","",colnames(extendedNucleusFeatures[[f]]))
    }

    ##check cell.ID correspond to nucleusFeatures
    cat(paste0("[",format(Sys.time()),"] "),"checking results\n")
    if(!(nrow(extendedNucleusFeatures[["shape"]])==nrow(nucleusFeatures[["shape"]])&&all(extendedNucleusFeatures[["shape"]][,"cell.ID"]==nucleusFeatures[["shape"]][,"cell.ID"])))
    {
        stop("Inconsistent cells ids")
    }
    
    ##check cell.ID correspond to extendedNucleusMasks at nucleus.x, nucleus.y
    cat(paste0("[",format(Sys.time()),"] "),"checking results\n")
    if(!all(sapply(1:nrow(extendedNucleusFeatures[["shape"]]),function(i){
        extendedNucleusFeatures[["shape"]][i,"cell.ID"]==extendedNucleusMasks[nucleusFeatures[["shape"]][i,"nucleus.x"],nucleusFeatures[["shape"]][i,"nucleus.y"]]
    })))
    {
        stop("Inconsistent cells ids")
    }
    ##check that nucleus.x,nucleus.y are inside the bounding box
    if(!all(nucleusFeatures[["shape"]][,"nucleus.x"]>=extendedNucleusFeatures[["shape"]][,"extended.nucleus.x.min"]&
            nucleusFeatures[["shape"]][,"nucleus.x"]<=extendedNucleusFeatures[["shape"]][,"extended.nucleus.x.max"]&
            nucleusFeatures[["shape"]][,"nucleus.y"]>=extendedNucleusFeatures[["shape"]][,"extended.nucleus.y.min"]&
            nucleusFeatures[["shape"]][,"nucleus.y"]<=extendedNucleusFeatures[["shape"]][,"extended.nucleus.y.max"]))
    {
        stop("inconsistent cells ids (nucleus.x,nucleus.y outside bounding box)")
    }

    if(!all(sort(unique(as.vector(extendedNucleusMasks[extendedNucleusMasks>0])))==sort(unique(extendedNucleusFeatures[[1]][,"cell.ID"]))))
    {
        stop("inconsistent cells ids")
    }
}


############################################
## Around nucleus region (i.e. "cytoplasm" region)
############################################
if(is.null(nucleusFeatures))
{
    aroundNucleusMasks=nucleusMasks*1
}
if(!is.null(nucleusFeatures))
{
    cat(paste0("[",format(Sys.time()),"] "),"around nucleus regions\n")

    ##around nucleus region=extended nucleus - nucleus
    ##Note: nucleus regions is first eroded by 1 pixel (by removing edges) to ensure non-zero "around nucleus region" area all around nucleus
    edges=filter2(nucleusMasks,matrix(c(0,1,0,1,-4,1,0,1,0), nrow = 3, ncol = 3),boundary=0)
    edges[abs(edges)<0.1]=0
    edges[abs(edges)>0]=1
    aroundNucleusMasks=extendedNucleusMasks*1
    aroundNucleusMasks[(nucleusMasks>0&edges==0)]=0
}

##output of computeFeatures.*() has one row per value in aroundNucleusMasks, ordered by increasing order of aroundNucleusMasks
aroundNucleusFeatures=NULL
if(!is.null(nucleusFeatures))
{
    cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.shape.area\n")
    cf.shape=computeFeatures.shape.area(aroundNucleusMasks)
    cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.bounding.box\n")
    cf.bounding.box=computeFeatures.bounding.box(aroundNucleusMasks)
    colnames(cf.bounding.box)=paste0("around.nucleus.",colnames(cf.bounding.box))
    aroundNucleusFeatures=lapply(rownames(metadata),function(f){
        channel.name=metadata[f,"name"]
        cat(paste0("[",format(Sys.time()),"] "),"Quantifying Channel ",channel.name,"\n")
        cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.basic\n")
        cf.basic=computeFeatures.basic.v2(aroundNucleusMasks,images[[f]])
        cat(paste0("[",format(Sys.time()),"] ")," computeFeatures.circular\n")
        cf.circular=computeFeatures.circular(aroundNucleusMasks,images[[f]],data.table(nucleusFeatures[["shape"]])[,.(id=cell.ID,x=nucleus.x,y=nucleus.y)])
        cat(paste0("[",format(Sys.time()),"] ")," done\n")
        cbind(cell.ID=nucleusFeatures[["shape"]][,"cell.ID"],cf.basic,cf.circular)
    })
    names(aroundNucleusFeatures)=rownames(metadata)
    aroundNucleusFeatures=c(list(shape=cbind(cell.ID=nucleusFeatures[["shape"]][,"cell.ID"],cf.bounding.box,cf.shape)),
                              aroundNucleusFeatures)
    ##rename columns
    colnames(aroundNucleusFeatures[["shape"]])=gsub("^s\\.","around.nucleus.",colnames(aroundNucleusFeatures[["shape"]]))
    for(f in rownames(metadata))
    {
        colnames(aroundNucleusFeatures[[f]])=gsub("^(m|b)\\.","",colnames(aroundNucleusFeatures[[f]]))
    }

    ##check cell.ID correspond to nucleusFeatures
    cat(paste0("[",format(Sys.time()),"] "),"checking results\n")
    if(!(nrow(aroundNucleusFeatures[["shape"]])==nrow(nucleusFeatures[["shape"]])&&all(aroundNucleusFeatures[["shape"]][,"cell.ID"]==nucleusFeatures[["shape"]][,"cell.ID"])))
    {
        stop("Inconsistent cells ids")
    }
    
    ##check cell.ID correspond to nucleusMasks at nucleus.x, nucleus.y
    cat(paste0("[",format(Sys.time()),"] "),"checking results\n")
    if(!all(sapply(1:nrow(aroundNucleusFeatures[["shape"]]),function(i){
        aroundNucleusFeatures[["shape"]][i,"cell.ID"]==nucleusMasks[nucleusFeatures[["shape"]][i,"nucleus.x"],nucleusFeatures[["shape"]][i,"nucleus.y"]]
    })))
    {
        stop("Inconsistent cells ids")
    }
    ##check that nucleus.x,nucleus.y are inside the bounding box
    if(!all(nucleusFeatures[["shape"]][,"nucleus.x"]>=aroundNucleusFeatures[["shape"]][,"around.nucleus.x.min"]&
            nucleusFeatures[["shape"]][,"nucleus.x"]<=aroundNucleusFeatures[["shape"]][,"around.nucleus.x.max"]&
            nucleusFeatures[["shape"]][,"nucleus.y"]>=aroundNucleusFeatures[["shape"]][,"around.nucleus.y.min"]&
            nucleusFeatures[["shape"]][,"nucleus.y"]<=aroundNucleusFeatures[["shape"]][,"around.nucleus.y.max"]))
    {
        stop("inconsistent cells ids (nucleus.x,nucleus.y outside bounding box)")
    }

    if(!all(sort(unique(as.vector(aroundNucleusMasks[aroundNucleusMasks>0])))==sort(unique(aroundNucleusFeatures[[1]][,"cell.ID"]))))
    {
        stop("inconsistent cells ids")
    }
}


############################
##bin data (image coordinates)
############################
cat(paste0("[",format(Sys.time()),"] "),"binning data\n")
data.binned.binsize=32

##average sharpness
data.binned=data.table(reshape2::melt(imageData(tenengrad),varnames=c("x","y"),value.name="tenengrad"))
data.binned=data.binned[,.(tenengrad=mean(tenengrad,na.rm=TRUE)),by=.(x=floor(convert.tile.to.image.position.x(x,image.info)/data.binned.binsize)*data.binned.binsize,y=floor(convert.tile.to.image.position.y(y,image.info)/data.binned.binsize)*data.binned.binsize)]
setkey(data.binned,x,y)
##add mean tenengrad.x
tmp=data.table(reshape2::melt(imageData(tenengrad.x),varnames=c("x","y"),value.name="tenengrad.x"))
tmp=tmp[,.(tenengrad.x=mean(tenengrad.x,na.rm=TRUE)),by=.(x=floor(convert.tile.to.image.position.x(x,image.info)/data.binned.binsize)*data.binned.binsize,y=floor(convert.tile.to.image.position.y(y,image.info)/data.binned.binsize)*data.binned.binsize)]
setkey(tmp,x,y)
data.binned=data.binned[tmp,on=c("x","y")]
##add mean tenengrad.y
tmp=data.table(reshape2::melt(imageData(tenengrad.y),varnames=c("x","y"),value.name="tenengrad.y"))
tmp=tmp[,.(tenengrad.y=mean(tenengrad.y,na.rm=TRUE)),by=.(x=floor(convert.tile.to.image.position.x(x,image.info)/data.binned.binsize)*data.binned.binsize,y=floor(convert.tile.to.image.position.y(y,image.info)/data.binned.binsize)*data.binned.binsize)]
setkey(tmp,x,y)
data.binned=data.binned[tmp,on=c("x","y")]
##keep only relevant columns
data.binned=data.binned[,.(x,y,sharpness=tenengrad-tenengrad.x**2-tenengrad.y**2)]

##channels
for(f in rownames(metadata))
{
    tmp=data.table(reshape2::melt(imageData(images[[f]]),varnames=c("x","y"),value.name="value"))
    tmp=tmp[,.(value=mean(value,na.rm=TRUE)),by=.(x=floor(convert.tile.to.image.position.x(x,image.info)/data.binned.binsize)*data.binned.binsize,y=floor(convert.tile.to.image.position.y(y,image.info)/data.binned.binsize)*data.binned.binsize)]
    setnames(tmp,"value",f)
    setkey(tmp,x,y)
    data.binned=data.binned[tmp,on=c("x","y")]
}
##is.valid
tmp=data.table(reshape2::melt(imageData(image.is.valid),varnames=c("x","y"),value.name="is.valid"))
tmp=tmp[,.(is.valid=mean(is.valid,na.rm=TRUE)),by=.(x=floor(convert.tile.to.image.position.x(x,image.info)/data.binned.binsize)*data.binned.binsize,y=floor(convert.tile.to.image.position.y(y,image.info)/data.binned.binsize)*data.binned.binsize)]
setkey(tmp,x,y)
data.binned=data.binned[tmp,on=c("x","y")]

##is.masked.low.dapi (note: save !mask.low.dapi, i.e. 0 => not masked, 1 => masked)
tmp=data.table(reshape2::melt(imageData(!mask.low.dapi),varnames=c("x","y"),value.name="is.masked.low.dapi"))
tmp=tmp[,.(is.masked.low.dapi=mean(is.masked.low.dapi,na.rm=TRUE)),by=.(x=floor(convert.tile.to.image.position.x(x,image.info)/data.binned.binsize)*data.binned.binsize,y=floor(convert.tile.to.image.position.y(y,image.info)/data.binned.binsize)*data.binned.binsize)]
setkey(tmp,x,y)
data.binned=data.binned[tmp,on=c("x","y")]


############################
##save
############################
nucleusFeatures.image=NULL
extendedNucleusFeatures.image=NULL
aroundNucleusFeatures.image=NULL
if(!is.null(nucleusFeatures))
{
    ## ###############convert to image coordinate system
    nucleusFeatures.image=lapply(nucleusFeatures,function(tmp){
        xpositions=unique(c(grep("^(around.nucleus|extended.nucleus|nucleus)\\.x\\.(min|max)$",colnames(tmp),value=TRUE),grep("nucleus.x$",colnames(tmp),value=TRUE),grep("^cx$",colnames(tmp),value=TRUE)))
        ypositions=unique(c(grep("^(around.nucleus|extended.nucleus|nucleus)\\.y\\.(min|max)$",colnames(tmp),value=TRUE),grep("nucleus.y$",colnames(tmp),value=TRUE),grep("^cy$",colnames(tmp),value=TRUE)))
        tmp[,xpositions]=convert.tile.to.image.position.x(tmp[,xpositions],image.info)
        tmp[,ypositions]=convert.tile.to.image.position.y(tmp[,ypositions],image.info)
        ##lengths:  *.perimeter *.radius.mean *.radius.sd *.radius.min *.radius.max *.majoraxis
        lengths=unique(c(grep("(around.nucleus|extended.nucleus|nucleus)\\.(perimeter|radius\\.mean|radius\\.sd|radius\\.min|radius\\.max)$",colnames(tmp),value=TRUE),
                         grep("^majoraxis$",colnames(tmp),value=TRUE)))
        tmp[,lengths]=convert.tile.to.image.length(tmp[,lengths],image.info)
        ##lengths: area
        areas=grep("^(around.nucleus|extended.nucleus|nucleus).area$",colnames(tmp),value=TRUE)
        tmp[,areas]=convert.tile.to.image.area(tmp[,areas],image.info)
        tmp
    })
    rm(nucleusFeatures)
    gc()
    ## ###############convert to image coordinate system
    extendedNucleusFeatures.image=lapply(extendedNucleusFeatures,function(tmp){
        xpositions=unique(c(grep("^(around.nucleus|extended.nucleus|nucleus)\\.x\\.(min|max)$",colnames(tmp),value=TRUE),grep("nucleus.x$",colnames(tmp),value=TRUE),grep("^cx$",colnames(tmp),value=TRUE)))
        ypositions=unique(c(grep("^(around.nucleus|extended.nucleus|nucleus)\\.y\\.(min|max)$",colnames(tmp),value=TRUE),grep("nucleus.y$",colnames(tmp),value=TRUE),grep("^cy$",colnames(tmp),value=TRUE)))
        tmp[,xpositions]=convert.tile.to.image.position.x(tmp[,xpositions],image.info)
        tmp[,ypositions]=convert.tile.to.image.position.y(tmp[,ypositions],image.info)
        ##lengths:  *.perimeter *.radius.mean *.radius.sd *.radius.min *.radius.max *.majoraxis
        lengths=unique(c(grep("(around.nucleus|extended.nucleus|nucleus)\\.(perimeter|radius\\.mean|radius\\.sd|radius\\.min|radius\\.max)$",colnames(tmp),value=TRUE),
                         grep("^majoraxis$",colnames(tmp),value=TRUE)))
        tmp[,lengths]=convert.tile.to.image.length(tmp[,lengths],image.info)
        ##lengths: area
        areas=grep("^(around.nucleus|extended.nucleus|nucleus).area$",colnames(tmp),value=TRUE)
        tmp[,areas]=convert.tile.to.image.area(tmp[,areas],image.info)
        tmp
    })
    rm(extendedNucleusFeatures)
    gc()
    ## ###############convert to image coordinate system
    aroundNucleusFeatures.image=lapply(aroundNucleusFeatures,function(tmp){
        xpositions=unique(c(grep("^(around.nucleus|extended.nucleus|nucleus)\\.x\\.(min|max)$",colnames(tmp),value=TRUE),grep("nucleus.x$",colnames(tmp),value=TRUE),grep("^cx$",colnames(tmp),value=TRUE)))
        ypositions=unique(c(grep("^(around.nucleus|extended.nucleus|nucleus)\\.y\\.(min|max)$",colnames(tmp),value=TRUE),grep("nucleus.y$",colnames(tmp),value=TRUE),grep("^cy$",colnames(tmp),value=TRUE)))
        tmp[,xpositions]=convert.tile.to.image.position.x(tmp[,xpositions],image.info)
        tmp[,ypositions]=convert.tile.to.image.position.y(tmp[,ypositions],image.info)
        ##lengths:  *.perimeter *.radius.mean *.radius.sd *.radius.min *.radius.max *.majoraxis
        lengths=unique(c(grep("(around.nucleus|extended.nucleus|nucleus)\\.(perimeter|radius\\.mean|radius\\.sd|radius\\.min|radius\\.max)$",colnames(tmp),value=TRUE),
                         grep("^majoraxis$",colnames(tmp),value=TRUE)))
        tmp[,lengths]=convert.tile.to.image.length(tmp[,lengths],image.info)
        ##lengths: area
        areas=grep("^(around.nucleus|extended.nucleus|nucleus).area$",colnames(tmp),value=TRUE)
        tmp[,areas]=convert.tile.to.image.area(tmp[,areas],image.info)
        tmp
    })
    rm(aroundNucleusFeatures)
    gc()
}

cwd=getwd()
filename=paste0(outputdir,"/output.RData")
cat(paste0("[",format(Sys.time()),"] "),"Saving results in",filename,"\n")
save(nucleusFeatures.image,extendedNucleusFeatures.image,aroundNucleusFeatures.image,data.binned,data.binned.binsize,unmixed.images.max.values,channel.dapi,channel.autofluorescence,input.image,input.dapi,input.autofluorescence,metadata,image.info,cwd,blur.sigma,blur.sigma.nosignal,threshold.dapi.positive,watershed.low.dapi,extended.nucleus.radius.pixel,sharpness.diameter.pixel,sharpness.low.threshold,sharpness.high.threshold,clip.region,convert.tile.to.slide.position.x,convert.slide.to.tile.position.x,convert.tile.to.slide.position.y,convert.slide.to.tile.position.y,convert.tile.to.slide.length,convert.slide.to.tile.length,convert.tile.to.slide.area,convert.slide.to.tile.area,convert.tile.to.image.position.x,convert.tile.to.image.position.y,convert.image.to.tile.position.x,convert.image.to.tile.position.y,convert.tile.to.image.length,convert.image.to.tile.length,convert.tile.to.image.area,convert.image.to.tile.area,convert.image.to.slide.position.x,convert.slide.to.image.position.x,convert.image.to.slide.position.y,convert.slide.to.image.position.y,convert.image.to.slide.length,convert.slide.to.image.length,convert.image.to.slide.area,convert.slide.to.image.area,unmixing.parameters,unmix_images,plot_image,get.contour.points,draw.contour.points,file=filename)

clean()
cat(paste0("[",format(Sys.time()),"] "),"Done\n")

