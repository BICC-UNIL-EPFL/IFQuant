<template>
	<div class="ifquantHelp container" id="ifquantHelp">
		<h1 id="toc_0">IFQuant User Manual</h1>

		<p>There are two main directories in the <code>data</code> folder:</p>

		<ul>
		<li><strong>samples</strong>: input data. Create one folder per sample. In each folder, put the image, preferentially in <code>.qptiff</code> format as well as the <code>panel.tsv</code>, <code>panel_thresholding.tsv</code>, <code>phenotypes.tsv</code>, <code>unmixing_parameters.csv</code> and <code>unmixing_parameters_values_distribution.csv</code> files. A README file describes their formats.</li>
		<li><strong>analyses</strong>: analyzed data. (Will) contain one folder by analyzed sample. The name of each folder is identical to the corresponding directory in the <code>samples</code> folder.</li>
		</ul>

		<h2 id="toc_1">Initial image processing</h2>

		<p>If a sample exists in the <code>samples</code> directory but is absent from the  <code>analyses</code> directory, the home page (<a href="http://localhost:8088">http://localhost:8088</a>) of IFQuant will display the shell command to run (Figure 1)</p>

		<p><img src="../assets/user_manual/figure1.jpg" alt="Figure 1">
		<em>Figure 1</em></p>

		<p>To process the image, open a terminal window and move to the directory containing the <code>docker-compose.yml</code> file and copy / paste the provided command.</p>

		<p><strong>Note:</strong></p>

		<ul>
		<li>The <code>--nprocesses</code> parameter can be adapted depending on the number of available CPUs. Be aware that the process will also consume more memory.</li>
		<li>The <code>--tmpdir=&lt;TEMPORARY_DIR&gt;</code> parameter can be specified. By default, the process is creating a <code>tmp/</code> directory in the analysis directory. If enough memory is available, <code>/dev/shm</code> is an option to speed up the process.</li>
		</ul>

		<p>Processing will take several minutes.</p>

		<h2 id="toc_2">Quality controls and excluded regions</h2>

		<p>Once the process is finished, refresh the home page (<a href="http://localhost:8088">http://localhost:8088</a>). The sample will be listed in the <code>List of samples</code> (Figure 2)</p>

		<p><img src="../assets/user_manual/figure2.jpg" alt="Figure 2">
		<em>Figure 2</em></p>

		<p>Click on it to open it in IFQuant (Figure 3).</p>

		<p><img src="../assets/user_manual/figure3.jpg" alt="Figure 3">
		<em>Figure 3</em></p>

		<p>Three QC masks are available. Tissue segmentation / sharpness / saturation. By default the <em>tissue segmentation</em> mask is displayed (stroma colored in green and tumor in red). A slider enables changing the opacity of the mask, and thus display the underlying cells. To change QC mask, click on the <code>hitde tissue segmentation</code> button. </p>

		<p>The image might contain some background noise of regions of bad quality. These regions can be excluded by first ensuring that the red <code>exclusion tool</code> button is selected and then by drawing excluded regions on the slide (Figure 4).</p>

		<p><img src="../assets/user_manual/figure4.jpg" alt="Figure 4">
		<em>Figure 4</em></p>

		<p>Once all regions have been drawn, click on the <code>save and compute statistics</code> button. A modal window will display a shell command to paste into the terminal window (Figure 5). Ensure that you are always located in the directory containing the <code>docker-compose.yml</code> file.</p>

		<p><img src="../assets/user_manual/figure5.jpg" alt="Figure 5">
		<em>Figure 5</em></p>

		<p><strong>Note:</strong></p>

		<ul>
		<li>The <code>--nprocesses</code> parameter can be adapted depending on the number of available CPUs. Be aware that the process will also consume more memory.</li>
		<li>The <code>--tmpdir=&lt;TEMPORARY_DIR&gt;</code> parameter can be specified. By default, the process is creating a <code>tmp/</code> directory in the analysis directory. If enough memory is available, <code>/dev/shm</code> is an option to speed up the process.</li>
		</ul>

		<h2 id="toc_3">Sample analysis</h2>

		<p>Once the sample is ready for analysis, the following interface will be displayed (Figure 6)</p>

		<ul>
		<li><strong>A</strong>: List of markers. Click on one to adjust its threshold (except for the tumor marker, see below)</li>
		<li><strong>B</strong>: List of channels. By default, all channels are displayed in the composite image (F). To hide one of multiple channels, click on its name. To adjust the intensity of a channel, use its slider. Revert to its <em>standard</em> value (1) by clicking on the badge at the right of the slider.</li>
		<li><strong>C</strong>: Show / hide the QC masks.</li>
		<li><strong>D</strong>: Draw excluded regions or regions of interest (ROI). Once ROIs are defined, specific statistics for the ROIs will be computed in the final report.</li>
		<li><strong>E</strong>: Report section. When a report is available, it can be downloaded from this section.</li>
		<li><strong>F</strong>: Dynamic composite image. The image can be zoomed and paned.</li>
		</ul>

		<p><img src="../assets/user_manual/figure6.jpg" alt="Figure 6">
		<em>Figure 6</em></p>

		<h3 id="toc_4">Marker intensity thresholding</h3>

		<p>IFQuant uses the notion of marker intensity thresholding to define a cell as being positive or negative for a given marker. IFQuant provides a user interface to adjust these thresholds. </p>

		<h4 id="toc_5">Tumor marker intensity thresholding</h4>

		<p>The distribution of the tumor marker signals across all cells often follows a bimodal distribution. In this case, IFQuant can suggest a usually pretty coherent threshold value. In the case where IFQuant is not confident enough to assign the default threshold, the <code>show tissue segmentation</code> button will be highlighted in red and a <code>check tissue segmentation</code> badge will be displayed. This is the case for our test sample. To adjust the tumor marker threshold, click on the <code>check tissue segmentation</code> and then on the <code>adjust segmentation</code> button. A series of tissue masks corresponding to different tumor marker thresholding values will be displayed on the right side of the screen. By clicking on the <code>graph</code> button next to the <em>Adjust Segmentation</em> title, the distribution of the tumor marker intensity signal will be displayed. In our example, we can notice that the default threshold is too low. By clicking the value 25, we can correct this value. We can play with the tissue opacity slider on the left side of the screen to verify the pertinence of the mask regarding the cells expressing the tumor marker (Figure 7). Once we are done, we can close the <em>adjust segmentation</em> interface and hide the tumor mask (Figure 6.C).</p>

		<p><img src="../assets/user_manual/figure7.jpg" alt="Figure 7">
		<em>Figure 7</em></p>

		<h4 id="toc_6">Other marker intensity thresholding</h4>

		<p>To adjust the intensity threshold of a given marker, first select it (Figure 6.A). By default, only the DAPI and the selected marker are displayed in the image. You can add additional cell types by selecting them (Figure 6.B). By clicking on the <code>show cells</code> button, the center of each positive cells will be spotted with a red circle (Figure 8).</p>

		<p><img src="../assets/user_manual/figure8.jpg" alt="Figure 8">
		<em>Figure 8</em></p>

		<p>Note that for performance reasons, if too many cells are positive,  only a fraction of those will be highlighted. If less the 1000 cells are visible on the image, negative cells will be spotted with a small gray circle. By clicking on the circle, the marker intensity value will be displayed (Figure 9).</p>

		<p><img src="../assets/user_manual/figure9.jpg" alt="Figure 9">
		<em>Figure 9</em></p>

		<p>IFQuant also provides a <em>FACS-like</em> interface to explore the distribution of the signal intensity of a given compared to the other markers. To display the series of scatter plots, click on the blue <code>plot</code> button at the right of the thresholding slider (Figure 10). The actual threshold is displayed as a vertical dashed line. The threshold can be adjusted in the interface by moving the green line (following the cursor) to the correct value and clicking on the mouse).</p>

		<p><img src="../assets/user_manual/figure10.jpg" alt="Figure 10">
		<em>Figure 10</em></p>

		<h3 id="toc_7">ROI creation</h3>

		<p>If the tissue contains several regions of interest (Tumor tissue, Next to tumor tissue, TLS, Host tissue, Adipose tissue or Necrosis) that should be quantified independently, the user can <em>draw</em> these regions on the image (Figure 11). First select the <strong>ROI</strong> green button, then draw freely the region with the mouse and finally, select the type of ROI from the select menu.</p>

		<p><img src="../assets/user_manual/figure11.jpg" alt="Figure 11">
		<em>Figure 11</em></p>

		<h3 id="toc_8">Create report</h3>

		<p>Once all thresholds have been reviewed and adjusted and ROI have been created (optional), a summary statistics can be computed and a PDF report generated. To do so, click on the <code>create report</code> button. Once again, a shell command will be displayed (Figure 12). Copy and paste it in a terminal window. Ensure that you are always located in the directory containing the <code>docker-compose.yml</code> file.</p>

		<p><img src="../assets/user_manual/figure12.jpg" alt="Figure 12">
		<em>Figure 12</em></p>

		<p><strong>Note:</strong></p>

		<ul>
		<li>The <code>--nprocesses</code> parameter can be adapted depending on the number of available CPUs. Be aware that the process will also consume more memory.</li>
		<li>The <code>--tmpdir=&lt;TEMPORARY_DIR&gt;</code> parameter can be specified. By default, the process is creating a <code>tmp/</code> directory in the analysis directory. If enough memory is available, <code>/dev/shm</code> is an option to speed up the process.</li>
		</ul>

		<p>Once the report is ready, it can be downloaded from the <code>Report</code> section at the bottom of the left panel (Figure 13). There are at least 3 files at the end of the analysis: </p>

		<p><img src="../assets/user_manual/figure13.jpg" alt="Figure 13">
		<em>Figure 13</em></p>

		<ul>
		<li><strong><code>sample_name</code>.pdf</strong>: A full PDF report containing quality control plots and summary statistics</li>
		<li><strong><code>sample_name</code>.xlsx</strong>: An Excel document containing several spreadsheets with summary statistics. If ROIs have been defined, a version of this file is available for each ROI.</li>
		<li><strong><code>sample_name</code>.tsv.gz`</strong>: A compressed tab-delimited text file containing the processed data. Each row is a cell and columns contain cell coordinates, the tissue type of the cell (stroma/tumor), if a cell is part of an ROI, the signal intensity of each marker, the signal intensity of each marker devided by its thresholds (useful to derive marker positivity) and a phenotype key. </li>
		</ul>

		<p><strong>Note on the PDF report:</strong>
		<em>Several figures of the full sample are available in the PDF report. They are created at the scale 1:32 (one pixel in the report = 32 in the original image). It appears that this ratio is well suited to fit a whole sample in the report and to represent cell densities. For this reason, if an original image is &quot;small&quot; (like the provided example image), some figures in the report might show a &#39;pixelated&#39; aspect.</em></p>

		<p>At this stage, the sample is on &#39;read-only&#39; mode. No more threshold modifications of ROI adjustments are possible. To modify the analysis, first delete the existing report by clicking on the <code>delete report...</code> button.</p>
	</div>
</template>

<script>

export default {
	name: "ifquantHelp",
}
</script>

<style>
#ifquantHelp img {
	position:relative;
	display: block;
	width: 100%;
	padding: 10px;
	border: 2px solid #999;
	border-radius: 5px;
}

#ifquantHelp  {
  font-family: Helvetica, arial, sans-serif;
  font-size: 14px;
  line-height: 1.6;
  padding-top: 10px;
  padding-bottom: 10px;
  padding: 30px; }

#ifquantHelp  > *:first-child {
  margin-top: 0 !important; }
#ifquantHelp  > *:last-child {
  margin-bottom: 0 !important; }

#ifquantHelp a {
  color: #4183C4; }
#ifquantHelp a.absent {
  color: #cc0000; }
#ifquantHelp a.anchor {
  display: block;
  padding-left: 30px;
  margin-left: -30px;
  cursor: pointer;
  position: absolute;
  top: 0;
  left: 0;
  bottom: 0; }

#ifquantHelp h1, h2, h3, h4, h5, h6 {
  margin: 20px 0 10px;
  padding: 0;
  font-weight: bold;
  -webkit-font-smoothing: antialiased;
  cursor: text;
  position: relative; }

#ifquantHelp h1:hover a.anchor, h2:hover a.anchor, h3:hover a.anchor, h4:hover a.anchor, h5:hover a.anchor, h6:hover a.anchor {
  background: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAA09pVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuMy1jMDExIDY2LjE0NTY2MSwgMjAxMi8wMi8wNi0xNDo1NjoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIENTNiAoMTMuMCAyMDEyMDMwNS5tLjQxNSAyMDEyLzAzLzA1OjIxOjAwOjAwKSAgKE1hY2ludG9zaCkiIHhtcE1NOkluc3RhbmNlSUQ9InhtcC5paWQ6OUM2NjlDQjI4ODBGMTFFMTg1ODlEODNERDJBRjUwQTQiIHhtcE1NOkRvY3VtZW50SUQ9InhtcC5kaWQ6OUM2NjlDQjM4ODBGMTFFMTg1ODlEODNERDJBRjUwQTQiPiA8eG1wTU06RGVyaXZlZEZyb20gc3RSZWY6aW5zdGFuY2VJRD0ieG1wLmlpZDo5QzY2OUNCMDg4MEYxMUUxODU4OUQ4M0REMkFGNTBBNCIgc3RSZWY6ZG9jdW1lbnRJRD0ieG1wLmRpZDo5QzY2OUNCMTg4MEYxMUUxODU4OUQ4M0REMkFGNTBBNCIvPiA8L3JkZjpEZXNjcmlwdGlvbj4gPC9yZGY6UkRGPiA8L3g6eG1wbWV0YT4gPD94cGFja2V0IGVuZD0iciI/PsQhXeAAAABfSURBVHjaYvz//z8DJYCRUgMYQAbAMBQIAvEqkBQWXI6sHqwHiwG70TTBxGaiWwjCTGgOUgJiF1J8wMRAIUA34B4Q76HUBelAfJYSA0CuMIEaRP8wGIkGMA54bgQIMACAmkXJi0hKJQAAAABJRU5ErkJggg==) no-repeat 10px center;
  text-decoration: none; }

#ifquantHelp h1 tt, h1 code {
  font-size: inherit; }

#ifquantHelp h2 tt, h2 code {
  font-size: inherit; }

#ifquantHelp h3 tt, h3 code {
  font-size: inherit; }

#ifquantHelp h4 tt, h4 code {
  font-size: inherit; }

#ifquantHelp h5 tt, h5 code {
  font-size: inherit; }

#ifquantHelp h6 tt, h6 code {
  font-size: inherit; }

#ifquantHelp h1 {
  font-size: 28px;
  color: white; }

#ifquantHelp h2 {
  font-size: 24px;
  border-bottom: 1px solid #cccccc;
  color: white; }

#ifquantHelp h3 {
  font-size: 18px; }

#ifquantHelp h4 {
  font-size: 16px; }

#ifquantHelp h5 {
  font-size: 14px; }

#ifquantHelp h6 {
  color: #777777;
  font-size: 14px; }

#ifquantHelp p, blockquote, ul, ol, dl, li, table, pre {
  margin: 15px 0; }

#ifquantHelp hr {
  background: transparent url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAYAAAAECAYAAACtBE5DAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAyJpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuMC1jMDYwIDYxLjEzNDc3NywgMjAxMC8wMi8xMi0xNzozMjowMCAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIENTNSBNYWNpbnRvc2giIHhtcE1NOkluc3RhbmNlSUQ9InhtcC5paWQ6OENDRjNBN0E2NTZBMTFFMEI3QjRBODM4NzJDMjlGNDgiIHhtcE1NOkRvY3VtZW50SUQ9InhtcC5kaWQ6OENDRjNBN0I2NTZBMTFFMEI3QjRBODM4NzJDMjlGNDgiPiA8eG1wTU06RGVyaXZlZEZyb20gc3RSZWY6aW5zdGFuY2VJRD0ieG1wLmlpZDo4Q0NGM0E3ODY1NkExMUUwQjdCNEE4Mzg3MkMyOUY0OCIgc3RSZWY6ZG9jdW1lbnRJRD0ieG1wLmRpZDo4Q0NGM0E3OTY1NkExMUUwQjdCNEE4Mzg3MkMyOUY0OCIvPiA8L3JkZjpEZXNjcmlwdGlvbj4gPC9yZGY6UkRGPiA8L3g6eG1wbWV0YT4gPD94cGFja2V0IGVuZD0iciI/PqqezsUAAAAfSURBVHjaYmRABcYwBiM2QSA4y4hNEKYDQxAEAAIMAHNGAzhkPOlYAAAAAElFTkSuQmCC) repeat-x 0 0;
  border: 0 none;
  color: #cccccc;
  height: 4px;
  padding: 0;
}

#ifquantHelp h2:first-child {
  margin-top: 0;
  padding-top: 0; }
#ifquantHelp h1:first-child {
  margin-top: 0;
  padding-top: 0; }
  body > h1:first-child + h2 {
    margin-top: 0;
    padding-top: 0; }
#ifquantHelp  h3:first-child, body > h4:first-child, body > h5:first-child, body > h6:first-child {
  margin-top: 0;
  padding-top: 0; }

#ifquantHelp a:first-child h1, a:first-child h2, a:first-child h3, a:first-child h4, a:first-child h5, a:first-child h6 {
  margin-top: 0;
  padding-top: 0; }

#ifquantHelp h1 p, h2 p, h3 p, h4 p, h5 p, h6 p {
  margin-top: 0; }

#ifquantHelp li p.first {
  display: inline-block; }
#ifquantHelp li {
  margin: 0; }
#ifquantHelp ul, ol {
  padding-left: 30px; }

#ifquantHelp ul :first-child, ol :first-child {
  margin-top: 0; }

#ifquantHelp dl {
  padding: 0; }
  #ifquantHelp dl dt {
    font-size: 14px;
    font-weight: bold;
    font-style: italic;
    padding: 0;
    margin: 15px 0 5px; }
    #ifquantHelp dl dt:first-child {
      padding: 0; }
    #ifquantHelp dl dt > :first-child {
      margin-top: 0; }
    #ifquantHelp dl dt > :last-child {
      margin-bottom: 0; }
  #ifquantHelp dl dd {
    margin: 0 0 15px;
    padding: 0 15px; }
    #ifquantHelp dl dd > :first-child {
      margin-top: 0; }
    #ifquantHelp dl dd > :last-child {
      margin-bottom: 0; }

#ifquantHelp blockquote {
  border-left: 4px solid #dddddd;
  padding: 0 15px;
  color: #777777; }
  #ifquantHelp blockquote > :first-child {
    margin-top: 0; }
  #ifquantHelp blockquote > :last-child {
    margin-bottom: 0; }

#ifquantHelp table {
  padding: 0;border-collapse: collapse; }
  #ifquantHelp table tr {
    border-top: 1px solid #cccccc;
    background-color: black;
    margin: 0;
    padding: 0; }
    #ifquantHelp table tr:nth-child(2n) {
      background-color: #393939; }
    #ifquantHelp table tr th {
      font-weight: bold;
      border: 1px solid #cccccc;
      margin: 0;
      padding: 6px 13px; }
    #ifquantHelp table tr td {
      border: 1px solid #cccccc;
      margin: 0;
      padding: 6px 13px; }
    #ifquantHelp table tr th :first-child, table tr td :first-child {
      margin-top: 0; }
    #ifquantHelp table tr th :last-child, table tr td :last-child {
      margin-bottom: 0; }

#ifquantHelp img {
  max-width: 100%; }

#ifquantHelp span.frame {
  display: block;
  overflow: hidden; }
  #ifquantHelp span.frame > span {
    border: 1px solid #dddddd;
    display: block;
    float: left;
    overflow: hidden;
    margin: 13px 0 0;
    padding: 7px;
    width: auto; }
  #ifquantHelp span.frame span img {
    display: block;
    float: left; }
  #ifquantHelp span.frame span span {
    clear: both;
    color: #333333;
    display: block;
    padding: 5px 0 0; }
  #ifquantHelp span.align-center {
  display: block;
  overflow: hidden;
  clear: both; }
#ifquantHelp span.align-center > span {
    display: block;
    overflow: hidden;
    margin: 13px auto 0;
    text-align: center; }
#ifquantHelp  span.align-center span img {
    margin: 0 auto;
    text-align: center; }
#ifquantHelp span.align-right {
  display: block;
  overflow: hidden;
  clear: both; }
#ifquantHelp  span.align-right > span {
    display: block;
    overflow: hidden;
    margin: 13px 0 0;
    text-align: right; }
#ifquantHelp span.align-right span img {
    margin: 0;
    text-align: right; }
#ifquantHelp span.float-left {
  display: block;
  margin-right: 13px;
  overflow: hidden;
  float: left; }
  span.float-left span {
    margin: 13px 0 0; }
#ifquantHelp span.float-right {
  display: block;
  margin-left: 13px;
  overflow: hidden;
  float: right; }
  span.float-right > span {
    display: block;
    overflow: hidden;
    margin: 13px auto 0;
    text-align: right; }

#ifquantHelp code, tt {
  margin: 0 2px;
  padding: 0 5px;
  white-space: nowrap;
  border: 1px solid #171717;
  background-color: #393939;
  border-radius: 3px; }

#ifquantHelp pre code {
  margin: 0;
  padding: 0;
  white-space: pre;
  border: none;
  background: transparent; }

#ifquantHelp .highlight pre {
  background-color: #393939;
  border: 1px solid #cccccc;
  font-size: 13px;
  line-height: 19px;
  overflow: auto;
  padding: 6px 10px;
  border-radius: 3px; }

#ifquantHelp pre {
  background-color: #393939;
  border: 1px solid #cccccc;
  font-size: 13px;
  line-height: 19px;
  overflow: auto;
  padding: 6px 10px;
  border-radius: 3px; }
  pre code, pre tt {
    background-color: transparent;
    border: none; }

#ifquantHelp sup {
    font-size: 0.83em;
    vertical-align: super;
    line-height: 0;
}

#ifquantHelp kbd {
  display: inline-block;
  padding: 3px 5px;
  font-size: 11px;
  line-height: 10px;
  color: #555;
  vertical-align: middle;
  background-color: #fcfcfc;
  border: solid 1px #ccc;
  border-bottom-color: #bbb;
  border-radius: 3px;
  box-shadow: inset 0 -1px 0 #bbb
}



</style>