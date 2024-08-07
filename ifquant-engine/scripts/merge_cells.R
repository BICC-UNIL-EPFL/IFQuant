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
  %prog [options] input1 input2 ..."

description="
Positional arguments:
\tinput1, input2, ...
\t\t RData files generated by detect_cells.R script."

epilogue=""

#default=NA => mandatory, default=NULL => optional.
option_list=list(
    make_option(c("--tmpdir"), type="character", default=NULL,metavar="DIRNAME",
                help="Directory to save temporary images [Default R tempdir()].
 \t\tConsider using /dev/shm/."),
    make_option(c("--nprocesses"), type="integer", default=1,metavar="N",
                help="Max number of threads to use (only for data.table) [default %default]."),
    make_option(c("--output"), type="character", default=NA,metavar="FILENAME",
                help="Output directory [mandatory].")
)


opt=parse_args(OptionParser(option_list=option_list,
                            usage=usage,
                            description=description,
                            epilogue=epilogue
                            ),positional_arguments=c(1,Inf),args=args)

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
input.RData=opt$args




dir.create(outputdir,showWarnings=FALSE,recursive=TRUE)

library(data.table)
library(viridis)
library(EBImage)

options(scipen=13)

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
##first pass: estimate max bounding box size
############################################

#estimate border size as the max size (bounding box) of cells touching the tile border
data.tmp=lapply(input.RData,function(f){
    cat(paste0("[",format(Sys.time()),"] "),"loading",f,"\n")
    load(f)
    ncells=nrow(nucleusFeatures.image[["shape"]])
    if(is.null(ncells))ncells=0
    ##cells with extended nucleus region touching vertical borders
    ind.x=which(extendedNucleusFeatures.image[["shape"]][,"extended.nucleus.x.min"]==image.info[["tile.x"]]|
                extendedNucleusFeatures.image[["shape"]][,"extended.nucleus.x.max"]==image.info[["tile.x"]]+image.info[["tile.width"]]-1)
    ##cells with extended nucleus region touching horizontal borders
    ind.y=which(extendedNucleusFeatures.image[["shape"]][,"extended.nucleus.y.min"]==image.info[["tile.y"]]|
                extendedNucleusFeatures.image[["shape"]][,"extended.nucleus.y.max"]==image.info[["tile.y"]]+image.info[["tile.height"]]-1)
    max.dist.to.border=NA
    if(length(ind.x)+length(ind.y)>0)
    {
        max.dist.to.border=max(pmin(nucleusFeatures.image[["shape"]][ind.x,"nucleus.x"]-image.info[["tile.x"]],
                                   (image.info[["tile.x"]]+image.info[["tile.width"]]-1)-nucleusFeatures.image[["shape"]][ind.x,"nucleus.x"]),
                               pmin(nucleusFeatures.image[["shape"]][ind.y,"nucleus.y"]-image.info[["tile.y"]],
                                   (image.info[["tile.y"]]+image.info[["tile.height"]]-1)-nucleusFeatures.image[["shape"]][ind.y,"nucleus.y"]))

    }
    list("max.dist.to.border"=max.dist.to.border,"image.info"=image.info,"ncells"=ncells,"data.binned.binsize"=data.binned.binsize,"unmixed.images.max.values"=unmixed.images.max.values,"clip.region"=clip.region)
})
names(data.tmp)=input.RData

ncells=sum(sapply(data.tmp,function(x){x$ncells}))
cat(paste0("[",format(Sys.time()),"] "),"Total number of cells:",ncells," (with duplicates)\n")
##global image info
for(n in grep("^image\\.",names(data.tmp[[1]][["image.info"]]),value=TRUE))
{
    if(!all(sapply(data.tmp,function(x){identical(x$image.info[[n]],data.tmp[[1]]$image.info[[n]])})))
        stop("Inconsistent image.info")
}
image.info.global=data.tmp[[1]][["image.info"]]
image.info.global[["tile.x"]]=min(sapply(data.tmp,function(x){x$image.info[["tile.x"]]}))
image.info.global[["tile.y"]]=min(sapply(data.tmp,function(x){x$image.info[["tile.y"]]}))
image.info.global[["tile.width"]]=max(sapply(data.tmp,function(x){x$image.info[["tile.x"]]+x$image.info[["tile.width"]]}))-image.info.global[["tile.x"]]
image.info.global[["tile.height"]]=max(sapply(data.tmp,function(x){x$image.info[["tile.y"]]+x$image.info[["tile.height"]]}))-image.info.global[["tile.y"]]

##clip.region
if(!all(sapply(data.tmp,function(x){identical(x$clip.region,data.tmp[[1]]$clip.region)})))
    stop("Inconsistent clip.region")
clip.region.global=data.tmp[[1]]$clip.region

##check binsize
if(!all(sapply(data.tmp,function(x){x$data.binned.binsize==data.tmp[[1]]$data.binned.binsize})))
    stop("Inconsistent data.binned.binsize")

##find unmixed.images.max.values
unmixed.images.max.values.all=NULL
if(length(input.RData)>1)
{
    cat(paste0("[",format(Sys.time()),"] "),"evaluating max values in unmixed images\n")
    unmixed.images.max.values.all=apply(do.call("cbind",lapply(data.tmp,function(x){
        data.frame(x$unmixed.images.max.values)
    })),1,max,na.rm=TRUE)
    ##save
    filename=paste0(outputdir,"/merge_cells_unmixed_images_max_values.txt")
    cat(paste0("[",format(Sys.time()),"] "),"creating ",filename,"\n")
    write.table(data.frame(channel=gsub("channel_","",names(unmixed.images.max.values.all)),max.value=unmixed.images.max.values.all),file=filename,sep="\t",quote=FALSE,row.names=FALSE,col.names=TRUE)
}


##find overlaps
overlap.dist.min=0
if(length(input.RData)>1)
{
    cat(paste0("[",format(Sys.time()),"] "),"evaluating overlaps\n")
    data.overlaps=do.call("rbind",lapply(data.tmp,function(x){
        data.frame(
            x.min=x$image.info[["tile.x"]],
            x.max=x$image.info[["tile.x"]]+x$image.info[["tile.width"]],
            y.min=x$image.info[["tile.y"]],
            y.max=x$image.info[["tile.y"]]+x$image.info[["tile.height"]]
        )
    }))
    overlap.dist.min=min(sapply(1:nrow(data.overlaps),function(i){
        x1.min=data.overlaps[i,"x.min"]
        x1.max=data.overlaps[i,"x.max"]
        y1.min=data.overlaps[i,"y.min"]
        y1.max=data.overlaps[i,"y.max"]
        idx=which(!(data.overlaps$x.max<x1.min|
                    data.overlaps$x.min>x1.max|
                    data.overlaps$y.max<y1.min|
                    data.overlaps$y.min>y1.max))
        idx=idx[idx>i]
        if(length(idx)>0)
        {
            all.overlaps=sapply(idx,function(j){
                x2.min=data.overlaps[j,"x.min"]
                x2.max=data.overlaps[j,"x.max"]
                y2.min=data.overlaps[j,"y.min"]
                y2.max=data.overlaps[j,"y.max"]
                overlap.x=max(0,min(x2.max-x2.min,
                                    x2.max-x1.min,
                                    x1.max-x2.min,
                                    x1.max-x1.min))
                overlap.y=max(0,min(y2.max-y2.min,
                                    y2.max-y1.min,
                                    y1.max-y2.min,
                                    y1.max-y1.min))
                min(overlap.x,overlap.y)
            })
            return(min(all.overlaps[all.overlaps>0]))
        }
        return(Inf)
    }))
    cat(paste0("[",format(Sys.time()),"] ")," min overlap",overlap.dist.min,"\n")
}

border.size=max(0,overlap.dist.min/2-1)
if(ncells>0)
{
    max.dist.to.border=max(c(0,sapply(data.tmp,function(x){x$max.dist.to.border})),na.rm=TRUE)
    if(max.dist.to.border>=overlap.dist.min/2)
    {
        cat(paste0("[",format(Sys.time()),"] "),"WARNING:","max.dist.to.border>overlap.dist.min/2. max.dist.to.border=",max.dist.to.border," overlap.dist.min=",overlap.dist.min,".\n")
        warning("max.dist.to.border>overlap.dist.min/2. max.dist.to.border=",max.dist.to.border," overlap.dist.min=",overlap.dist.min)
    }
}

############################################
##main loop
############################################
positions.all=NULL
nucleusFeatures.image.all=NULL
extendedNucleusFeatures.image.all=NULL
aroundNucleusFeatures.image.all=NULL
data.binned.all=NULL
for(n in seq_along(input.RData))
{
    cat(paste0("[",format(Sys.time()),"] "),"loading",input.RData[n],"\n")
    ##load image.info, nucleusFeatures.image, extendedNucleusFeatures.image, aroundNucleusFeatures.image
    load(input.RData[n])

    ##we work in image coordinate system
    xmin=image.info[["tile.x"]]+0 #+0 to force copy
    xmax=image.info[["tile.x"]]+image.info[["tile.width"]]-1
    ymin=image.info[["tile.y"]]+0 #+0 to force copy
    ymax=image.info[["tile.y"]]+image.info[["tile.height"]]-1

    if(image.info[["tile.x"]]>max(0,clip.region.global["x.min"])) ##not on the border of the image
        xmin=xmin+border.size
    if(image.info[["tile.x"]]+image.info[["tile.width"]]<min(image.info[["image.width.pixel"]],clip.region.global["x.max"])) ##not on the border of the image
        xmax=xmax-border.size
    if(image.info[["tile.y"]]>max(0,clip.region.global["y.min"])) ##not on the border of the image
        ymin=ymin+border.size
    if(image.info[["tile.y"]]+image.info[["tile.height"]]<min(image.info[["image.height.pixel"]],clip.region.global["y.max"])) ##not on the border of the image
        ymax=ymax-border.size

    ##data.binned
    if(!is.null(data.binned.all))##merge
    {
        data.binned.all=rbind(data.binned.all,data.binned[x>=xmin&x<xmax&y>=ymin&y<ymax])
        setkey(data.binned.all,x,y)
    }
    if(is.null(data.binned.all))##create
    {
        data.binned.all=data.binned[x>=xmin&x<xmax&y>=ymin&y<ymax]
        setkey(data.binned.all,x,y)
    }


    if(is.null(nucleusFeatures.image))
    {
        rm(data.binned)
        rm(nucleusFeatures.image)
        rm(extendedNucleusFeatures.image)
        rm(aroundNucleusFeatures.image)
        next
    }

    to.keep=which(nucleusFeatures.image[["shape"]][,"nucleus.x"]>=xmin&
                  nucleusFeatures.image[["shape"]][,"nucleus.x"]<=xmax&
                  nucleusFeatures.image[["shape"]][,"nucleus.y"]>=ymin&
                  nucleusFeatures.image[["shape"]][,"nucleus.y"]<=ymax)


    ##filter
    positions.latest=data.table(tile.count=rep(1,length(to.keep)),nucleusFeatures.image[["shape"]][to.keep,c("cell.ID","nucleus.x","nucleus.y"),drop=FALSE])
    setkey(positions.latest,nucleus.x,nucleus.y)


    if(!is.null(positions.all)&&nrow(positions.latest)>0) ##merge positions
    {
        positions.all=merge(positions.all,positions.latest,all=TRUE,by=c("nucleus.x","nucleus.y"),suffixes=c("",".latest"))
        positions.all[is.na(tile.count)&!is.na(tile.count.latest),status:="latest.only"]
        positions.all[!is.na(tile.count)&is.na(tile.count.latest),status:="all.only"]
        positions.all[!is.na(tile.count)&!is.na(tile.count.latest),status:="common"]
        positions.all[is.na(tile.count),tile.count:=0]
        positions.all[!is.na(tile.count)&!is.na(tile.count.latest),tile.count:=tile.count+tile.count.latest]
        positions.all[,tile.count.latest:=NULL]
        setkey(positions.all,nucleus.x,nucleus.y)

        cat(paste0("[",format(Sys.time()),"] "),"Nb common cells:",positions.all[status=="common",.N],"\n")


        ##append new
        latest.only.cell.IDs=positions.all[status=="latest.only"]$cell.ID
        if(length(latest.only.cell.IDs)>0)
        {
            for(f in names(nucleusFeatures.image.all))
            {
                nucleusFeatures.image.all[[f]]=rbind(nucleusFeatures.image.all[[f]],nucleusFeatures.image[[f]][nucleusFeatures.image[[f]][,"cell.ID"]%in%latest.only.cell.IDs,])
            }
            for(f in names(extendedNucleusFeatures.image.all))
            {
                extendedNucleusFeatures.image.all[[f]]=rbind(extendedNucleusFeatures.image.all[[f]],extendedNucleusFeatures.image[[f]][extendedNucleusFeatures.image[[f]][,"cell.ID"]%in%latest.only.cell.IDs,])
            }
            for(f in names(aroundNucleusFeatures.image.all))
            {
                aroundNucleusFeatures.image.all[[f]]=rbind(aroundNucleusFeatures.image.all[[f]],aroundNucleusFeatures.image[[f]][aroundNucleusFeatures.image[[f]][,"cell.ID"]%in%latest.only.cell.IDs,])
            }
        }
        ##remove columns
        positions.all[,cell.ID:=NULL]
    }
    if(is.null(positions.all)&&nrow(positions.latest)>0)
    {
        nucleusFeatures.image.all=lapply(nucleusFeatures.image,function(x){
            x[x[,"cell.ID"]%in%positions.latest$cell.ID,,drop=FALSE]
        })
        extendedNucleusFeatures.image.all=lapply(extendedNucleusFeatures.image,function(x){
            x[x[,"cell.ID"]%in%positions.latest$cell.ID,,drop=FALSE]
        })
        aroundNucleusFeatures.image.all=lapply(aroundNucleusFeatures.image,function(x){
            x[x[,"cell.ID"]%in%positions.latest$cell.ID,,drop=FALSE]
        })
        positions.latest[,cell.ID:=NULL]
        positions.all=positions.latest
        setkey(positions.all,nucleus.x,nucleus.y)
    }

    rm(data.binned)
    rm(nucleusFeatures.image)
    rm(extendedNucleusFeatures.image)
    rm(aroundNucleusFeatures.image)
    rm(positions.latest)
}

if(!(is.null(positions.all)&&is.null(nucleusFeatures.image.all)&&is.null(extendedNucleusFeatures.image.all)&&is.null(aroundNucleusFeatures.image.all)))
{

    ## update cell.ID and rownames
    for(f in names(nucleusFeatures.image.all))
    {
        nucleusFeatures.image.all[[f]][,"cell.ID"]=1:nrow(nucleusFeatures.image.all[[f]])
        rownames(nucleusFeatures.image.all[[f]])=1:nrow(nucleusFeatures.image.all[[f]])
    }
    for(f in names(extendedNucleusFeatures.image.all))
    {
        extendedNucleusFeatures.image.all[[f]][,"cell.ID"]=1:nrow(extendedNucleusFeatures.image.all[[f]])
        rownames(extendedNucleusFeatures.image.all[[f]])=1:nrow(extendedNucleusFeatures.image.all[[f]])
    }
    for(f in names(aroundNucleusFeatures.image.all))
    {
        aroundNucleusFeatures.image.all[[f]][,"cell.ID"]=1:nrow(aroundNucleusFeatures.image.all[[f]])
        rownames(aroundNucleusFeatures.image.all[[f]])=1:nrow(aroundNucleusFeatures.image.all[[f]])
    }
}

#########################################
##save
#########################################

##save RData
nucleusFeatures.image=nucleusFeatures.image.all
rm(nucleusFeatures.image.all)
extendedNucleusFeatures.image=extendedNucleusFeatures.image.all
rm(extendedNucleusFeatures.image.all)
aroundNucleusFeatures.image=aroundNucleusFeatures.image.all
rm(aroundNucleusFeatures.image.all)
data.binned=data.binned.all
rm(data.binned.all)
unmixed.images.max.values=unmixed.images.max.values.all
#remove tile info
image.info=image.info.global
clip.region=clip.region.global

filename=paste0(outputdir,"/merge_cells.RData")
cat(paste0("[",format(Sys.time()),"] "),"Saving results in",filename,"\n")
save(nucleusFeatures.image,extendedNucleusFeatures.image,aroundNucleusFeatures.image,data.binned,data.binned.binsize,unmixed.images.max.values,channel.dapi,channel.autofluorescence,input.image,input.dapi,input.autofluorescence,metadata,image.info,cwd,blur.sigma,blur.sigma.nosignal,threshold.dapi.positive,watershed.low.dapi,extended.nucleus.radius.pixel,sharpness.diameter.pixel,sharpness.low.threshold,sharpness.high.threshold,clip.region,convert.tile.to.slide.position.x,convert.slide.to.tile.position.x,convert.tile.to.slide.position.y,convert.slide.to.tile.position.y,convert.tile.to.slide.length,convert.slide.to.tile.length,convert.tile.to.slide.area,convert.slide.to.tile.area,convert.tile.to.image.position.x,convert.tile.to.image.position.y,convert.image.to.tile.position.x,convert.image.to.tile.position.y,convert.tile.to.image.length,convert.image.to.tile.length,convert.tile.to.image.area,convert.image.to.tile.area,convert.image.to.slide.position.x,convert.slide.to.image.position.x,convert.image.to.slide.position.y,convert.slide.to.image.position.y,convert.image.to.slide.length,convert.slide.to.image.length,convert.image.to.slide.area,convert.slide.to.image.area,unmixing.parameters,unmix_images,plot_image,get.contour.points,draw.contour.points,file=filename)

clean()
cat(paste0("[",format(Sys.time()),"] "),"Done\n")
