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
  %prog [options]"

description="
"

epilogue="Notes:
- output to stdout up to --size values from --min to --max (not equispaced, rounded --min and --max).
"

#default=NA => mandatory, default=NULL => optional.
option_list=list( 
    make_option(c("--min"), type="numeric", default=NA,metavar="MIN",
                help="Min value [mandatory]."),
    make_option(c("--max"), type="numeric", default=NA,metavar="MAX",
                help="Max value [mandatory]."),
    make_option(c("--size"), type="integer", default=NA,metavar="N",
                help="Max number of output values [mandatory].")
)


opt=parse_args(OptionParser(option_list=option_list,
                            usage=usage,
                            description=description,
                            epilogue=epilogue
                            ),positional_arguments=0,args=args)

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
    }
}


xmin=opt$options[["min"]]
xmax=opt$options[["max"]]
N=opt$options[["size"]]

if(xmax<=xmin)
{
    cat("WARNING: --min >= --max: setting --max to --min+1\n",file=stderr())
    xmax=xmin+1
}
if(xmax<=0)
{
    cat("WARNING: --max <= 0: setting --max to 1\n",file=stderr())    
    xmax=1
}
x.all=NULL
flag_stop=FALSE
for(f in seq(ceiling(log10(xmax)),ceiling(log10(xmax))-3,by=-1))
{
    x.candidate=list()
    for(level in c(1,2,3))
    {
        for(q in seq(0,min(9,ceiling(xmax/10**f)),by=1))
        {
            if(level==1)
                is=c(5)
            if(level==2)
                is=seq(2,9,by=2)
            if(level==3)
                is=seq(1,9,by=1)
            x.tmp=q*10**(f)+is*10**(f-1)
            x.tmp=x.tmp[x.tmp>=xmin&x.tmp<=xmax]
            if(length(x.tmp)>0)
            {
                x.candidate.tmp=x.candidate
                x.candidate.tmp[[q+1]]=x.tmp
                if(length(x.all)+length(unlist(x.candidate.tmp))<=N)
                    x.candidate=x.candidate.tmp
                else
                {
                    flag_stop=TRUE
                    break
                }
            }
        }
        if(flag_stop)
            break
    }
    x.all=c(x.all,unlist(x.candidate))
    if(flag_stop)
        break
}

for(x in sort(unique(x.all)))
{
    cat(x,"\n")
}
