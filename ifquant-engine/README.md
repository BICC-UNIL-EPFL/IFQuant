# IFQuant

## Dependencies

* [Bio-formats command line tools](https://www.openmicroscopy.org/bio-formats/downloads/) (v6.6.0).
  `bfconvert` and `showinf` must be accessible from the PATH.

* [libvips](https://libvips.github.io/libvips/) (v8.9.1). 
  `vips` and `vipsheader` must be accessible from the PATH.

* [libtiff-tools](http://www.simplesystems.org/libtiff/tools.html) (v4.1.0).
  `tiffinfo` must be accessible from the PATH.

* [pandoc](http://pandoc.org/) (v2.5)

* [R](https://www.R-project.org) (v4.0.4) with the following packages:

  * [data.table](https://CRAN.R-project.org/package=data.table) (v1.14.0).
  * [ggplot2](https://ggplot2.tidyverse.org) (v3.3.3).
  * [R.utils](https://CRAN.R-project.org/package=R.utils) (v2.10.1).
  * [gridExtra](https://CRAN.R-project.org/package=gridExtra) (v2.3).
  * [NMF](https://CRAN.R-project.org/package=NMF) (v0.23.0).
  * [viridis](https://CRAN.R-project.org/package=viridis) (v0.5.1).
  * [gplots](https://CRAN.R-project.org/package=gplots) (v3.1.1).
  * [KernSmooth](https://CRAN.R-project.org/package=KernSmooth) (v2.23-18).
  * [RColorBrewer](https://CRAN.R-project.org/package=RColorBrewer) (v1.1-2).
  * [writexl](https://CRAN.R-project.org/package=writexl) (v1.3.1).
  * [geometry](https://CRAN.R-project.org/package=geometry) (v0.4.5).
  * [igraph](https://CRAN.R-project.org/package=igraph) (v1.2.6).
  * [RANN](https://CRAN.R-project.org/package=RANN) (v2.6.1).
  * [rmarkdown](https://CRAN.R-project.org/package=rmarkdown) (v2.7).
  * [sp](https://CRAN.R-project.org/package=sp) (v1.4-5).
  * [polyclip](https://CRAN.R-project.org/package=polyclip) (v1.10-0).
  * [RTriangle](https://CRAN.R-project.org/package=RTriangle) (v1.6-0.10).
  * [EBImage](http://bioconductor.org/packages/EBImage) (4.32.0).
  * [optparse](https://CRAN.R-project.org/package=optparse) (v1.7.1).

* [bash](https://www.gnu.org/software/bash) (v5.0.17).

These scripts were tested on Linux (ubuntu 20.04) using software versions specified above (parenthesis). 


## Usage

### Estimate unmixing parameters

This should be done only once on a single stained library to estimate the unmixing parameters.

Prepare a file with information on the single stained library. This file should be tab delimited with header in first row, one row per input file and 6 columns:

* `file`: filename (only basename). Correspondance between input files and column `file` will be done by matching base file name (without path)
* `fluorophore`: single fluorophore used when acquiring the image (or AUTOFLUO). Should be `DAPI`, `AUTOFLUO` and for other channels it should correspond to the channel name (`Name #<channel>`) in the metadata of the qptiff image (e.g. `Opal 570`, `Opal 690`, ...).
* `x` (optional): upper left corner x coordinate (pixels) of the selected region (NA will be replaced by 0).
* `y` (optional): upper left corner y coordinate (pixels) of the selected region (NA will be replaced by 0).
* `width` (optional): width (pixels) of the selected region (NA will be replaced by available width).
* `height` (optional): height (pixels) of the selected region (NA will be replaced by available height).

Example:

```
file                                   fluorophore  x    y    width  height
MM_OX7V.0Q_Library_AUTOFLUO_1.qptiff   AUTOFLUO     NA   NA   NA     NA
MM_OX7V.0Q_Library_CD20-O480_1.qptiff  OPAL 480     NA   NA   NA     NA
MM_OX7V.0Q_Library_CD20-O520_1.qptiff  OPAL 520     0    215  1650   NA
MM_OX7V.0Q_Library_CD20-O570_1.qptiff  OPAL 570     NA   NA   NA     NA
MM_OX7V.0Q_Library_CD20-O620_1.qptiff  OPAL 620     415  0    NA     1000
MM_OX7V.0Q_Library_CD20-O690_2.qptiff  OPAL 690     270  NA   NA     NA
MM_OX7V.0Q_Library_CD20-O780_1.qptiff  OPAL 780     NA   NA   NA     NA
MM_OX7V.0Q_Library_DAPI_1.qptiff       DAPI         NA   NA   NA     NA
```


To generate unmixing parameters from single stained library:

```
scripts/get_unmixing_parameters.R --debug-plots --metadata=FILENAME --output=FILENAME input1.qptiff input2.qptiff ...
```

Example:

```
scripts/get_unmixing_parameters.R --debug-plots
   --metadata=library.txt \
   --output=unmixing_parameters.csv \
   Single_stained/MM_OX7V.0Q_Library_AUTOFLUO_1.qptiff \
   Single_stained/MM_OX7V.0Q_Library_CD20-O480_1.qptiff \
   Single_stained/MM_OX7V.0Q_Library_CD20-O520_1.qptiff \
   Single_stained/MM_OX7V.0Q_Library_CD20-O570_1.qptiff \
   Single_stained/MM_OX7V.0Q_Library_CD20-O620_1.qptiff \
   Single_stained/MM_OX7V.0Q_Library_CD20-O690_2.qptiff \
   Single_stained/MM_OX7V.0Q_Library_CD20-O780_1.qptiff \
   Single_stained/MM_OX7V.0Q_Library_DAPI_1.qptiff
```

This script will create three files

* `unmixing_parameters.csv`: unmixing parameters (use with `--unmixing-parameters`)
* `unmixing_parameters_values_distribution.csv`: distribution of fluorescence around marker-positive cells measured in the stained channel. Used to normalized composite image (use `--channel-normalization`).
* `unmixing_parameters.pdf`: diagnostic plots. Two pages for each single stained input image (page title), one page with raw images (one image per channel) and one page with unmixed images. Note that images are resized by a factor 1/4 in x and y directions to reduce file size.

Note:
* Selected regions should not be too large (e.g. below 2000x2000 pixels).
* Check that the resulting unmixed images are properly unmixed (in `unmixing_parameters.pdf`). The signal should be mainly in the corresponding single stained channel and in the autofluorescence channel. If not, it can be worth rerunning the script (the algorithm is stochastic, therefore each run can give slightly different results), possibly after changing the selected regions (make sure to select clean regions with a clear positive signal in the stained channel).



### Image analysis

The workflow consists in two steps: a preprocessing step (`scripts/run_segmentation.sh`) where most of the heavy computations are done and a faster analysis step (`scripts/run_analysis.sh`) that generates the final output given user defined parameters such as thresholds, regions of interests and excluded regions. Typically, the preprocessing step is run only once, while the analysis step can be run multiple times to adjust parameters.

A brief usage summary can be obtained with `--help`

```
scripts/run_segmentation.sh --help
scripts/run_analysis.sh --help
```

Example of typical workflow:

1. Run segmentation (slow):
   
   ```
   scripts/run_segmentation.sh --nprocesses=12 \
      --unmixing-parameters=examples/unmixing_parameters.csv \
      --metadata-panel=examples/panel.tsv \
      --channel-thresholding=examples/channel_thresholding.tsv \
      --channel-normalization=examples/unmixing_parameters_values_distribution.csv \
      --phenotypes=examples/phenotypes.tsv \
      --output="analysis/" \
      --image=image_01.qptiff
   ```

   Note: if the image contains N samples, use `--sample-selection=n:N` to select sample n (with n=1,2,3,..,N from top to bottom). E.g. `--sample-selection=1:2` to select first sample (top) or  `--sample-selection=2:2` to select second sample (bottom). Alternatively, use `--sample-selection-range=start:end` to select a specific region from start to end along the y axis, with start and end in fraction of image height (from 0=top to 1=bottom). E.g. `--sample-selection-range=0.1:0.4` to select region from 10% to 40% of image height. The output file `sample_selection/sample_selection.pdf` shows the selected region (red) on top of a low resolution version of the input image (first channel, before unmixing).
   
2. Run first analysis:
   
   ```
   scripts/run_analysis.sh --path="analysis/image_01/" \
      --excluded-regions=examples/excluded_regions.csv \
      --ROI=examples/ROI.csv
   ```
   
3. Adjust channel thresholding (`--channel-thresholding`), regions of interest (`--ROI`) or excluded regions (`--excluded-regions`) and rerun analysis:
   
   ```
   scripts/run_analysis.sh --path="analysis/image_01/" \
      --excluded-regions=examples/excluded_regions.csv \
      --ROI=examples/ROI.csv \
      --channel-thresholding=examples/channel_thresholding.tsv
   ```

   WARNING: automatic determined <tumor_marker> (e.g. CK) threshold will be replaced by the <tumor_marker> threshold specified in `--channel-thresholding`. Make sure to use the automatic <tumor_marker> threshold saved in `analysis/image_01/data/analysis/metadata_channel_thresholding.txt`.

4. Several files are created during the run, mainly to be used by the web application, and can be ignored. Final results can be found in `analysis/image_01/report/`.

#### Input files

Description of the files used as input for `run_segmentation.sh` and `run_analysis.sh`:

* Image (`--image`): image in PerkinElmer Vectra/QPTIFF format.

* Unmixing parameters (`--unmixing-parameters`): file with unmixing parameter generated by `get_unmixing_parameters.R` (`unmixing_parameters.csv`).

* Channel normalization (`--channel-normalization`): file with distribution of fluorescence around marker-positive cells measured in single-stained images, generated by `get_unmixing_parameters.R` (`unmixing_parameters_values_distribution.csv`). Used for channel normalization when plotting images. 

* Panel metadata (`--metadata-panel`): file with panel metadata. Tab delimited with header in first row, one row per channel and the following columns:

  * `channel`: channel index (0,1,2,...,7). Should correspond the channel index in the image (using 0 based indexing)
  
  * `name`: marker name (e.g. DAPI, CD15, CK, CD3, autofluorescence).
  
  * `filter`: filter used for the corresponding channel (e.g. DAPI, Opal 570, Sample AF). Should correspond to the filter name in the image metadata (using `showinf`).
  
  * `color`: channel color for image visualization. Should be comma separated `R,G,B` (e.g. 255,204,229).
  
  * `type`: marker type. Valid marker types are (comma separated if more than one type):
  
    * `nucleus`: nucleus staining. Used for nucleus segmentation. Exactly one channel should have type `nucleus`.
    * `nucleus2`: additional channel to use for nucleus segmentation. Several channels can have type `nucleus2`. Note: it is strongly discouraged to use an additional channel for nucleus segmentation.
    * `tumor`: tumor staining. Used for tissue segmentation. At most one channel should have type `tumor`. Although it is optional, it is strongly advised to use a panel with a tumor marker.
    * `AF`: autofluorescence. Exactly one channel should have type `AF`.
    * `NA`: all other channels.

  Example:
  
  ```
  channel name             filter          color        type
  0       DAPI             DAPI            0,0,255      nucleus
  1       CD15             OPAL 570        255,255,0    NA
  2       SOX10            OPAL 690        255,204,229  tumor,nucleus2
  3       CD3              OPAL 480        255,0,0      NA
  4       CD11c            OPAL 620        255,128,0    NA
  5       CD20             OPAL 780        255,255,255  NA
  6       CD163            OPAL 520        0,255,0      NA
  7       autofluorescence AUTOFLUO        0,0,0        AF
  ```

* Channel thresholding (`--channel-thresholding`): file with channel thresholding information. Tab delimited with header in first row, one row per channel (except DAPI and autofluorescence) and the following columns:

  * `channel`: channel index (0,1,2,...,7). Should correspond the channel index in the image (using 0 based indexing)
  
  * `name`: marker name (e.g. CD15, CK, CD3, CD11c, CD20, CD163). Should correspond to column `name` in the panel metadata (`--metadata-panel`)
  
  * `score.type`: should have the form `<summary_statistic>.<region>` with

    `<summary_statistic>`=`mean`, `median`, `q001`, `q005`, `q025`, `q075`, `q095`, `q099`, `circular.q005`, `circular.q010`, `circular.q025` or `circular.q050`, with `q<n>`=n-th percentile and `circular.q<n>`=n-th percentile of max in all directions.

    `<region>`=`nucleus`, `extended.nucleus` or `around.nucleus`.

    E.g. `mean.nucleus`, `median.extended.nucleus`, `q001.nucleus`, `q095.around.nucleus`, `circular.q010.around.nucleus`

  * `threshold`: numeric threshold. A cell is "positive" for a channel if its score (evaluated using `score.type`) is above threshold.

  * `automatic.thresholding.method`: method(s) to use when searching for thresholds. This column is optional and is only used when running `run_segmentation.sh`. Should contain:

    * `none`: do not try to estimate threshold automatically, use threshold specified in column `threshold`.
    * `bimodal`: if the distribution of asinh transformed score is bimodal, use threshold separating both modes.
    * `outliers`: assume rare population of positive cells and use threshold given by Q3+2*(Q3-Q1), with Qn the n-th quartile for the distribution of asinh transformed scores. 
    * `bimodal,outliers`: try with `bimodal` and if it fails, use `outliers`.

    If column `automatic.thresholding.method` is not specified, use `bimodal` for <tumor_marker> and `none` for all other channels.

    Note that except for markers with a clearly bimodal distribution, the automatic thresholding method implemented in IFQuant is not very reliable. The resulting thresholds should be manually validated and adjusted if needed.
    
  This file should contain one row per channel except DAPI and autofluorescence, which will be ignored.

  Example:
  
  ```
  channel name    score.type                     threshold  automatic.thresholding.method
  1       CD15    median.extended.nucleus        6          none
  2       CK      median.extended.nucleus        5          bimodal
  3       CD3     median.nucleus                 10         bimodal,outliers
  4       CD11c   circular.q050.extended.nucleus 5          bimodal,outliers
  5       CD20    q075.nucleus                   5          outliers
  6       CD163   circular.q050.around.nucleus   10         none
  ```

* Phenotypes (`--phenotypes`): file with phenotypes definition. Tab delimited with header in the first row, one row per phenotype and the following columns:

  * `label`: phenotype label (e.g. CD15-CD163-CD11c-CD20-CD3-, macrophage,...)  
  * `channel_1`: state of channel_1 (channel with index 1 in panel metadata `--metadata-panel` file). Can be `-` (channel must be negative), `+` (channel must be positive) or `*` (channel is ignored).
  * `channel_2`: same as `channel_1` but for channel with index 2.
  * `channel_3`: same as `channel_1` but for channel with index 3.
  * `channel_4`: same as `channel_1` but for channel with index 4.
  * `channel_5`: same as `channel_1` but for channel with index 5.
  * `channel_6`: same as `channel_1` but for channel with index 6.

  Note: channels with nucleus staining (type `nucleus` in metadata panel) and autofluorescence (type `AF` in metadata panel) will be ignored.
  
  Example:

  ```
  label                   channel_1  channel_2  channel_3  channel_4  channel_5 channel_6
  Stromal cells           -          -          -          -          -         -
  Epithelial cells        -          +          -          -          -         -
  T-lymphocytes           -          *          -          -          -         +
  B cells                 -          *          -          -          +         -
  Neutrophils             +          -          -          -          -         -
  Macrophages             -          *          +          -          -         -
  Dendritic               -          *          -          +          -         -
  Activated T-cells (CD4) +          *          -          -          -         +
  Myeloid                 -          *          +          +          -         -
  ```

* Sample information (`--sample-information`): file with informations on the sample. Tab separated file WITHOUT header in the first row and two columns (property name and value). This file will be used as is in the first page of the report.

* Excluded regions (`--excluded-regions`): file with excluded regions. Comma separated with header in the first row, one row per point and 3 columns:

  * `id`: region id. 
  * `x`: x coordinate (in image coordinate system, i.e. pixels, with origin at the upper left corner)
  * `y`: y coordinate (in image coordinate system, i.e. pixels, with origin at the upper left corner)

  This file can contain multiple regions, each with a different id. Regions are assumed to be closed (polygons), i.e. last point will be connected to first point.

* Regions of interest (`--ROI`): file with regions of interest. Comma separated with header in the first row, one row per point, 3 mandatory columns and 1 optional column:

  * `id`: region id. 
  * `x`: x coordinate (in image coordinate system, i.e. pixels, with origin at the upper left corner)
  * `y`: y coordinate (in image coordinate system, i.e. pixels, with origin at the upper left corner)
  * `label`: region label (optional).

  This file can contain multiple regions (each with a different `label`), composed of one of more connected regions (each with a different `id`). Connected regions are assumed to be closed (polygons), i.e. last point will be connected to first point.

#### Output files

Several files are created during the run. Most files can be ignored as they are only created to temporarily store preprocessing results or to be used by the web application.
The main results are (paths are relative to the analysis folder):

* `report/report.pdf`: a report summarizing the main results.
* `report/summary_all.xlsx`: summary tables for the full image (see `report.pdf`).
* `report/summary_ROI_*.xlsx`: summary tables for cells in a specific ROI.
* `report/cells_properties.tsv.gz`: gzipped tab delimited file with header in the first row, one row per segmented cell and several columns described in the file `report/README.txt`.



## Credits

* Julien Dorier, BioInformatics Competence Center, University of Lausanne, Switzerland.

