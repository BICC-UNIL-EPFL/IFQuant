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
  %prog [options] image1 image2 ..."

description="
Positional arguments:
\timage1, image2, ...
\t\tsingle stained qptiff images  (one file per single stained channel and one file with autofluorescence)."

epilogue="Notes:
 - bfconvert and showinf must be in the PATH (bftools https://www.openmicroscopy.org/bio-formats/)
 - In metadata, column \"fluorophore\" for autofluorescence file must contain AUTOFLUO
 - To find which channel corresponds to which fluorophores, column \"fluorophore\" in metadata and image
   channels (\"Name #...\" in image metadata) will be matched by searching for keywords \"DAPI\", \"AUTOFLUO\", \"AF\" and the wave lengths.
 - Image metadata (such as band names) will be extracted from the images
 - In addition to <output>.csv file, this script will generate a file <output>_values_distribution.csv.
"

#default=NA => mandatory, default=NULL => optional.
option_list=list( 
    make_option(c("-d", "--debug-plots"), action="store_true", default=FALSE,
                help="Output debug plot."),
    make_option(c("--tmpdir"), type="character", default=NULL,metavar="DIRNAME",
                help="Directory to save temporary images [Default R tempdir()].
\t\tConsider using /dev/shm/."),
    make_option(c("--pixels-per-image"), type="integer", default=500,metavar="N",
                help="Number of pixels randomly selected per image to generate the training set (WARNING: memory usage increases with N) [default %default]."),
    make_option(c("--repeat"), type="integer", default=20,metavar="N",
                help="To reduce noise due to random sampling of pixels, repeat N times the evaluation of the unmixing parameters and output the median unmixing parameters [default %default]."),
    make_option(c("--metadata"), type="character", default=NA,metavar="FILENAME",
                help="File specifying the correspondance between input file names and single fluorophores [mandatory].
\t\tTab separated with a header in the first row and at least two columns \"file\" and \"fluorophore\".
\t\tCorrespondance between input files and column \"file\" will be done by matching base file name (without path).
\t\tColumn \"fluorophore\" should contain the single fluorophore used when acquiring the image (or AUTOFLUO).
\t\tOptional columns \"x\", \"y\", \"width\", \"height\" can be added to specify region [x,x+width]x[y,y+height] to use.
\t\tNA values are replaced by 0 for x and y and by the maximum for width and height.
\t\tExample:
\t\t  file                                   fluorophore
\t\t  MM_OX7V.0Q_Library_AUTOFLUO_1.qptiff   AUTOFLUO         
\t\t  MM_OX7V.0Q_Library_CD20-O480_1.qptiff  OPAL 480
\t\t  MM_OX7V.0Q_Library_CD20-O520_1.qptiff  OPAL 520
\t\t  MM_OX7V.0Q_Library_CD20-O570_1.qptiff  OPAL 570
\t\t  MM_OX7V.0Q_Library_CD20-O620_1.qptiff  OPAL 620
\t\t  MM_OX7V.0Q_Library_CD20-O690_2.qptiff  OPAL 690
\t\t  MM_OX7V.0Q_Library_CD20-O780_1.qptiff  OPAL 780
\t\t  MM_OX7V.0Q_Library_DAPI_1.qptiff       DAPI"),
    make_option(c("--output"), type="character", default=NA,metavar="FILENAME",
                help="Output file (.csv comma separated format) [mandatory].")
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

flag_debug=opt$options[["debug-plots"]]
tmpdir=opt$options[["tmpdir"]]
npix.per.image=opt$options[["pixels-per-image"]]
nb.evaluations=opt$options[["repeat"]]
input.metadata=opt$options[["metadata"]]
outputfile=opt$options[["output"]]


##check
if(is.null(tmpdir))
{
    tmpdir=tempdir()
    cat("using tmpdir=",tmpdir,"\n",sep="")
}

##positional arguments
input.files=opt$args


library(EBImage)
library(NMF)
library(viridis) #color palettes

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
##functions (only used with flag_debug)
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

plot_image=function(x,main="",cex.main=0.8,xlab="",ylab="",zlim=NULL,sqrt=TRUE,colors=inferno(256),...)
{

    par(mar=.1+c(0.5,0.5,4,3))
    if(is.null(zlim))zlim=range(x,na.rm=TRUE)
    if(is.na(zlim[1]))zlim[1]=min(x,na.rm=TRUE)
    if(is.na(zlim[2]))zlim[2]=max(x,na.rm=TRUE)
    if(zlim[2]<zlim[1])zlim=rev(zlim)
    if(max(x,na.rm=TRUE)>zlim[2])x[x>zlim[2]]=zlim[2]
    if(min(x,na.rm=TRUE)<zlim[1])x[x<zlim[1]]=zlim[1]

    legend.width=round(max(2,0.05*nrow(x)))
    yvals=1:ncol(x)
    legend=matrix(rep(seq(zlim[2],zlim[1],length.out=length(yvals)),each=legend.width),nrow=legend.width)
    legend[1:(max(1,as.integer(0.2*nrow(legend)))),]=NA #add blank line
    xvals=1:(nrow(x)+nrow(legend))
    
    if(sqrt)
    {
        graphics::image(xvals,yvals,sqrt(rbind(x,legend)-zlim[1]),useRaster=TRUE,col=colors,zlim=sqrt(zlim-zlim[1]),xaxt="n",yaxt="n",main=main,xlab="",ylab="",asp=1,bty="n",ylim=c(ncol(x),1),cex.main=cex.main,...)
    }
    else
    {
        graphics::image(xvals,yvals,(rbind(x,legend)),useRaster=TRUE,col=colors,zlim=(zlim),xaxt="n",yaxt="n",main=main,xlab="",ylab="",asp=1,bty="n",ylim=c(ncol(x),1),cex.main=cex.main,...)
    }
    if(zlim[2]>zlim[1])
    {
        labels=pretty(zlim,10)
        labels=labels[labels>=zlim[1]&labels<=zlim[2]]
        axis(4,at=1+(ncol(x)-1)*(labels-zlim[2])/(zlim[1]-zlim[2]),labels=format(labels),cex.axis=0.7,las=2,tck= -0.01,hadj=0.5,pos=max(xvals)+0.5)
    }
    else #zlim[2]==zlim[1]
    {
        axis(4,at=c(1,ncol(x)/2,ncol(x)),labels=rep(zlim[1],3),cex.axis=0.7,las=2,tck= -0.01,hadj=0.5,pos=max(xvals)+0.5)
    }
}


############################################
##load metadata
############################################
files.metadata=read.table(input.metadata,header=TRUE,stringsAsFactors=FALSE,sep="\t")

##keep only specified images
files.metadata=files.metadata[basename(files.metadata$file)%in%basename(input.files),]

##check
if(any(duplicated(basename(input.files))))
{
    stop("All input files must have different basenames")
}

if(!all(basename(input.files)%in%basename(files.metadata$file)))
{
    stop("Files not found in metadata\n",paste(input.files[!basename(input.files)%in%basename(files.metadata$file)],collapse="\n"),"\n")
}
##replace file column by filename
files.metadata[match(basename(input.files),basename(files.metadata$file)),"file"]=input.files

rownames(files.metadata)=files.metadata$file

##############################################
##load images information
##############################################
images.info=lapply(rownames(files.metadata),function(i){
    input.image=files.metadata[i,"file"]
    ##get info on image
    cat(paste0("[",format(format(Sys.time())),"] "),"reading image information ",input.image,"\n")
    tmp.metadata=system2("showinf",args=c("-no-upgrade",paste0("\"",input.image,"\""),"-nopix"),stdout=TRUE)
    ##WARNING:
    ## bftools coordinate systems (pixels) is 0-based, i.e. origin pixel is at position (0,0).
    ## R coordinate systems (pixels) is 1-based, i.e. origin pixel is at position (1,1).
    image.resolutionunit=gsub(".*: ","",grep("ResolutionUnit",tmp.metadata,value=TRUE))
    image.xresolution=as.numeric(gsub(".*: ","",grep("XResolution",tmp.metadata,value=TRUE)))
    image.yresolution=as.numeric(gsub(".*: ","",grep("YResolution",tmp.metadata,value=TRUE)))
    image.xoffset=as.numeric(gsub(".*: ","",grep("XPosition",tmp.metadata,value=TRUE)))
    image.yoffset=as.numeric(gsub(".*: ","",grep("YPosition",tmp.metadata,value=TRUE)))
    image.width.pixel=as.numeric(gsub(".*: ","",grep("ImageWidth",tmp.metadata,value=TRUE)))
    image.height.pixel=as.numeric(gsub(".*: ","",grep("ImageLength",tmp.metadata,value=TRUE)))
    image.exposure.times=gsub(".*: ","",grep("^ExposureTime #",tmp.metadata,value=TRUE)) #qptiff
    if(length(image.exposure.times)==0)
        image.exposure.times=strsplit(gsub(".*\\[(.*)\\]","\\1",grep("^ExposureTime:",tmp.metadata,value=TRUE)),", ")[[1]] #ome.tif
    image.exposure.times=as.numeric(image.exposure.times)
    names(image.exposure.times)=paste0("channel_",(1:length(image.exposure.times))-1)
    image.channel.names=gsub(".*: ","",grep("^Name #",tmp.metadata,value=TRUE)) #qptiff
    if(length(image.channel.names)==0)
        image.channel.names=strsplit(gsub(".*\\[(.*)\\]","\\1",grep("^Name:",tmp.metadata,value=TRUE)),", ")[[1]] #ome.tif
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
    image.info
})
names(images.info)=rownames(files.metadata)


images.metadata=lapply(rownames(files.metadata),function(i){
    metadata=data.frame(channel=names(images.info[[i]]$image.channel.names),stringsAsFactors=FALSE)
    rownames(metadata)=metadata$channel
    metadata$name=images.info[[i]]$image.channel.names[rownames(metadata)]
    metadata$exposure.time=images.info[[i]]$image.exposure.times[rownames(metadata)]
    metadata
})
names(images.metadata)=rownames(files.metadata)
############################################
##add selected regions to metadata
############################################
if(!"x"%in%colnames(files.metadata))
    files.metadata$x=as.integer(NA)
if(!"y"%in%colnames(files.metadata))
    files.metadata$y=as.integer(NA)
if(!"width"%in%colnames(files.metadata))
    files.metadata$width=as.integer(NA)
if(!"height"%in%colnames(files.metadata))
    files.metadata$height=as.integer(NA)
##replace missing values
files.metadata$x=sapply(rownames(files.metadata),function(i){
    image.width=images.info[[i]]$image.width.pixel
    x=files.metadata[i,"x"]
    if(is.na(x))
        return(0)
    if(x<0)
        return(0)
    if(x>=image.width)
        return(image.width-1)
    return(x)
})
files.metadata$y=sapply(rownames(files.metadata),function(i){
    image.height=images.info[[i]]$image.height.pixel
    y=files.metadata[i,"y"]
    if(is.na(y))
        return(0)
    if(y<0)
        return(0)
    if(y>=image.height)
        return(image.height-1)
    return(y)
})
files.metadata$width=sapply(rownames(files.metadata),function(i){
    image.width=images.info[[i]]$image.width.pixel
    x=files.metadata[i,"x"]
    width=files.metadata[i,"width"]
    if(is.na(width))
        return(image.width-x)
    if(width<=0)#at least one pixel
        return(1)
    return(min(width,image.width-x))
})
files.metadata$height=sapply(rownames(files.metadata),function(i){
    image.height=images.info[[i]]$image.height.pixel
    y=files.metadata[i,"y"]
    height=files.metadata[i,"height"]
    if(is.na(height))
        return(image.height-y)
    if(height<=0)#at least one pixel
        return(1)
    return(min(height,image.height-y))
})

############################################
##generate images
############################################
images.files.tmp=lapply(rownames(files.metadata),function(i){
    input.image=files.metadata[i,"file"]
    x=files.metadata[i,"x"]
    y=files.metadata[i,"y"]
    w=files.metadata[i,"width"]
    h=files.metadata[i,"height"]
    cat(paste0("[",format(format(Sys.time())),"] "),"extracting image ",input.image," to ",tmpdir,"\n")
    tmpfile=tempfile(fileext="_channel_%c.png",tmpdir=tmpdir)
    system2("bfconvert",args=c("-no-upgrade",paste0("-crop ",x,",",y,",",w,",",h),"-series 0",paste0("\"",input.image,"\""),paste0("\"",tmpfile,"\"")))
    list.files(tmpdir,pattern=gsub("_channel_%c.png","_channel_[0-9]*.png",basename(tmpfile)),full.names=TRUE)
})
names(images.files.tmp)=rownames(files.metadata)

## ############################################
## main loop
## ############################################
runs=lapply(1:nb.evaluations,function(run){
    cat(paste0("[",format(format(Sys.time())),"] "),"run",run,"/",nb.evaluations,"\n")

    ## ############################################
    ##generate training set X (using a subset of pixels)
    ## ############################################

    X=NULL
    CoefInit=NULL
    n.channels=nrow(images.metadata[[1]])
    files.metadata$channel=NA
    cols.ranges=NULL
    cat(paste0("[",format(format(Sys.time())),"] ")," creating training set (random subset of pixels)\n")
    for(q in rownames(files.metadata))
    {
        cat(q,"\n")
        ##load images
        images=lapply(rownames(images.metadata[[q]]),function(j){
            channel=images.metadata[[q]][j,"channel"]
            f=grep(paste0(channel,".png"),images.files.tmp[[q]],value=TRUE)
            cat(paste0("[",format(format(Sys.time())),"] "),"reading",f,"\n")
            image=readImage(f)
            image=image/images.metadata[[q]][channel,"exposure.time"]
            image
        })
        names(images)=images.metadata[[q]]$channel

        
        channel.autofluorescence=images.metadata[[q]][grepl("AF|autofluo",images.metadata[[q]]$name),"channel"]
        channel.fluorophore=NULL
        if(grepl("AUTOFLUO",files.metadata[q,"fluorophore"],ignore.case=TRUE))
        {
            channel.fluorophore=images.metadata[[q]][grepl("AF|autofluo",images.metadata[[q]]$name),"channel"]
        }
        else if(grepl("DAPI",files.metadata[q,"fluorophore"],ignore.case=TRUE))
        {
            channel.fluorophore=images.metadata[[q]][grepl("DAPI",images.metadata[[q]]$name),"channel"]
        }
        else
        {
            channel.fluorophore=images.metadata[[q]][grepl(gsub(".*[o].*[^0-9]([0-9]+)","\\1",tolower(files.metadata[q,"fluorophore"])),gsub(".*[o].*[^0-9]([0-9]+)","\\1",tolower(images.metadata[[q]]$name))),"channel"]
        }
        if(length(channel.fluorophore)!=1)
            stop("could not match fluorophore name to channel name")
        files.metadata[q,"channel"]=channel.fluorophore

        if(channel.fluorophore!=channel.autofluorescence)
        {
            ##split range in 10 intervals
            r=range(images[[channel.fluorophore]])+c(-1e-10,1e-10)
            nintervals=10
            d=(r[2]-r[1])/nintervals
            pixel.ind=do.call("c",lapply(1:nintervals,function(i){
                pixel.ind.tmp=which(images[[channel.fluorophore]]>=r[1]+(i-1)*d&images[[channel.fluorophore]]<r[1]+i*d)
                unique(sample(pixel.ind.tmp,size=min(length(pixel.ind.tmp),ceiling(npix.per.image/nintervals))))
            }))
        }
        else#autofluorescence
        {
            pixel.ind=sample.int(length(images[[channel.fluorophore]]),size=npix.per.image)
        }

        
        Xtmp=matrix(NA,nrow=n.channels,ncol=length(pixel.ind))
        rownames(Xtmp)=paste0("channel_",(1:n.channels)-1)
        for(channel in paste0("channel_",(1:n.channels)-1))
        {
            Xtmp[channel,]=images[[channel]][pixel.ind]
        }
        X=cbind(X,Xtmp)

        for(channel in paste0("channel_",(1:n.channels)-1))
        {
            if(channel==channel.fluorophore||channel==channel.autofluorescence)
            {
                Xtmp[channel,]=rep(1,length(pixel.ind))
            }
            else
            {
                Xtmp[channel,]=rep(0,length(pixel.ind))
            }
        }
        CoefInit=cbind(CoefInit,Xtmp)
        cols.ranges=rbind(cols.ranges,data.frame(start=ncol(CoefInit)-ncol(Xtmp)+1,end=ncol(CoefInit)))
    }
    rownames(cols.ranges)=rownames(files.metadata)

    ##Note rownames(X) correspond to filters: images.metadata[[1]][rownames(X),"name"]
    ##Note rownames(Coef) correspond to fluorophores: files.metadata[match(rownames(CoefInit),files.metadata$channel),"fluorophore"]
    rownames(CoefInit)=paste0("emitter_",(1:n.channels)-1)
    colnames(CoefInit)=NULL
    BasisInit=matrix(0.1,ncol=n.channels,nrow=n.channels)
    rownames(BasisInit)=paste0("channel_",(1:n.channels)-1)
    colnames(BasisInit)=paste0("channel_",(1:n.channels)-1)
    diag(BasisInit)=1
    BasisInit[,channel.autofluorescence]=1/n.channels
    colnames(BasisInit)=paste0("emitter_",(1:n.channels)-1)

    ## ############################################
    ##NMF
    ## ############################################

    ##Nonnegative matrix factorization such that
    ## X ~ Basis %*% Coef + Offset_matrix#
    ## with X: measured data. 1 row per detected channel, one column per pixel
    ## Basis=basis(res) #square matrix: 1 row per detected channel, one column per emitted channel (fluorophores, possibly not in same order as detected channels, i.e. rows).
    ## Coef= coef(res)  #same size as X: 1 row per emitted channel (fluorophore), one column per pixel, with same row order as Basis column order (but possibly with other row order as X)
    ## Offset= offset(res)  #Offset is a vector: convert to matrix with same size as X: 1 row per detect channel, one column per pixel (each row is constant:  Offset_matrix[i,j]=Offset[i])
    ##i.e. (in R)
    ## X=sweep(Basis %*% Coef,1,Offset,FUN="+")
    ##
    ## In particular, to "unmix", i.e. obtain "Coef" (with Inv(Basis)=solve(Basis)=inverse of matrix Basis)
    ## Coef=Inv(Basis)%*%(X-Offset_matrix)
    ##i.e. (in R)
    ## Coef=solve(Basis)%*% sweep(X,1,Offset,FUN="-")
    ##
    ## WARNING: the factorization algorithm should absolutely preserve  0's in Coefs (initialized with 0 except for emitted channel and autofluorescence, i.e. only stained channel and autofluorescence can emit)

    cat(paste0("[",format(format(Sys.time())),"] ")," Non-negative matrix factorization (method=offset)\n")
    init=nmfModel(n.channels,X,model="NMFOffset")
    basis(init)=BasisInit
    coef(init)=CoefInit
    rm(CoefInit)
    rm(BasisInit)
    res=nmf(x=X,rank=n.channels,seed=init,method="offset")
    cat(paste0("[",format(format(Sys.time())),"] ")," done\n")
    Offset=offset(res)
    Basis=basis(res)
    Coef=coef(res)
    rm(res)

    ##Normalize columns of Basis to 1
    r=colSums(Basis)
    Basis=sweep(Basis,2,r,FUN="/")
    Coef=sweep(Coef,1,r,FUN="*")

    ##check emitting channels order
    ##autofluorescence
    fluorophore=grep("AUTOFLUO",unique(files.metadata[,"fluorophore"]),ignore.case=TRUE,value=TRUE)
    files=rownames(files.metadata)[fluorophore==files.metadata[,"fluorophore"]]
    ind=do.call("c",lapply(files,function(q){cols.ranges[q,"start"]:cols.ranges[q,"end"]}))
    r=rowMeans(Coef[,ind])
    rowname.autoflo=names(r)[order(r,decreasing=TRUE)][1]
    row.file.match=data.frame(channel.emit=rowname.autoflo,channel.measured=unique(files.metadata[files,"channel"]),fluorophore=fluorophore,stringsAsFactors=FALSE)

    row.file.match=rbind(row.file.match,do.call("rbind",lapply(grep("AUTOFLUO",unique(files.metadata[,"fluorophore"]),ignore.case=TRUE,value=TRUE,invert=TRUE),function(fluorophore){
        files=rownames(files.metadata)[fluorophore==files.metadata[,"fluorophore"]]
        ind=do.call("c",lapply(files,function(q){cols.ranges[q,"start"]:cols.ranges[q,"end"]}))
        r=rowMeans(Coef[!rownames(Coef)%in%rowname.autoflo,ind])
        channel=names(r)[order(r,decreasing=TRUE)][1]
        data.frame(channel.emit=channel,channel.measured=unique(files.metadata[files,"channel"]),fluorophore=fluorophore,stringsAsFactors=FALSE)
    })))
    if(!all(sort(row.file.match$channel.emit)==sort(paste0("emitter_",0:(nrow(row.file.match)-1)))))
    {
        stop("cannot match Non-negative matrix factorization results to fluorophores")
    }
    if(!all(gsub("emitter_","",row.file.match$channel.emit)==gsub("channel_","",row.file.match$channel.measured)))
    {
        cat("WARNING: order of emitting channels not respected during Non-negative matrix factorization\n")
    }

    ##rename Basis and Coef with fluorophore and channel names
    rownames(row.file.match)=row.file.match$channel.emit
    colnames(Basis)=row.file.match[colnames(Basis),"fluorophore"]
    rownames(Coef)=row.file.match[rownames(Coef),"fluorophore"]

    rownames(Basis)=images.metadata[[1]][rownames(Basis),"name"]
    names(Offset)=images.metadata[[1]][names(Offset),"name"]

    list(Basis=Basis,Offset=Offset)
})



##median
Basis=runs[[1]]$Basis
if(length(runs)>1)
{
    for(i in 1:nrow(Basis))
    {
        for(j in 1:ncol(Basis))
        {
            Basis[i,j]=median(sapply(runs,function(x){x$Basis[i,j]}))
        }
    }
}
Offset=runs[[1]]$Offset
if(length(runs)>1)
{
    for(i in 1:length(Offset))
    {
        Offset[i]=median(sapply(runs,function(x){x$Offset[i]}))
    }
}


dir.create(dirname(outputfile),showWarnings=FALSE,recursive=TRUE)
cat("creating",outputfile,"\n")
write.table(data.frame(name=names(Offset),Offset=Offset,Basis,check.names=FALSE),file=outputfile,sep=",",quote=FALSE,row.names=FALSE)

####################################################################
## estimate distribution of signal in the stained channel (consider only positions with strong signal)
####################################################################
##reload unmixing parameters
tmp=read.table(outputfile,sep=",",header=TRUE,check.names=FALSE)
tmp.basis=as.matrix(tmp[,-c(1,2)])
rownames(tmp.basis)=tmp[,1]
tmp.offset=as.vector(tmp[,2])
names(tmp.offset)=tmp[,1]
unmixing.parameters=list(W=tmp.basis,W_inv=solve(tmp.basis),Offset=tmp.offset)

metadata=images.metadata[[1]][,c("channel","name")]
##check that metadata are the same for all
if(!all(sapply(images.metadata,function(x){identical(metadata,x[,c("channel","name")])})))
{
    stop("Inconsistent image metadata")
}

if(!all(rownames(unmixing.parameters$W)%in%metadata$name)||!all(metadata$name%in%rownames(unmixing.parameters$W)))
{
    cat("ERROR: could not match unmixing parameters channel names to image channel names\n")
    cat(" unmixing paramters channel names:\n")
    cat("  ",paste(rownames(unmixing.parameters$W),collapse=", "),"\n")
    cat(" Image channel names:\n")
    cat("  ",paste(metadata$name,collapse=", "),"\n")
    ##remove tmp images
    invisible(lapply(rownames(files.metadata),function(q){
        ##load image and normalize by exposure time
        invisible(lapply(images.files.tmp[[q]],function(f){
            cat(paste0("[",format(format(Sys.time())),"] "),"removing",f,"\n")
            file.remove(f)
        }))
    }))
    gc()
    stop("problem with unmixing parameters (not the same channel names as image)")
}
##rename  measured channel to channel_*
ind=match(rownames(unmixing.parameters$W),metadata$name)
rownames(unmixing.parameters$W)=rownames(metadata)[ind]
names(unmixing.parameters$Offset)=rownames(metadata)[ind]
colnames(unmixing.parameters$W_inv)=rownames(metadata)[ind]

##find match between fluorophores and channels and rename to channel_*
ind=match(gsub(".*af.*|.*autofluo.*","autofluo",gsub(".*dapi.*","dapi",gsub(".*[o].*[^0-9]([0-9]+)","\\1",tolower(colnames(unmixing.parameters$W))))),gsub(".*af.*|.*autofluo.*","autofluo",gsub(".*dapi.*","dapi",gsub(".*[o].*[^0-9]([0-9]+)","\\1",tolower(metadata$name)))))
if(any(is.na(ind)))
{
    cat("ERROR: could not match unmixing parameters fluorophore names to image channel names\n")
    cat(" unmixing paramters fluorophores names:\n")
    cat("  ",paste(colnames(unmixing.parameters$W),collapse=", "),"\n")
    cat(" Image channel names:\n")
    cat("  ",paste(metadata$name,collapse=", "),"\n")
    ##remove tmp images
    invisible(lapply(rownames(files.metadata),function(q){
        ##load image and normalize by exposure time
        invisible(lapply(images.files.tmp[[q]],function(f){
            cat(paste0("[",format(format(Sys.time())),"] "),"removing",f,"\n")
            file.remove(f)
        }))
    }))
    gc()
    stop("problem with unmixing parameters (not the same channel names as image)")
}
colnames(unmixing.parameters$W)=rownames(metadata)[ind]
rownames(unmixing.parameters$W_inv)=rownames(metadata)[ind]

values.distribution=do.call("rbind",lapply(rownames(files.metadata),function(q)
{
    cat(q,"\n")
    images=lapply(rownames(images.metadata[[q]]),function(j){
        channel=images.metadata[[q]][j,"channel"]
        f=grep(paste0(channel,".png"),images.files.tmp[[q]],value=TRUE)
        cat(paste0("[",format(format(Sys.time())),"] "),"reading",f,"\n")
        image=readImage(f)
        image=image/images.metadata[[q]][channel,"exposure.time"]
        image
    })
    names(images)=images.metadata[[q]]$channel

    image.is.valid=sign(Reduce("+",images))!=0 #TRUE if not all zero (valid), FALSE if all channels at 0 (not valid)
    ##unmix image
    cat(paste0("[",format(Sys.time()),"] "),"unmixing and removing AF\n")
    images=unmix_images(images,unmixing.parameters)
    
    for(f in names(images))
    {
        images[[f]][!image.is.valid]=0
    }


    ##find stained channel 
    channel.autofluorescence=images.metadata[[q]][grepl("AF|autofluo",images.metadata[[q]]$name),"channel"]
    channel.fluorophore=NULL
    if(grepl("AUTOFLUO",files.metadata[q,"fluorophore"],ignore.case=TRUE))
    {
        channel.fluorophore=images.metadata[[q]][grepl("AF|autofluo",images.metadata[[q]]$name),"channel"]
    }
    else if(grepl("DAPI",files.metadata[q,"fluorophore"],ignore.case=TRUE))
    {
        channel.fluorophore=images.metadata[[q]][grepl("DAPI",images.metadata[[q]]$name),"channel"]
    }
    else
    {
        channel.fluorophore=images.metadata[[q]][grepl(gsub(".*[o].*[^0-9]([0-9]+)","\\1",tolower(files.metadata[q,"fluorophore"])),gsub(".*[o].*[^0-9]([0-9]+)","\\1",tolower(images.metadata[[q]]$name))),"channel"]
    }
    if(length(channel.fluorophore)!=1)
        stop("could not match fluorophore name to channel name")
    
    
    image=images[[channel.fluorophore]]
    mask=thresh(gblur(image,2), w=10, h=10, offset=1)
    
    data.frame(mean=mean(gblur(image,2)[mask==1]),t(quantile(gblur(image,2)[mask==1],probs=c(0,0.01,0.05,0.1,0.25,0.5,0.75,0.90,0.95,0.99,1))),check.names=FALSE,row.names=channel.fluorophore)
}))
##reorder
values.distribution=cbind(metadata,values.distribution[rownames(metadata),])
colnames(values.distribution)[grep("%",colnames(values.distribution))]=paste0("q",formatC(as.numeric(gsub("%","",colnames(values.distribution)[grep("%",colnames(values.distribution))])),width=3,format="d",flag="0"))

filename=gsub("(\\.txt|\\.csv)*$","_values_distribution\\1",outputfile)
cat("creating",filename,"\n")
write.table(values.distribution,file=filename,sep=",",quote=FALSE,row.names=FALSE)


####################################################################
#debug plots
####################################################################
if(flag_debug)
{
    filename=gsub("(\\.txt|\\.csv)*$",".pdf",outputfile)
    cat("creating",filename,"\n")
    dir.create(dirname(filename),showWarnings=FALSE,recursive=TRUE)
    pdf(filename,10,10)
    for(q in rownames(files.metadata))
    {
        cat(q,"\n")
        images=lapply(rownames(images.metadata[[q]]),function(j){
            channel=images.metadata[[q]][j,"channel"]
            f=grep(paste0(channel,".png"),images.files.tmp[[q]],value=TRUE)
            cat(paste0("[",format(format(Sys.time())),"] "),"reading",f,"\n")
            image=readImage(f)
            image=image/images.metadata[[q]][channel,"exposure.time"]
            image
        })
        names(images)=images.metadata[[q]]$channel

        ##plot original images
        n=length(images)
        nc=ceiling(sqrt(n))
        nr=ceiling(n/nc)
        par(mfrow=c(nr,nc))
        par(oma=c(0,0,2.5,0))
        zranges=c(0,max(sapply(images,range)))
        resize_factor=4
        zranges.resized=c(0,max(sapply(images,function(x){range(resize(x,w=round(dim(x)[1]/resize_factor)))})))
        for(channel in names(images))
        {
            plot_image(resize(images[[channel]],w=round(dim(images[[channel]])[1]/resize_factor)),main=paste0(channel," - ",images.metadata[[q]][channel,"name"]),zlim=zranges.resized)
        }
        title(paste0(basename(q),"\nRaw image / exposure time  (resized by 1/4)"),outer=TRUE)

        
        image.is.valid=sign(Reduce("+",images))!=0 #TRUE if not all zero (valid), FALSE if all channels at 0 (not valid)
        ##unmix image
        cat(paste0("[",format(Sys.time()),"] "),"unmixing and removing AF\n")
        images=unmix_images(images,unmixing.parameters)
        
        for(f in names(images))
        {
            images[[f]][!image.is.valid]=0
        }

        ##plot umixed images
        n=length(images)
        nc=ceiling(sqrt(n))
        nr=ceiling(n/nc)
        par(mfrow=c(nr,nc))
        par(oma=c(0,0,2.5,0))
        zranges=c(0,max(sapply(images,range)))
        resize_factor=4
        zranges.resized=c(0,max(sapply(images,function(x){range(resize(x,w=round(dim(x)[1]/resize_factor)))})))
        for(channel in names(images))
        {
            plot_image(resize(images[[channel]],w=round(dim(images[[channel]])[1]/resize_factor)),main=paste0(channel," - ",images.metadata[[q]][channel,"name"]),zlim=zranges.resized)
        }
        title(paste0(basename(q),"\nUnmixed images (resized by 1/4)"),outer=TRUE)

        
    }
    dev.off()
}

##remove tmp images
invisible(lapply(rownames(files.metadata),function(q){
    ##load image and normalize by exposure time
    invisible(lapply(images.files.tmp[[q]],function(f){
        cat(paste0("[",format(format(Sys.time())),"] "),"removing",f,"\n")
        file.remove(f)
    }))
}))
gc()

clean()
cat(paste0("[",format(Sys.time()),"] "),"Done\n")
