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
  %prog [options] merge_cells_RData tissue_segmentation_RData"

description="
Positional arguments:
\tmerge_cells_RData
\t\tRData file generated by merge_cells.R.
\ttissue_segmentation_RData
\t\tRData file generated by tissue_segmentation.R."

epilogue=""

#default=NA => mandatory, default=NULL => optional.
option_list=list( 
    make_option(c("--nprocesses"), type="integer", default=1,metavar="N",
                help="Max number of threads to use (only for data.table) [default %default]."),
    make_option(c("--excluded-regions"), type="character", default=NULL,metavar="FILENAME",
                help="File with excluded regions (closed polygons).
\t\tComma separated format with header in the first row and 3 columns: id, x and y.
\t\tThis file can contain multiple polygons, each with a different id.
\t\tPolygons are assumed to be closed, i.e. last point will be connected to first point.
\t\tAll cells with center inside an excluded region will be ignored."),
    make_option(c("--other-tissue"), action="store_true", default=FALSE,
                help="Also consider cells with \"other\" tissue type (ignored by default if there is a tumor marker)."),
    make_option(c("--TLS"), type="character", default=NULL,metavar="FILENAME",
                help="RData file generated by find_patches.R."),
    make_option(c("--output"), type="character", default=NA,metavar="DIRNAME",
                help="Output directory [mandatory].")
)


opt=parse_args(OptionParser(option_list=option_list,
                            usage=usage,
                            description=description,
                            epilogue=epilogue
                            ),positional_arguments=2,args=args)

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

nprocesses=opt$options[["nprocesses"]]
input.excluded.regions=opt$options[["excluded-regions"]]
flag_other_tissue=opt$options[["other-tissue"]]
input.TLS=opt$options[["TLS"]]
outputdir=opt$options[["output"]]

##check
if(!(is.finite(nprocesses)&nprocesses>0))
{
    stop("--nprocesses must be a positive integer")
}

##positional arguments
input_merge_cells.RData=opt$args[1]
input_tissue_segmentation.RData=opt$args[2]


library(R.utils)  #for gzip
library(data.table) 
library(sp) #point.in.polygon
library(RColorBrewer)
library(RANN)
options(scipen=13)

##nb threads for data.table
setDTthreads(nprocesses)


if(flag_other_tissue==FALSE)
    tissue.type.list=c("stroma","tumor")
if(flag_other_tissue)
    tissue.type.list=c("stroma","tumor","other")


    

############################################
##load
############################################

cat(paste0("[",format(Sys.time()),"] "),"loading",input_merge_cells.RData,"\n")
load(input_merge_cells.RData)
image.info.tmp=image.info
metadata.tmp=metadata

cat(paste0("[",format(Sys.time()),"] "),"loading",input_tissue_segmentation.RData,"\n")
load(input_tissue_segmentation.RData)

tumor_marker_present=(length(input.ck)>0)

##simple check
if(!identical(image.info.tmp,image.info))
{
    stop("inconsistent image.info in ",input_merge_cells.RData," and ",input_tissue_segmentation.RData)
}
if(!identical(metadata.tmp,metadata))
{
    stop("inconsistent metadata in ",input_merge_cells.RData," and ",input_tissue_segmentation.RData)
}

if(!identical(voronoi.cells.summary[,as.integer(cell.ID)],as.integer(unname(nucleusFeatures.image[["shape"]][,"cell.ID"]))))
{
    stop("inconsistent data in ",input_merge_cells.RData," and ",input_tissue_segmentation.RData)
}


##add tissue.type
voronoi.cells[,tissue.type:=voronoi.cells.summary[voronoi.cells,tissue.type,on="cell.ID"]]

##check cell.ID corresponds to row index
if(!voronoi.cells.summary[,all(cell.ID==.I)])
  stop("problem with cell.ID")


if(!is.null(input.TLS))
{
    cat(paste0("[",format(Sys.time()),"] "),"loading",input.TLS,"\n")
    load(input.TLS)
    ##simple check
    if(!data.patches[,all(cell.ID==.I)])
        stop("problem with cell.ID")
}

##In the absence of tumor marker, add "other" tissue type
if(tumor_marker_present==FALSE&&!"other"%in%tissue.type.list)
    tissue.type.list=c(tissue.type.list,"other")


############################################
##load excluded region
############################################

excluded.regions=data.table(id=integer(0))
if(!is.null(input.excluded.regions))
{
    cat(paste0("[",format(Sys.time()),"] "),"reading",input.excluded.regions,"\n")
    excluded.regions=fread(input.excluded.regions)
}


############################################
## extract nucleus Features
############################################

if(is.null(nucleusFeatures.image))
{
    data.nucleus=data.table(cell.ID=numeric(0),nucleus.x=numeric(0),nucleus.y=numeric(0),nucleus.area=numeric(0),nucleus.perimeter=numeric(0))
}
if(!is.null(nucleusFeatures.image))
{
    data.nucleus=data.table(nucleusFeatures.image[["shape"]][,c("cell.ID","nucleus.x","nucleus.y","nucleus.area","nucleus.perimeter"),drop=FALSE])
}


############################################
## merge & clean
############################################
rm(extendedNucleusFeatures.image)
rm(aroundNucleusFeatures.image)
rm(nucleusFeatures.image)

if(is.null(input.TLS))
{
    data.all=data.table(data.nucleus,
                        voronoi.cells.summary[data.nucleus[,"cell.ID"],.(tissue.type,area)])
}
if(!is.null(input.TLS))
{
    data.all=data.table(data.nucleus,
                        voronoi.cells.summary[data.nucleus[,"cell.ID"],.(tissue.type,area)],
                        data.patches[data.nucleus[,"cell.ID"],.(TLS.ID=patch.ID)])
}
setkey(data.all,cell.ID)
##check cell.ID corresponds to row index
if(!data.all[,all(cell.ID==.I)])
  stop("problem with cell.ID")

rm(data.nucleus)
rm(voronoi.cells.summary)
if(!is.null(input.TLS))
    rm(data.patches)


############################################
## flag cells to filter out 
############################################

data.all[,excluded:=FALSE]
if(!is.null(input.excluded.regions))
{
    ##exclude points
    for(i in excluded.regions[,unique(id)])
        data.all$excluded=data.all$excluded|(point.in.polygon(data.all$nucleus.x,data.all$nucleus.y,excluded.regions[id==i,x],excluded.regions[id==i,y])!=0)

}

##exclude "other" tissue type
data.all[!tissue.type%in%tissue.type.list,excluded:=TRUE]

############################################
##save
############################################
dir.create(outputdir,showWarnings=FALSE,recursive=TRUE)

##convert to micron & mm^2
Precision=-floor(log10(convert.image.to.slide.length(1,image.info)))
SquarePrecision=-floor(log10(convert.image.to.slide.length(1,image.info)**2))
convert.position.x=function(x,image.info){round(convert.image.to.slide.position.x(x,image.info),digits=Precision)}
convert.position.y=function(x,image.info){round(convert.image.to.slide.position.y(x,image.info),digits=Precision)}
convert.length=function(x,image.info){round(convert.image.to.slide.length(x,image.info),digits=Precision)}
convert.area=function(x,image.info){round(convert.image.to.slide.area(x,image.info),digits=SquarePrecision)}

output.table=data.all[excluded==FALSE][,
                                       .(cell.ID,
                                         nucleus.x=convert.position.x(nucleus.x,image.info),
                                         nucleus.y=convert.position.y(nucleus.y,image.info),
                                         cell.area=convert.area(area,image.info)
                                         )]

if(!is.null(input.TLS))
{
    output.table=cbind(output.table,data.all[excluded==FALSE,.(TLS.ID)])
}

filename=paste0(outputdir,"/cells_properties_2.tsv")
cat("creating",filename,"\n")
fwrite(output.table,file=filename,sep="\t",na="NA",quote=FALSE,row.names=FALSE)
gzip(filename,destname=paste(filename,"gz",sep="."),overwrite=TRUE)

filename=paste0(outputdir,"/README_2.txt")
cat("creating",filename,"\n")
cat("cells_properties_2.tsv.gz: gzipped tab delimited file with columns\n",file=filename,sep="")
cat(" - cell.ID: cell ID.\n",file=filename,append=TRUE,sep="")
cat(" - nucleus.x: x coordinate of nucleus center in slide coordinate system (micrometer).\n",file=filename,append=TRUE,sep="")
cat(" - nucleus.y: y coordinate of nucleus center in slide coordinate system (micrometer).\n",file=filename,append=TRUE,sep="")
cat(" - cell.area: voronoi cell area (micrometer^2).\n",file=filename,append=TRUE,sep="")
if(!is.null(input.TLS))
    cat(" - TLS.ID: ID of the TLS if the cell is in a TLS. NA if the cell is not in a TLS.\n",file=filename,append=TRUE,sep="")
cat("\n",file=filename,append=TRUE,sep="")



cat(paste0("[",format(Sys.time()),"] "),"Done\n")
