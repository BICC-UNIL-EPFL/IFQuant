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

unmixing_parameters=""
metadata_panel=""
channel_normalization=""
metadata_channel_thresholding=""
phenotypes=""

sample_selection="1:1"
sample_selection_range=""

input_image=""

#optional
sample_information=""
output_dir="./"

tmpdir_str="${tmpdir}"
if [ -z "$tmpdir_str" ];then
   tmpdir_str="<output_dir>/tmp/"
fi

usage()
{
echo "
Usage: 
  $0 [OPTIONS]

OPTIONS:
 --help
 --nprocesses=N                      max number of CPUs to use (default: ${nprocesses})
 --scripts-path=DIRNAME              path to scripts directory (default: ${script_path})
 --tmpdir=DIRNAME                    temp directory (default: ${tmpdir_str}). Consider using /dev/shm/.
 --output=DIRNAME                    output directory. A directory with image name will be created in this directory (default: ${output_dir})
 --unmixing-parameters=FILENAME      unmixing parameters
 --metadata-panel=FILENAME           panel metadata
 --channel-normalization=FILENAME    file generated with unmixing parameters (unmixing_parameters_values_distribution.csv). Used to normalize channels when plotting composite image.
 --channel-thresholding=FILENAME     default channel thresholding information.
 --sample-selection=n:N              select sample n, assuming that the image contains N samples (default: ${sample_selection}). Samples are numbered 1,2,...,N from top (y=0) to bottom (y=image height).
 --sample-selection-range=start:end  ignore --sample-selection and directly select the region from start to end, with start and end in fraction of image height i.e. from 0 (top) to 1 (bottom). (optional)
 --phenotypes=FILENAME               phenotypes definition (optional, not used in this script, only stored for later)
 --sample-information=FILENAME       sample information (optional, not used in this script, only stored for later)
 --image=FILENAME                    qptiff image
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
      "--nprocesses")
	  nprocesses="${optarg}"
	  ;;
      "--scripts-path")
	  script_path="${optarg}"
	  ;;
      "--tmpdir")
	  tmpdir="${optarg}"
	  ;;
      "--output")
	  output_dir="${optarg}"
	  ;;
      "--unmixing-parameters")
	  unmixing_parameters="${optarg}"
	  ;;
      "--metadata-panel")
	  metadata_panel="${optarg}"
	  ;;
      "--channel-normalization")
	  channel_normalization="${optarg}"
	  ;;
      "--channel-thresholding")
          metadata_channel_thresholding="${optarg}"
	  ;;
      "--sample-selection")
          sample_selection="${optarg}"
	  ;;
      "--sample-selection-range")
          sample_selection_range="${optarg}"
	  ;;
      "--phenotypes")
	  phenotypes="${optarg}"
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
if [ -z "$output_dir" ];then
    usage
    echo "Missing: --output=DIRNAME"
    exit 1
fi
if [ -z "$unmixing_parameters" ];then
    usage
    echo "Missing: --unmixing-parameters=FILENAME"
    exit 1
fi
if [ -z "$metadata_panel" ];then
    usage
    echo "Missing: --metadata-panel=FILENAME"
    exit 1
fi
if [ -z "$channel_normalization" ];then
    usage
    echo "Missing: --channel-normalization=FILENAME"
    exit 1
fi
if [ -z "$metadata_channel_thresholding" ];then
    usage
    echo "Missing: --channel-thresholding=FILENAME"
    exit 1
fi
if [ -z "$sample_selection" ];then
    usage
 echo "Missing: --sample-selection=n:N"
    exit 1
fi
if [ -z "$input_image" ];then
    usage
    echo "Missing: --image=FILENAME"
    exit 1
fi


##Cells segmentation:
tiles_overlap=400
tiles_size=1600

output_path="${output_dir}"/$(basename $input_image|sed -e s@"\(.qptiff\|.ome.tif\|.ome.tiff\)$"@@)

if [ -z "$tmpdir" ];then
    tmpdir="${output_path}/tmp/"
    echo "tmpdir: ${tmpdir}"
fi

##############################
#Clean
##############################

rm -rf "${output_path}"/*

##############################
#Test dependencies
##############################

mkdir -p "${output_path}"/
2>&1 "${script_path}"/test_dependencies.sh | tee "${output_path}"/versions_segmentation.txt  

2>&1 "${script_path}"/test_R_dependencies.R | tee -a "${output_path}"/versions_segmentation.txt  

##############################
#copy input data
##############################

mkdir -p "${output_path}"/data/
echo "command: $0 $arguments" > "${output_path}"/data/README.txt
echo "pwd=$(pwd)" >> "${output_path}"/data/README.txt
echo "output_path=${output_path}" >> "${output_path}"/data/README.txt

echo "cp \"${unmixing_parameters}\"  \"${output_path}/data/unmixing_parameters.txt\"" >> "${output_path}"/data/README.txt
if ! diff -q "${unmixing_parameters}" "${output_path}"/data/unmixing_parameters.txt >& /dev/null; then
    cp "${unmixing_parameters}" "${output_path}"/data/unmixing_parameters.txt
fi
unmixing_parameters="${output_path}"/data/unmixing_parameters.txt

echo "cp \"${metadata_panel}\"   \"${output_path}/data/metadata_panel.txt\"" >> "${output_path}"/data/README.txt
if ! diff -q "${metadata_panel}" "${output_path}"/data/metadata_panel.txt >& /dev/null; then
    cp "${metadata_panel}" "${output_path}"/data/metadata_panel.txt
fi
metadata_panel="${output_path}"/data/metadata_panel.txt

echo "cp \"${channel_normalization}\" \"${output_path}/data/channel_normalization.txt\"" >> "${output_path}"/data/README.txt
if ! diff -q "${channel_normalization}" "${output_path}"/data/channel_normalization.txt >& /dev/null; then
    cp "${channel_normalization}" "${output_path}"/data/channel_normalization.txt
fi
channel_normalization="${output_path}"/data/channel_normalization.txt

echo "cp \"${metadata_channel_thresholding}\" \"${output_path}/data/metadata_channel_thresholding.txt\"" >> "${output_path}"/data/README.txt
if ! diff -q "${metadata_channel_thresholding}" "${output_path}"/data/metadata_channel_thresholding.txt >& /dev/null; then
    cp "${metadata_channel_thresholding}" "${output_path}"/data/metadata_channel_thresholding.txt
fi
channel_thresholding="${output_path}"/data/metadata_channel_thresholding.txt

if [ ! -z "${phenotypes}" ];then
    echo "cp \"${phenotypes}\"  \"${output_path}/data/phenotypes.txt\"" >> "${output_path}"/data/README.txt
    if ! diff -q "${phenotypes}"  "${output_path}"/data/phenotypes.txt >& /dev/null; then
	cp "${phenotypes}"  "${output_path}"/data/phenotypes.txt
    fi
    phenotypes="${output_path}"/data/phenotypes.txt
fi

if [ ! -z "${sample_information}" ];then
    echo "cp \"${sample_information}\" \"${output_path}/data/sample_information.txt\"" >> "${output_path}"/data/README.txt
    if ! diff -q "${sample_information}" "${output_path}"/data/sample_information.txt >& /dev/null; then
	cp "${sample_information}" "${output_path}"/data/sample_information.txt
    fi
    sample_information="${output_path}"/data/sample_information.txt
fi

echo "image=${input_image}" >> "${output_path}"/data/README.txt


##############################
#find tumor marker
##############################

tumor_marker=$(cat "${metadata_panel}"|awk -F '\t' '{if(NR==1){for(i=1;i<=NF;i++){if($i=="name")colname=i;if($i=="type")coltype=i}}else{split($coltype,types,",");for(i in types){if(types[i]=="tumor")print $colname}}}')
if [ -z "${tumor_marker}" ];then
    tumor_marker="MISSINGTUMORMARKER"
fi
tumor_marker_lowercase=$(echo "${tumor_marker}" | tr '[:upper:]' '[:lower:]')

##############################
#check image
##############################
tiffinfo -D "${input_image}" > /dev/null || (echo "ERROR: ${input_image} not valid." | tee "${output_path}"/error.log; exit 1)

##############################
#Sample selection
##############################

mkdir -p "${output_path}"/sample_selection/
2>&1 "${script_path}"/sample_selection.R --sample=${sample_selection} ${sample_selection_range:+--selected-region="${sample_selection_range}"} --tmpdir="${tmpdir}" --output="${output_path}"/sample_selection/sample_selection.txt --output-debug="${output_path}"/sample_selection/sample_selection.pdf --output-image="${output_path}"/sample_selection/image.png "${input_image}" | tee "${output_path}"/sample_selection/sample_selection.log


##############################
#Cells segmentation
##############################

mkdir -p "${output_path}"/cell_segmentation/
"${script_path}"/get_tiles.R --clip="${output_path}"/sample_selection/sample_selection.txt --overlap=$tiles_overlap --tile-size=$tiles_size  "${input_image}" > "${output_path}"/cell_segmentation/tiles.txt
for tile in $(cat "${output_path}"/cell_segmentation/tiles.txt);do
  dest="${output_path}"/cell_segmentation/tile_$(echo $tile|cut -d',' -f1,2|tr ',' '_')"/"
  if [[ ! -f "${dest}"/output.RData ]];then
    echo "${dest}"
    mkdir -p "${dest}"
    2>&1 "${script_path}"/detect_cells.R --clip="${output_path}"/sample_selection/sample_selection.txt --extended-nucleus=5 --unmixing-parameters="${unmixing_parameters}" --tmpdir="${tmpdir}" --metadata="${metadata_panel}" --output="${dest}"/ --tile=$tile --tile-unit=pixel "${input_image}" | tee "${dest}"/detect_cells.log &
  fi
  cnt=`jobs | grep -vc Done || [[ $? == 1 ]]`
  while [ $cnt -ge $nprocesses ]; do
    sleep 1
    cnt=`jobs | grep -vc Done || [[ $? == 1 ]]`
  done                    
done
wait


#####check status
echo "tile status"|tr ' ' '\t' > "${output_path}"/cell_segmentation/detect_cells_status.txt
for tile in $(cat "${output_path}"/cell_segmentation/tiles.txt);do
    dest="${output_path}"/cell_segmentation/tile_$(echo $tile|cut -d',' -f1,2|tr ',' '_')"/"
    status="SUCCESS"
    if ! grep Done "${dest}"/detect_cells.log >& /dev/null;then
	status="FAILED";
    fi
    if ! ls "${dest}"/output.RData >& /dev/null;then
	status="FAILED";
    fi
    echo ${tile} $status|tr ' ' '\t' >> "${output_path}"/cell_segmentation/detect_cells_status.txt
done

##############################
#Merge tiles
##############################
2>&1 "${script_path}"/merge_cells.R --tmpdir="${tmpdir}" --nprocesses=${nprocesses} --output="${output_path}"/cell_segmentation/ "${output_path}"/cell_segmentation/tile_*_*/output.RData | tee "${output_path}"/cell_segmentation/merge_cells.log

###remove tiles
rm -r "${output_path}"/cell_segmentation/tile_*_*/

##############################
#generate sharpness mask
##############################

mkdir -p "${output_path}"/cell_segmentation/
2>&1 "${script_path}"/generate_sharpness_mask_tiles.R --clip="${output_path}"/sample_selection/sample_selection.txt --nprocesses=${nprocesses} --tile-size=$tiles_size --unmixing-parameters="${unmixing_parameters}" --tmpdir="${tmpdir}" --metadata="${metadata_panel}" --output="${output_path}"/cell_segmentation/ "${input_image}" | tee "${output_path}"/cell_segmentation/generate_sharpness_mask_tiles.log

pushd "${output_path}"/cell_segmentation/
d=sharpness
if [[ -d "$d" ]];then
    echo $d
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
fi
popd

##############################
#generate saturation mask
##############################

mkdir -p "${output_path}"/cell_segmentation/
2>&1 "${script_path}"/generate_saturation_mask_tiles.R --clip="${output_path}"/sample_selection/sample_selection.txt --nprocesses=${nprocesses} --tile-size=$tiles_size --tmpdir="${tmpdir}" --output="${output_path}"/cell_segmentation/ "${input_image}" | tee "${output_path}"/cell_segmentation/generate_saturation_mask_tiles.log

pushd "${output_path}"/cell_segmentation/
d=saturation
if [[ -d "$d" ]];then
    echo $d
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
fi
popd

##############################
#generate unmixed images
##############################

##get normalization
#maxvalue=$(cat "${output_path}"/cell_segmentation/merge_cells_unmixed_images_max_values.txt|grep -v "max.value"|cut -f2|awk 'BEGIN{m=0}{if($1>m)m=$1}END{print m}')
maxvalue=128
##empirical correction for 40x images (i.e. 40x image: factor=2, 20x images: factor=1)
factor=$(showinf -nopix -no-upgrade "${input_image}" |grep XResolution|awk '{print $2/20154}')
maxvalue=$(echo $maxvalue $factor|awk '{print int($1*$2+0.5)}')

mkdir -p "${output_path}"/sqrt_unmixed_images/
2>&1 "${script_path}"/generate_unmixed_tiles.R --clip="${output_path}"/sample_selection/sample_selection.txt --nprocesses=${nprocesses} --tile-size=$tiles_size --sqrt --normalization=${maxvalue} --channel-normalization="${channel_normalization}" --unmixing-parameters="${unmixing_parameters}" --tmpdir="${tmpdir}" --metadata="${metadata_panel}" --output="${output_path}"/sqrt_unmixed_images/ "${input_image}" | tee "${output_path}"/sqrt_unmixed_images/generate_unmixed_tiles.log

pushd "${output_path}"/sqrt_unmixed_images/
for d in channel*;do
    if [[ -d "$d" ]];then
	echo $d
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
	## using vips
	vips --vips-concurrency=$nprocesses arrayjoin "$(ls ${d}_row_*.tiff|sort )" "$dest_tmp" --across 1
	rm -r "$d"_row_*.tiff
	vips --vips-concurrency=$nprocesses crop  "$dest_tmp" "$dest" 0 0 $width $height
	rm "$dest_tmp"
	#vipsthumbnail "$dest" --size 1000x -o thumbnails_%s.tiff
    fi
done
images=$(ls channel*tiff|sed -e s@"channel_\([0-9]*\)_.*tiff"@"\1\t&"@|sort -k1n |cut -f2)
vips --vips-concurrency=$nprocesses bandjoin "$images" image_unmixed.v
rm $images
vipsedit image_unmixed.v -i multiband
vips tiffsave image_unmixed.v image_unmixed.tiff --pyramid --compression deflate --tile --tile-width 1024 --tile-height 1024 --bigtiff
rm image_unmixed.v
popd


##############################
#Create metadata_channel_thresholding & automatic estimation of thresholds
##############################

mkdir -p "${output_path}"/data/analysis/
mkdir -p "${output_path}"/automatic_channel_thresholding/

2>&1 "${script_path}"/automatic_channel_thresholding.R --transformation=asinh --thresholds="${channel_thresholding}" --nprocesses=${nprocesses} --output="${output_path}"/automatic_channel_thresholding/ "${output_path}"/cell_segmentation/merge_cells.RData | tee "${output_path}"/automatic_channel_thresholding/automatic_channel_thresholding.log

##save to "${output_path}"/data/analysis and use this one for the remaining analysis
cp "${output_path}"/automatic_channel_thresholding/automatic_channel_thresholding.txt "${output_path}"/data/analysis/metadata_channel_thresholding.txt
channel_thresholding="${output_path}"/data/analysis/metadata_channel_thresholding.txt

##############################
#Tissue segmentation 
##############################

mkdir -p "${output_path}"/tissue_segmentation/latest/
##save "${channel_thresholding}"
cp "${channel_thresholding}" "${output_path}"/tissue_segmentation/latest/
2>&1 "${script_path}"/tissue_segmentation.R --max-cell-radius=15 --max-connectivity-dist=40 --thresholds="${output_path}"/tissue_segmentation/latest/metadata_channel_thresholding.txt --nprocesses=${nprocesses} --output="${output_path}"/tissue_segmentation/latest/ "${output_path}"/cell_segmentation/merge_cells.RData | tee "${output_path}"/tissue_segmentation/latest/tissue_segmentation.log

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



##############################
#Tissue segmentation with several test thresholds
##############################

if [[ "${tumor_marker}" != "MISSINGTUMORMARKER" ]];then
    ##list of test thresholds
    nb_ck_thresholds=22
    auto_ck_threshold=$(grep -w -e "${tumor_marker}" "${output_path}"/automatic_channel_thresholding/automatic_channel_thresholding.txt|cut -f4)
    ck_q01=$(grep -e "${tumor_marker} channel score distribution" "${output_path}"/automatic_channel_thresholding/automatic_channel_thresholding.log|sed -e s@".*100%): "@@|tr ',' '\t'|cut -f2)
    ck_q99=$(grep "${tumor_marker} channel score distribution" "${output_path}"/automatic_channel_thresholding/automatic_channel_thresholding.log|sed -e s@".*100%): "@@|tr ',' '\t'|cut -f6)
    ck_thresholds=$("${script_path}"/get_sequence.R --min=${ck_q01} --max=${ck_q99} --size=${nb_ck_thresholds})

    for ck in $auto_ck_threshold $ck_thresholds;do
        mkdir -p "${output_path}"/tissue_segmentation/"${tumor_marker_lowercase}"_${ck}/
        2>&1 "${script_path}"/tissue_segmentation.R --max-cell-radius=15 --max-connectivity-dist=40 --thresholds="${channel_thresholding}" --tumor-marker-threshold=$ck --nprocesses=${nprocesses} --output="${output_path}"/tissue_segmentation/"${tumor_marker_lowercase}"_${ck}/ "${output_path}"/cell_segmentation/merge_cells.RData | tee "${output_path}"/tissue_segmentation/"${tumor_marker_lowercase}"_${ck}/tissue_segmentation.log
    
        ##add tissue type mask (--score-type="median.extended.nucleus")
        2>&1 "${script_path}"/generate_tissue_type_mask_tiles.R --tmpdir="${tmpdir}" --nprocesses=${nprocesses} --output="${output_path}"/tissue_segmentation/"${tumor_marker_lowercase}"_${ck}/tissue_type_mask/ "${output_path}"/tissue_segmentation/"${tumor_marker_lowercase}"_${ck}/tissue_segmentation.RData
        pushd "${output_path}"/tissue_segmentation/"${tumor_marker_lowercase}"_${ck}/
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
    
        ##add tissue area
        2>&1 "${script_path}"/generate_tissue_area.R --nprocesses=${nprocesses} --output="${output_path}"/tissue_segmentation/"${tumor_marker_lowercase}"_${ck}/tissue_area.txt "${output_path}"/tissue_segmentation/"${tumor_marker_lowercase}"_${ck}/tissue_segmentation.RData | tee "${output_path}"/tissue_segmentation/"${tumor_marker_lowercase}"_${ck}/generate_tissue_area.log
    
        ##remove unneeded files
        rm "${output_path}"/tissue_segmentation/"${tumor_marker_lowercase}"_${ck}/tissue_segmentation.RData
    
    done
fi

##############################
#Generate results table (image coordinate system)
##############################

mkdir -p "${output_path}"/cell_segmentation/
2>&1 "${script_path}"/generate_table.R --thresholds="${channel_thresholding}" --coordinates=image --nprocesses=${nprocesses} --output="${output_path}"/cells_properties_pixels.txt "${output_path}"/cell_segmentation/merge_cells.RData "${output_path}"/tissue_segmentation/latest/tissue_segmentation.RData | tee "${output_path}"/cell_segmentation/generate_table.log


