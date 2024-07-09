FROM ubuntu:20.04
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ed \
		less \
		locales \
		vim-tiny \
		wget \
		ca-certificates \
		fonts-texgyre \
		openjdk-11-jre \
		libvips libvips-tools \
		libfftw3-dev  libtiff-dev libcurl4-openssl-dev \
		ghostscript \
		pandoc \
		texlive-latex-recommended texlive-xetex texlive-luatex pandoc-citeproc texlive-latex-extra texlive-extra-utils lmodern \
		libtiff-tools \
		libxml2-dev \
		libglpk-dev \
	&& rm -rf /var/lib/apt/lists/*

## Configure default locale, see https://github.com/rocker-org/rocker/issues/19
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
	&& locale-gen en_US.utf8 \
	&& /usr/sbin/update-locale LANG=en_US.UTF-8

ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
RUN locale-gen en_US.UTF-8   #for latex? 
RUN update-locale LANG=en_US.UTF-8   #for latex?


ENV R_BASE_VERSION 4

RUN apt -o APT::Sandbox::User=root update


RUN apt -y install  gnupg ca-certificates \
#  && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9 \
  && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9 \
  && echo "deb https://cloud.r-project.org/bin/linux/ubuntu focal-cran40/" >>  /etc/apt/sources.list \
  && apt -o APT::Sandbox::User=root update

## Now install R and littler, and create a link for littler in /usr/local/bin
RUN apt-get update \
        && apt-get install -y --no-install-recommends \
		r-base=${R_BASE_VERSION}* \
		r-base-dev=${R_BASE_VERSION}* \
	&& rm -rf /tmp/downloaded_packages/ /tmp/*.rds \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/bin/ifquant/scripts
RUN echo "#! /bin/bash\n/usr/local/bin/ifquant/run_segmentation.sh \"\$@\""|sed -e s@"#! "@"#!"@ > /usr/local/bin/run_segmentation.sh
RUN chmod +x /usr/local/bin/run_segmentation.sh
RUN echo "#! /bin/bash\n/usr/local/bin/ifquant/run_analysis.sh \"\$@\""|sed -e s@"#! "@"#!"@ > /usr/local/bin/run_analysis.sh
RUN chmod +x /usr/local/bin/run_analysis.sh
RUN wget https://downloads.openmicroscopy.org/bio-formats/6.6.0/artifacts/bftools.zip \
  && unzip bftools.zip \
  && rm -f bftools.zip \
  && mv bftools /usr/local/bin 
RUN  cd /usr/local/bin && for f in $(ls /usr/local/bin/bftools/*|grep -v -e ".bat$" -e ".sh$" -e ".xml$" -e ".jar$");do ln -s $f; done;
RUN cd /root/
RUN echo "options(Ncpus=8)" > ~/.Rprofile
RUN echo "deb https://cloud.r-project.org/bin/linux/ubuntu focal-cran40/" >>  /etc/apt/sources.list
RUN apt -o APT::Sandbox::User=root update
RUN R --slave  -e 'install.packages("BiocManager",repos=c("https://stat.ethz.ch/CRAN/","https://cloud.r-project.org/","http://R-Forge.R-project.org"))'
##install packages from bioconductor (needed by NMF)
RUN R --slave   -e 'if(!"Biobase"%in%rownames(installed.packages()))BiocManager::install(c("Biobase"),update=FALSE,ask=FALSE)'
##install all packages from cran
RUN R --slave   -e 'packages=c(  \
  "parallel",  \
  "data.table",  \
  "ggplot2",  \
  "gridExtra",  \
  "NMF",  \
  "viridis",  \
  "gplots",  \
  "KernSmooth",  \
  "RColorBrewer",  \
  "R.utils",  \
  "writexl",  \
  "geometry",  \
  "igraph",  \
  "RANN",  \
  "rmarkdown",  \
  "fastcluster",  \
  "sp",  \
	"optparse", \
	"RTriangle", \
	"polyclip" \
); \
for(p in packages) \
{ \
 install.packages(p,repos=c("https://stat.ethz.ch/CRAN/","https://cloud.r-project.org/","http://R-Forge.R-project.org")) \
}'
###install bioconductor packages.
RUN R --slave   -e 'packages=c( \
  "EBImage" \
); \
for(p in packages) \
{ \
BiocManager::install(p,update=FALSE,ask=FALSE) \
}'
RUN rm -f ~/.Rprofile
ENV TERM xterm