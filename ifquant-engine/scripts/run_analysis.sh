#!/bin/bash

# Copyright (C) 2022 Julien Dorier and UNIL (University of Lausanne).
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
    
#set -e: Any subsequent commands which fail will cause the shell script to exit immediately
#set -u: unset variables treated as an error.
#set -o pipefail: sets the exit code of a pipeline to that of the rightmost command to exit with a non-zero status, or to zero if all commands of the pipeline exit successfully.
set -euo pipefail

arguments="$@"
nprocesses=16
ncpu=$(nproc||getconf  _NPROCESSORS_ONLN||echo "")
nprocesses=$(awk 'BEGIN{ncpu="'$ncpu'";nprocesses='$nprocesses';if(ncpu!=""&&ncpu/2<nprocesses){nprocesses=int(ncpu/2)}print nprocesses}')

script_path=$(dirname $0)"/"
tmpdir=""

channel_normalization=""
phenotypes=""

#optional
excluded_regions=""
ROI=""
sample_information=""
output_path=""
metadata_channel_thresholding=""
input_image=""

report="yes"
TLS="no"
TLS_phenotype=""

tmpdir_str="${tmpdir}"
if [ -z "$tmpdir_str" ];then
   tmpdir_str="<output_dir>/tmp/"
fi

usage()
{
echo "
Usage: 
  $0 [OPTIONS]

  Unless specified using options, all parameters will be read from --path.

OPTIONS:
 --help
 --no-report                      do not create report/ (existing report/ will be erased).    
 --TLS                            search for TLS (i.e. patches of CD20+ or CD19+ cells by default, see  --TLS-phenotype).
                                  Only if markers in --TLS-phenotype are in the panel.
 --TLS-phenotype=PHENOTYPE        search for TLS as patch of cells with this phenotype (optional, used only with --TLS).
                                  If not specified, use CD20+ if it is in the panel, othewise CD19+ if it is in the panel.
                                  PHENOTYPE must be a comma separated list of marker names followed by + or -.
                                  E.g. \"CD20+,CK-\" to select cells with CD20 score above threshold
                                  and CK score below threshold (ignoring all other markers).
 --nprocesses=N                   max number of CPUs to use (default: ${nprocesses})
 --scripts-path=DIRNAME           path to scripts directory (default: ${script_path})
 --tmpdir=DIRNAME                 temp directory (default: ${tmpdir_str}). Consider using /dev/shm/.
 --channel-thresholding=FILENAME  channel thresholding information (optional).
 --channel-normalization=FILENAME file generated with unmixing parameters (unmixing_parameters_values_distribution.csv) (optional). 
                                  Used to normalize channels when plotting composite image.
 --image=FILENAME                 qptiff image (optional).
 --phenotypes=FILENAME            phenotypes definition (optional).
 --excluded-regions=FILENAME      excluded regions (optional). If not specified: no excluded region.
 --ROI=FILENAME                   regions of interest (optional). If not specified: no region of interest.
 --sample-information=FILENAME    sample information (optional)
 --path=DIRNAME                   input/output directory. Should correspond to the directory created inside --output with image name during segmentation.
"

}

for arg in "$@"; do
    opt=$(echo "$arg"|cut -d'=' -f1)
    optarg=$(echo "$arg"|sed -e s@"[^=]*"@""@|sed -e s@"^="@""@)
  shift
  case "$opt" in
      "--help")
	  usage
	  exit;
	  ;;
      "-h")
	  usage
	  exit
	  ;;
      "--no-report")
	  report="no"
	  ;;
      "--TLS")
	  TLS="yes"
	  ;;
      "--TLS-phenotype")
	  TLS_phenotype="${optarg}"
	  ;;
      "--nprocesses")
	  nprocesses="${optarg}"
	  ;;
      "--scripts-path")
	  script_path="${optarg}"
	  ;;
      "--tmpdir")
	  tmpdir="${optarg}"
	  ;;
      "--path")
	  output_path="${optarg}"
	  ;;
      "--channel-thresholding")
          metadata_channel_thresholding="${optarg}"
	  ;;
      "--channel-normalization")
	  channel_normalization="${optarg}"
	  ;;
      "--phenotypes")
	  phenotypes="${optarg}"
	  ;;
      "--excluded-regions")
	  excluded_regions="${optarg}"
	  ;;
      "--ROI")
	  ROI="${optarg}"
	  ;;
      "--sample-information")
	  sample_information="${optarg}"
	  ;;
      "--image")
	  input_image="${optarg}"
	  ;;
      *)
          usage
	  echo "Unknown option: $arg"
	  exit 1
	  ;;
  esac
done

if [ -z "$nprocesses" ];then
    usage
    echo "Missing: --nprocesses=N"
    exit 1
fi
if [ -z "$script_path" ];then
    usage
    echo "Missing: --scripts-path=DIRNAME"
    exit 1
fi
if [ -z "$output_path" ];then
    usage
    echo "Missing: --path=DIRNAME"
    exit 1
fi


if [ -z "$input_image" ];then
    input_image=$(grep "^image=" "${output_path}"/data/README.txt |cut -d'=' -f2)
fi

if [ ! -f "$input_image" ];then
    echo "ERROR: $input_image does not exist. Check paths and use --image to specify its location."
    exit 1
fi

if [ -z "$tmpdir" ];then
    tmpdir="${output_path}/tmp/"
    echo "tmpdir: ${tmpdir}"
fi

##############################
#Test dependencies
##############################

mkdir -p "${output_path}"/
2>&1 "${script_path}"/test_dependencies.sh | tee "${output_path}"/versions_analysis.txt  

2>&1 "${script_path}"/test_R_dependencies.R | tee -a "${output_path}"/versions_analysis.txt  

##############################
#copy input data
##############################

mkdir -p "${output_path}"/data/analysis/
echo "command: $0 $arguments" > "${output_path}"/data/analysis/README.txt
echo "pwd=$(pwd)" >> "${output_path}"/data/analysis/README.txt
echo "output_path=${output_path}" >> "${output_path}"/data/analysis/README.txt

if [ ! -z "${channel_normalization}" ];then
    echo "cp \"${channel_normalization}\" \"${output_path}/data/analysis/channel_normalization.txt\"" >> "${output_path}"/data/analysis/README.txt
    if ! diff -q "${channel_normalization}" "${output_path}"/data/analysis/channel_normalization.txt >& /dev/null; then
	cp "${channel_normalization}" "${output_path}"/data/analysis/channel_normalization.txt
    fi
    channel_normalization="${output_path}"/data/analysis/channel_normalization.txt
else ##reuse previously defined
    if [ -f "${output_path}"/data/analysis/channel_normalization.txt ]; then
        channel_normalization="${output_path}"/data/analysis/channel_normalization.txt
    elif [ -f "${output_path}"/data/channel_normalization.txt ]; then
        channel_normalization="${output_path}"/data/channel_normalization.txt
	echo "cp \"${channel_normalization}\" \"${output_path}/data/analysis/channel_normalization.txt\"" >> "${output_path}"/data/analysis/README.txt
	cp "${channel_normalization}" "${output_path}"/data/analysis/channel_normalization.txt
        channel_normalization="${output_path}"/data/analysis/channel_normalization.txt
    fi
fi
if [ ! -z "${phenotypes}" ];then
    echo "cp \"${phenotypes}\"  \"${output_path}/data/analysis/phenotypes.txt\"" >> "${output_path}"/data/analysis/README.txt
    if ! diff -q "${phenotypes}"  "${output_path}"/data/analysis/phenotypes.txt >& /dev/null; then
	cp "${phenotypes}"  "${output_path}"/data/analysis/phenotypes.txt
    fi
    phenotypes="${output_path}"/data/analysis/phenotypes.txt
else ##reuse previously defined phenotypes
    if [ -f "${output_path}"/data/analysis/phenotypes.txt ]; then
        phenotypes="${output_path}"/data/analysis/phenotypes.txt
    elif [ -f "${output_path}"/data/phenotypes.txt ]; then
        phenotypes="${output_path}"/data/phenotypes.txt
	echo "cp \"${phenotypes}\" \"${output_path}/data/analysis/phenotypes.txt\"" >> "${output_path}"/data/analysis/README.txt
	cp "${phenotypes}" "${output_path}"/data/analysis/phenotypes.txt
        phenotypes="${output_path}"/data/analysis/phenotypes.txt
    fi
fi

if [ ! -z "${excluded_regions}" ];then
    echo "cp \"${excluded_regions}\" \"${output_path}/data/analysis/excluded_regions.txt\"" >> "${output_path}"/data/analysis/README.txt
    if ! diff -q "${excluded_regions}" "${output_path}"/data/analysis/excluded_regions.txt >& /dev/null; then
	cp "${excluded_regions}" "${output_path}"/data/analysis/excluded_regions.txt
    fi
    excluded_regions="${output_path}"/data/analysis/excluded_regions.txt
else ##do not use excluded region (erase previously defined)
    rm -f "${output_path}"/data/analysis/excluded_regions.txt
fi

if [ ! -z "${ROI}" ];then
    echo "cp \"${ROI}\" \"${output_path}/data/analysis/ROI.txt\"" >> "${output_path}"/data/analysis/README.txt
    if ! diff -q "${ROI}" "${output_path}"/data/analysis/ROI.txt >& /dev/null; then
	cp "${ROI}" "${output_path}"/data/analysis/ROI.txt
    fi
    ROI="${output_path}"/data/analysis/ROI.txt
else ##do not use excluded region (erase previously defined)
    rm -f "${output_path}"/data/analysis/ROI.txt
fi

if [ ! -z "${sample_information}" ];then
    echo "cp \"${sample_information}\" \"${output_path}/data/analysis/sample_information.txt\"" >> "${output_path}"/data/analysis/README.txt
    if ! diff -q "${sample_information}" "${output_path}"/data/analysis/sample_information.txt >& /dev/null; then
	cp "${sample_information}" "${output_path}"/data/analysis/sample_information.txt
    fi
    sample_information="${output_path}"/data/analysis/sample_information.txt
else ##reuse if it exists
    if [ -f "${output_path}"/data/analysis/sample_information.txt ]; then
        sample_information="${output_path}"/data/analysis/sample_information.txt
    elif [ -f "${output_path}"/data/sample_information.txt ]; then
        sample_information="${output_path}"/data/sample_information.txt
	echo "cp \"${sample_information}\" \"${output_path}/data/analysis/sample_information.txt\"" >> "${output_path}"/data/analysis/README.txt
	cp "${sample_information}" "${output_path}"/data/analysis/sample_information.txt
        sample_information="${output_path}"/data/analysis/sample_information.txt
    fi
fi

if [ ! -z "${metadata_channel_thresholding}" ];then
    echo "cp \"${metadata_channel_thresholding}\" \"${output_path}/data/analysis/metadata_channel_thresholding.txt\"" >> "${output_path}"/data/analysis/README.txt
    if ! diff -q "${metadata_channel_thresholding}" "${output_path}"/data/analysis/metadata_channel_thresholding.txt >& /dev/null; then
	cp "${metadata_channel_thresholding}" "${output_path}"/data/analysis/metadata_channel_thresholding.txt
    fi
    channel_thresholding="${output_path}"/data/analysis/metadata_channel_thresholding.txt
else ##reuse if it exists
    if [ -f "${output_path}"/data/analysis/metadata_channel_thresholding.txt ]; then
	channel_thresholding="${output_path}"/data/analysis/metadata_channel_thresholding.txt
    elif [ -f "${output_path}"/data/metadata_channel_thresholding.txt ]; then
        channel_thresholding="${output_path}"/data/metadata_channel_thresholding.txt
	echo "cp \"${channel_thresholding}\" \"${output_path}/data/analysis/metadata_channel_thresholding.txt\"" >> "${output_path}"/data/analysis/README.txt
	cp "${channel_thresholding}" "${output_path}"/data/analysis/metadata_channel_thresholding.txt
        channel_thresholding="${output_path}"/data/analysis/metadata_channel_thresholding.txt
    else
	echo "ERROR: missing --channel-thresholding."
	exit 1	
    fi
fi

echo "image=${input_image}" >> "${output_path}"/data/analysis/README.txt

##############################
##final check
##############################
if [ -z "${channel_normalization}" ];then
    echo "Missing: --channel-normalization"
    exit 1
fi
if [ -z "${phenotypes}" ];then
    echo "Missing: --phenotypes"
    exit 1
fi

##############################
#Clean
##############################

rm -rf "${output_path}"/cells_properties_pixels.txt
rm -rf "${output_path}"/score_density/
rm -rf "${output_path}"/report/
rm -rf "${output_path}"/TLS/


##############################
#Tissue segmentation 
##############################
if  ! ls "${output_path}"/tissue_segmentation/latest/metadata_channel_thresholding.txt 2> /dev/null 1> /dev/null || ! diff -q "${channel_thresholding}" "${output_path}"/tissue_segmentation/latest/metadata_channel_thresholding.txt > /dev/null; then

    rm -rf "${output_path}"/tissue_segmentation/latest/
    mkdir -p "${output_path}"/tissue_segmentation/latest/

    ##save "${output_path}"/data/analysis/metadata_channel_thresholding.txt
    cp "${channel_thresholding}" "${output_path}"/tissue_segmentation/latest/
    2>&1 "${script_path}"/tissue_segmentation.R --max-cell-radius=15 --max-connectivity-dist=40 --thresholds="${channel_thresholding}" --nprocesses=${nprocesses} --output="${output_path}"/tissue_segmentation/latest/ "${output_path}"/cell_segmentation/merge_cells.RData | tee "${output_path}"/tissue_segmentation/latest/tissue_segmentation.log

    ##############################
    #Tissue type mask
    ##############################

    ##add tissue type mask (--score-type="median.extended.nucleus")
    2>&1 "${script_path}"/generate_tissue_type_mask_tiles.R --tmpdir="${tmpdir}" --nprocesses=${nprocesses} --output="${output_path}"/tissue_segmentation/latest/tissue_type_mask/ "${output_path}"/tissue_segmentation/latest/tissue_segmentation.RData
    pushd "${output_path}"/tissue_segmentation/latest/
    d=tissue_type_mask
    y_values=$(ls "$d"|sed -e s@".*tile_\([0-9]*\)_\([0-9]*\)_\([0-9]*\).png"@"\3"@|sort -ug)
    width=$(vipsheader --vips-concurrency=$nprocesses -f width ${d}/tile_*_*_0.png|awk '{s=s+$1}END{print s}') ##sum first row width
    height=$(vipsheader --vips-concurrency=$nprocesses -f height ${d}/tile_*_0_*.png|awk '{s=s+$1}END{print s}') ##sum first column height
    ##create rows
    for y in ${y_values};do
	nx=$(ls "$d"/tile_*_*_${y}.png|sed -e s@".*tile_\([0-9]*\)_\([0-9]*\)_\([0-9]*\).png"@"\2"@|sort -ug|wc -l)
	ref=$(ls "$d"/tile_*_*_${y}.png|sort |head -1 |sed -e s@".*tile_\([0-9]*\)_\([0-9]*\)_\([0-9]*\).png"@"\1"@)
	echo $y
	dest_tmp=$(echo "$d"|sed -e s@"/*$"@"_row_${ref}_${y}.tiff"@) #vips format
	## using vips
	vips --vips-concurrency=$nprocesses arrayjoin "$(ls ${d}/tile_*_*_${y}.png|sort )" "$dest_tmp" --across ${nx}
	rm  "${d}"/tile_*_*_${y}.png
    done
    rm -r "$d"
    ##join rows
    ny=$(ls "${d}"_row_*.tiff|wc -l)
    dest=$(echo "$d"|sed -e s@"/*$"@".tiff"@)
    dest_tmp=$(echo "$d"|sed -e s@"/*$"@"_tmp.tiff"@) #vips format
    dest_tmp2=$(echo "$d"|sed -e s@"/*$"@"_tmp2.tiff"@) #vips format
    ## using vips
    vips --vips-concurrency=$nprocesses arrayjoin "$(ls ${d}_row_*.tiff|sort )" "$dest_tmp" --across 1
    rm -r "$d"_row_*.tiff
    vips --vips-concurrency=$nprocesses crop  "$dest_tmp" "$dest_tmp2" 0 0 $width $height
    rm "$dest_tmp"
    vips --vips-concurrency=$nprocesses tiffsave "$dest_tmp2" "$dest" --tile --pyramid --compression deflate --tile-width 1024 --tile-height 1024 --bigtiff
    rm "$dest_tmp2"	
    #vipsthumbnail "$dest" --size 1000x -o thumbnails_%s.tiff
    popd

    ##############################
    #Tissue area
    ##############################
    ##add tissue area
    2>&1 "${script_path}"/generate_tissue_area.R --nprocesses=${nprocesses} --output="${output_path}"/tissue_segmentation/latest/tissue_area.txt "${output_path}"/tissue_segmentation/latest/tissue_segmentation.RData | tee "${output_path}"/tissue_segmentation/latest/generate_tissue_area.log

fi



##############################
#Generate results table (image coordinate system)
##############################

2>&1 "${script_path}"/generate_table.R --thresholds="${channel_thresholding}" --coordinates=image --nprocesses=${nprocesses} --output="${output_path}"/cells_properties_pixels.txt ${excluded_regions:+--excluded-regions="${excluded_regions}"} "${output_path}"/cell_segmentation/merge_cells.RData "${output_path}"/tissue_segmentation/latest/tissue_segmentation.RData | tee "${output_path}"/cell_segmentation/generate_table.log

##############################
#Generate score density plots
##############################

mkdir -p "${output_path}"/score_density/
2>&1 "${script_path}"/generate_score_density.R --thresholds="${channel_thresholding}" --nprocesses=${nprocesses} --output-resolution=256 --output="${output_path}"/score_density/ ${excluded_regions:+--excluded-regions="${excluded_regions}"} "${output_path}"/cell_segmentation/merge_cells.RData "${output_path}"/tissue_segmentation/latest/tissue_segmentation.RData | tee "${output_path}"/score_density//generate_score_density.log

##############################
#TLS 
##############################

if [  "${TLS}" == "yes" ];then
    metadata_panel="${output_path}"/data/metadata_panel.txt
    if [ -z "$TLS_phenotype" ];then
       TLS_phenotype=""
       if grep -q -i -w CD20 "${metadata_panel}"; then
           TLS_phenotype="CD20+"
       elif grep -q -i -w CD19 "${metadata_panel}"; then
           TLS_phenotype="CD19+"
       fi
    fi
    #check all markers in TLS_phenotype are in the panel
    missing="no"
    while read m;
    do
       grep -q -i -w "${m}" "${metadata_panel}" || missing="yes"
    done <<< "$(echo "${TLS_phenotype}"|tr ',' '\n'|sed -e s@"[+-]$"@@)"
    if [ "${missing}" == "yes" ]; then
	TLS_phenotype=""
    fi
    
    if [ ! -z "$TLS_phenotype" ];then
	mkdir -p "${output_path}"/TLS/
	2>&1 "${script_path}"/find_patches.R --tmpdir="${tmpdir}" --nprocesses=${nprocesses} ${excluded_regions:+--excluded-regions="${excluded_regions}"} ${ROI:+--ROI="${ROI}"} --clustering-method=none --boundary-method=alphashape --boundary-param=20 --min-density-selected=2000 --min-patch-size-selected=40 --phenotype="${TLS_phenotype}" --thresholds="${channel_thresholding}" --output-patch-mask="${output_path}"/TLS/TLS_mask/  --output="${output_path}"/TLS/ "${output_path}"/cell_segmentation/merge_cells.RData "${output_path}"/tissue_segmentation/latest/tissue_segmentation.RData | tee "${output_path}"/TLS/find_patches.log

	##TLS mask
	pushd "${output_path}"/TLS/
	d=TLS_mask
	y_values=$(ls "$d"|sed -e s@".*tile_\([0-9]*\)_\([0-9]*\)_\([0-9]*\).png"@"\3"@|sort -ug)
	width=$(vipsheader --vips-concurrency=$nprocesses -f width ${d}/tile_*_*_0.png|awk '{s=s+$1}END{print s}') ##sum first row width
	height=$(vipsheader --vips-concurrency=$nprocesses -f height ${d}/tile_*_0_*.png|awk '{s=s+$1}END{print s}') ##sum first column height
	##create rows
	for y in ${y_values};do
	    nx=$(ls "$d"/tile_*_*_${y}.png|sed -e s@".*tile_\([0-9]*\)_\([0-9]*\)_\([0-9]*\).png"@"\2"@|sort -ug|wc -l)
	    ref=$(ls "$d"/tile_*_*_${y}.png|sort |head -1 |sed -e s@".*tile_\([0-9]*\)_\([0-9]*\)_\([0-9]*\).png"@"\1"@)
	    echo $y
	    dest_tmp=$(echo "$d"|sed -e s@"/*$"@"_row_${ref}_${y}.tiff"@) #vips format
	    ## using vips
	    vips --vips-concurrency=$nprocesses arrayjoin "$(ls ${d}/tile_*_*_${y}.png|sort )" "$dest_tmp" --across ${nx}
	    rm  "${d}"/tile_*_*_${y}.png
	done
	rm -r "$d"
	##join rows
	ny=$(ls "${d}"_row_*.tiff|wc -l)
	dest=$(echo "$d"|sed -e s@"/*$"@".tiff"@)
	dest_tmp=$(echo "$d"|sed -e s@"/*$"@"_tmp.tiff"@)
	dest_tmp2=$(echo "$d"|sed -e s@"/*$"@"_tmp2.tiff"@)
	dest_tmp3=$(echo "$d"|sed -e s@"/*$"@"_tmp3.tiff"@)
	## using vips
	vips --vips-concurrency=$nprocesses arrayjoin "$(ls ${d}_row_*.tiff|sort )" "$dest_tmp" --across 1
	rm -r "$d"_row_*.tiff
	vips --vips-concurrency=$nprocesses crop  "$dest_tmp" "$dest_tmp2" 0 0 $width $height
	rm "$dest_tmp"
	vips --vips-concurrency=$nprocesses bandmean  "$dest_tmp2" "$dest_tmp3" #create single channel image
	rm "$dest_tmp2"
	vips --vips-concurrency=$nprocesses tiffsave "$dest_tmp3" "$dest" --tile --pyramid --compression deflate --tile-width 1024 --tile-height 1024 --bigtiff
	rm "$dest_tmp3"
	#vipsthumbnail "$dest" --size 1000x -o thumbnails_%s.tiff
	popd
    fi
fi

##############################
#Report
##############################

if [ "${report}" == "yes" ]; then
    TLS_data=""
    if [[ -f "${output_path}"/TLS/patches.RData ]];then
	TLS_data="${output_path}"/TLS/patches.RData
    fi

    mkdir -p "${output_path}"/report/
    2>&1 "${script_path}"/create_report.R --nprocesses=${nprocesses} --output-tables --input-image="${input_image}" --output="${output_path}"/report/ --rmarkdown="${script_path}"/report.rmd --channel-normalization="${channel_normalization}" --phenotypes="${phenotypes}" --thresholds="${channel_thresholding}" --automatic-thresholds="${output_path}"/automatic_channel_thresholding/automatic_channel_thresholding.txt --automatic-thresholds-status="${output_path}"/automatic_channel_thresholding/automatic_channel_thresholding_status.txt ${excluded_regions:+--excluded-regions="${excluded_regions}"} ${ROI:+--ROI="${ROI}"} ${sample_information:+--sample-info="${sample_information}"} ${TLS_data:+--TLS="${TLS_data}"} "${output_path}"/cell_segmentation/merge_cells.RData "${output_path}"/tissue_segmentation/latest/tissue_segmentation.RData | tee "${output_path}"/report/create_report.log

    ##decrease file size
    gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/prepress -dAutoFilterColorImages=false -dColorImageFilter=/FlateEncode -dNOPAUSE -dQUIET -dBATCH -sOutputFile="${output_path}"/report/report_tmp.pdf "${output_path}"/report/report.pdf 

    mv "${output_path}"/report/report_tmp.pdf "${output_path}"/report/report.pdf
fi



