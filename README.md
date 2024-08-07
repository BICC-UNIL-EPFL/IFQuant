# IFQuant App
This application is a demonstrator standalone version of IFQuant for multiplex-immunofluorescence image analysis. This version can process `.qptiff` images generated by the Vectra Polaris imaging system.

It is composed of several parts:

- `ifquant-engine`: the IFQuant engine built using R, bcftools and vips.
- `ifquant-api`: the backend (PHP) of the web application. It contains the Apache web server.
- `ifquant-vuejs`: the frontend (VueJS) of the web application
- `ifquant-iipsrv`: the IIP image server [https://iipimage.sourceforge.io](https://iipimage.sourceforge.io/)

## Getting started:

Make sure you have `git`, `docker` and `docker compose` available on your system

```bash
docker compose up -d
```

The IFQuant application is available under: [http://localhost:8088](http://localhost:8088)

## Loading a sample

- Create on directory for the sample in the `data/samples` directory.
  ```sh
  mkdir data/samples/example
  ```

- Copy (or move) your image file, preferencially in *.qptiff* format in this directory. The name of the file (without its extension) will be used as sample name in the web application.

  *`ome.tiff` image format is currently not supported unless the following qptiff properties are available in the 'OME-XML' field of the file. The `tiffcomment` tool from the [bftools](https://docs.openmicroscopy.org/bio-formats/5.9.1/users/comlinetools/index.html) might be useful.*

  ```
  ResolutionUnit
  XResolution
  YResolution
  XPosition
  YPosition
  ImageWidth
  ImageLength
  ExposureTime
  Name
  ```

  **Please ensure that the directory `data/` and all children directories have write access for the apache2 (www) user**

- Create five files:

  - **panel.tsv:**

    Tab delimited with header in first row, one row per channel and the following columns:
    
      * `channel`: channel index (0,1,2,...,7). Should correspond the channel index in the image (using 0 based indexing)
    
      * `name`: marker name (e.g. DAPI, CD15, CK, CD3, autofluorescence).
    
      * `filter`: filter used for the corresponding channel (e.g. DAPI, Opal 570, Sample AF). Should correspond to the filter name in the image metadata (using `showinf`).
    
      * `color`: channel color for image visualization. Should be comma separated `R,G,B` (e.g. 255,204,229).
    
      * `type`: marker type. Valid marker types are (comma separated if more than one type):
    
        * `nucleus`: nucleus staining. Used for nucleus segmentation. Exactly one channel should have type `nucleus`.
        * `tumor`: tumor staining. Used for tissue segmentation. Exactly one channel should have type `tumor`.
        * `AF`: autofluorescence. Exactly one channel should have type `AF`.
        * `NA`: all other channels.
    
      Example:
    
      ```
      channel name             filter          color        type
      0       DAPI             DAPI            0,0,255      nucleus
      1       CD15             OPAL 570        255,255,0    NA
      2       SOX10            OPAL 690        255,204,229  tumor
      3       CD3              OPAL 480        255,0,0      NA
      4       CD11c            OPAL 620        255,128,0    NA
      5       CD20             OPAL 780        255,255,255  NA
      6       CD163            OPAL 520        0,255,0      NA
      7       autofluorescence AUTOFLUO        0,0,0        AF
      ```

  - **channel_thresholding.tsv:**

    File with channel thresholding information. Tab delimited with header in first row, one row per channel (except DAPI and autofluorescence) and the following columns:
    
      * `channel`: channel index (0,1,2,...,7). Should correspond the channel index in the image (using 0 based indexing)
    
      * `name`: marker name (e.g. CD15, CK, CD3, CD11c, CD20, CD163). Should correspond to column `name` in the panel metadata (`--metadata-panel`)
    
      * `score.type`: should have the form `<summary_statistic>.<region>` with
    
        `<summary_statistic>`=`mean`, `median`, `q001`, `q005`, `q025`, `q075`, `q095`, `q099`, `circular.q005`, `circular.q010`, `circular.q025` or `circular.q050`, with `q<n>`=n-th percentile and `circular.q<n>`=n-th percentile of max in all directions.
    
        `<region>`=`nucleus`, `extended.nucleus` (cell region) or `around.nucleus` (cytoplasm region, i.e. cell region without nucleus).
    
        E.g. `mean.nucleus`, `median.extended.nucleus`, `q001.nucleus`, `q095.around.nucleus`, `circular.q010.around.nucleus`.
    
        In case of doubt, use the default `mean.nucleus` for a marker located in the nucleus, `mean.around.nucleus` for a marker located in the cytoplasm and `mean.extended.nucleus` for a marker located in the nucleus or in the cytoplasm.
    
      * `threshold`: numeric threshold. A cell is "positive" for a channel if its score (evaluated using `score.type`) is above threshold.
    
      * `automatic.thresholding.method`: method(s) to use when searching for thresholds. This column is optional and is only used when running `run_segmentation.sh`. Should contain:
    
        * `none`: do not try to estimate threshold automatically, use threshold specified in column `threshold`.
        * `bimodal`: if the distribution of asinh transformed score is bimodal, use threshold separating both modes.
        * `outliers`: assume rare population of positive cells and use threshold given by Q3+2*(Q3-Q1), with Qn the n-th quartile for the distribution of asinh transformed scores.
        * `bimodal,outliers`: try with `bimodal` and if it fails, use `outliers`.
    
        If column `automatic.thresholding.method` is not specified, use `bimodal` for <tumor_marker> and `none` for all other channels.
    
        Note that except for markers with a clearly bimodal distribution, the automatic thresholding method implemented in IFQuant if not very reliable. The resulting thresholds should be manually validated and adjusted if needed.
        
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

  - **phenotypes.tsv:**
  
    Describes the combination of markers to assign a given phenotype to a cell. Tab delimited with header in the first row, one row per phenotype and the following columns:
    
      * `label`: phenotype label (e.g. CD15-CD163-CD11c-CD20-CD3-, macrophage,...)
      * `channel_1`: state of channel_1 (channel with index 1 in `panel.tsv` file). Can be `-` (channel must be negative), `+` (channel must be positive) or `*` (channel is ignored).
      * `channel_2`: same as `channel_1` but for channel with index 2.
      * `channel_3`: same as `channel_1` but for channel with index 3.
      * `channel_4`: same as `channel_1` but for channel with index 4.
      * `channel_5`: same as `channel_1` but for channel with index 5.
      * `channel_6`: same as `channel_1` but for channel with index 6.
    
      Note: channels with nucleus staining (type `nucleus` in `panel.tsv`) and autofluorescence (type `AF` in `panel.tsv`) will be ignored.
    
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

  - **unmixing_parameters.csv:**

    Please read the **Estimate unmixing parameters** section of the README file in the `ifquant-engine` directory to create this file

  - **unmixing\_parameters\_values_distribution.csv:**

    Please read the **Estimate unmixing parameters** section of the README file in the `ifquant-engine` directory to create this file

## Test run

You can download a test sample:

```bash
cd data/samples
wget https://bix.unil.ch/ifquant/example.tar.gz
tar -zxvf example.tar.gz
```

Open [http://localhost:8088](http://localhost:8088) in a web browser or reload the web page. 

You should see an entry under: **List of Qptiff images to process**.

Copy the provided command and run it in the same location as the `docker-compose.yml` file (or provide the location of the `docker-compose.yml` as the value of the `-f` parameter).

## Documentation

A user manual is available from the web application or from this [link](ifquant-vuejs/src/assets/user_manual/IFQuant_User_Manual.md). A [PDF version](ifquant-vuejs/src/assets/user_manual/IFQuant_User_Manual.pdf) is also available.

## Credits

The following persons contributed to the development of this tool: 

- **Engine:** Julien Dorier, BioInformatics Competence Center, University of Lausanne, Switzerland.
- **Web application:** Robin Liechti, Vital-IT, SIB Swiss Institute of Bioinformatics, Lausanne, Switzerland and BioInformatics Competence Center, University of Lausanne, Switzerland.
- **Initial idea, biological expertise, feedback, validation:** Stéphanie Tissot, Center of Experimental Therapeutics, Immune Landscape Laboratory, Ludwig Cancer Center of the University of Lausanne - CHUV, Lausanne, Switzerland.

All the members of the Immune Landscape Laboratory provided valuable feedback and bug tracking.