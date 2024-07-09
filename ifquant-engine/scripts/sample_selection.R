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
 - Use low resolution channel 0 image (not unmixed).
   Pixels with value >= THRESHOLD are considered as part of a sample.
"

#default=NA => mandatory, default=NULL => optional.
option_list=list( 
    make_option(c("--tmpdir"), type="character", default=NULL,metavar="DIRNAME",
                help="Directory to save temporary images [Default R tempdir()].
\t\tConsider using /dev/shm/."),
    make_option(c("--output-debug"), type="character", default=NULL,metavar="FILENAME",
                help="Save debug plots to FILENAME (pdf format)."),
    make_option(c("--output-image"), type="character", default=NULL,metavar="FILENAME",
                help="Save low resolution channel 0 image (not unmixed) in file FILENAME (png format)."),
    make_option(c("--threshold"), type="integer", default=0,metavar="THRESHOLD",
                help="All pixels>THRESHOLD (in channel 0) are considered as part of a sample [default %default]."),
    make_option(c("--selected-region"), type="character", default=NULL,metavar="START:END",
                help="Select the region with START*image.height<y<END*image.height.
\t\tSTART and END are in fraction of the image height (i.e. must be in the interval [0,1]).
\t\tWith --selected-region, option --sample will be ignored and the automatic detection of the region will not be performed.
\t\tE.g. --selected-region=0.2:0.45."),
    make_option(c("--sample"), type="character", default=NA,metavar="M:N",
                help="Select sample M over N total samples in the image [mandatory].
\t\tSamples are numbered 1,2,...,N from top (y=0) to bottom (y=image height)."),
    make_option(c("--output"), type="character", default=NA,metavar="FILENAME",
                help="Output file with selected region [mandatory].
\t\tComma separated with header in first row, one row per points and 3 columns id,x,y.
\t\tx and y coordinates in qptiff image coordinate system, i.e. pixels with origin at the upper left corner.")
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
outputfile.debug=opt$options[["output-debug"]]
outputfile.image=opt$options[["output-image"]]
threshold=opt$options[["threshold"]]
selected.region.tmp=opt$options[["selected-region"]]
sample.tmp=opt$options[["sample"]]
outputfile=opt$options[["output"]]

##check
if(is.null(tmpdir))
{
    tmpdir=tempdir()
    cat("using tmpdir=",tmpdir,"\n",sep="")
}
option.y.start=NULL
option.y.end=NULL
if(!is.null(selected.region.tmp))
{
    if(!length(grep(":",selected.region.tmp))==1)
    {
        stop("Invalid --selected-region=",selected.region.tmp)
    }
    option.y.start=min(as.numeric(strsplit(selected.region.tmp,":")[[1]]))
    option.y.end=max(as.numeric(strsplit(selected.region.tmp,":")[[1]]))
    if(!(is.finite(option.y.start)&&is.finite(option.y.end)&&option.y.start>=0&&option.y.end<=1))
    {
        stop("Invalid --selected-region=",selected.region.tmp)
    }
}
nb.samples=NULL
selected.sample=NULL
if(!is.null(sample.tmp))
{
    if(!length(grep(":",sample.tmp))==1)
    {
        stop("Invalid --sample=",sample.tmp)
    }
    
    selected.sample=as.integer(gsub("(.*):(.*)","\\1",sample.tmp))
    nb.samples=as.integer(gsub("(.*):(.*)","\\2",sample.tmp))
    if(!(is.finite(selected.sample)&&is.finite(nb.samples)&&selected.sample>0&&selected.sample<=nb.samples))
    {
        stop("Invalid --sample=",sample.tmp)
    }
}

##positional arguments
input.image=opt$args[1]



library(fastcluster)
library(EBImage)

dir.create(dirname(outputfile),showWarnings=FALSE,recursive=TRUE)

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

flag_auto=(is.null(option.y.start)||is.null(option.y.end))

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



############################################
##load low resolution image (only dapi)
############################################

##series max: such that (image size)/2**series_max is no larger than 2K x 2K
series_max=ceiling(max(c(log2(image.info$image.width.pixel/2000),log2(image.info$image.height.pixel/2000))))
series=min(series_max,3)


tmpfile=tempfile(fileext="_channel_0.png",tmpdir=tmpdir)
cat(paste0("[",format(Sys.time()),"] "),"temp file:",tmpfile,"\n")
system2("bfconvert",args=c("-no-upgrade",paste0("-series ",series),"-channel 0",paste0("\"",input.image,"\""),paste0("\"",tmpfile,"\"")))


cat(paste0("[",format(Sys.time()),"] "),"reading",tmpfile,"\n")
im=readImage(tmpfile)
cat(paste0("[",format(Sys.time()),"] "),"removing",tmpfile,"\n")
file.remove(tmpfile)

x.scale.factor=image.info$image.width.pixel/nrow(im)
y.scale.factor=image.info$image.height.pixel/ncol(im)

if(flag_auto) ##detect region automatically
{
    nonzero.idx=which(colSums(im)>threshold)

    hc=hclust.vector(nonzero.idx)


    ##cut in nb.samples groups
    tmp=cutree(hc,k=nb.samples)

    idx=which(diff(tmp)!=0)
    separations.y.positions=(nonzero.idx[idx]+nonzero.idx[idx+1])/2
    separations.y.width=(nonzero.idx[idx+1]-nonzero.idx[idx])



    ##add image boundaries to separations
    ranges.y=cbind(start=c(0,separations.y.positions*y.scale.factor),end=c(separations.y.positions*y.scale.factor,image.info$image.height.pixel))

    range.y=ranges.y[selected.sample,]
    range.x=c(start=0,end=image.info$image.width.pixel)

}
if(!flag_auto) ##use region defined with --selected-region
{
    range.y=c(start=round(option.y.start*image.info$image.height.pixel),end=round(option.y.end*image.info$image.height.pixel))
    range.x=c(start=0,end=image.info$image.width.pixel)
}

selected.region=rbind(data.frame(id=selected.sample,x=range.x["start"],y=range.y["start"]),
                      data.frame(id=selected.sample,x=range.x["end"],y=range.y["start"]),
                      data.frame(id=selected.sample,x=range.x["end"],y=range.y["end"]),
                      data.frame(id=selected.sample,x=range.x["start"],y=range.y["end"]))
cat("Selected region start:end (fraction of image height):",paste(range(selected.region$y)/image.info$image.height.pixel,collapse=":"),"\n")
cat("creating",outputfile,"\n")
write.csv(selected.region,file=outputfile,quote=FALSE,row.names=FALSE)


if(!is.null(outputfile.debug))
{    
    #resize image to max 1000 pix
    resize.factor=1000/max(dim(im))
    im2=resize(im,w=round(resize.factor*nrow(im)))
    cat("creating",outputfile.debug,"\n")
    pdf(outputfile.debug,10*nrow(im)/max(dim(im)),10*ncol(im)/max(dim(im)))
    par(mar=.1+c(0.5,0.5,0.5,0.5),xpd=TRUE)
    yvals=1:ncol(im2)
    xvals=1:(nrow(im2))
    graphics::image(xvals,yvals,sqrt(im2),useRaster=TRUE,col=colorRampPalette(c("black","white"),space="Lab")(256),xaxt="n",yaxt="n",xlab="",ylab="",asp=1,bty="n",ylim=c(ncol(im2),1))
    polygon(selected.region[,"x"]*resize.factor/x.scale.factor,selected.region[,"y"]*resize.factor/y.scale.factor,border="red",col=rgb(1,0,0,alpha=0.1),lwd=5)
    dev.off()
}

if(!is.null(outputfile.image))
{    
    #resize image to max 1000 pix
    resize.factor=1000/max(dim(im))
    im2=resize(im,w=round(resize.factor*nrow(im)))
    im2=sqrt(im2)
    im2=im2/quantile(im2,0.999,na.rm=TRUE)
    im2[im2>1]=1
    cat("creating",outputfile.image,"\n")
    writeImage(im2,outputfile.image)
}



clean()

if(flag_auto)
{
    ##check that we have exactly nb.samples cluster separated by more than tmp.separation pixels (only when nb.sample>1)
    tmp.separation=1000
    if(nb.samples>1&&length(unique(cutree(hc,h=tmp.separation/y.scale.factor)))!=nb.samples)
        stop("Found ",length(unique(cutree(hc,h=tmp.separation/y.scale.factor)))," groups (expecting ",nb.samples," samples)",sep="")
    
    ##check separation (i.e. nb pixels below threshold) between region
    min.separation.pixel=200
    if(any(separations.y.width<=min(1,min.separation.pixel/y.scale.factor)))
        stop("samples separation too low (",paste(separations.y.width*y.scale.factor,collapse=" pixels, ")," pixels)",sep="")
    
    ##check region sizes
    min.region.height=200
    if(any(ranges.y[,"end"]-ranges.y[,"start"]<=min(1,min.region.height/y.scale.factor)))
        stop("samples height too low (",paste((ranges.y[,"end"]-ranges.y[,"start"])*y.scale.factor,collapse=" pixels, ")," pixels)",sep="")
}


cat(paste0("[",format(Sys.time()),"] "),"Done\n")
 
