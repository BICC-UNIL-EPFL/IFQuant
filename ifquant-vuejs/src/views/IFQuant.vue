<template>
	<div class = 'ifquant container-fluid' id="IFQuantContainer" style = 'position:relative; margin: 0 !important; padding-top: 40px; padding-bottom: 120px;' @click="checkAnnotationStatus" v-on:keyup.delete="removePath">
		<div id="ROIannotation" ref="ROIannotation"  class="p-3">
			<div class="input-group mb-3">
				<select class="form-control form-control-sm" v-model="ROItitle" v-if="!showOtherROItitle">
					<option :value="null">-- select --</option>
					<option v-for="title in cvROItitles" :key="title" :value="title">{{title}}</option>
					<option value="other...">other...</option>
				</select>
				<input type="text" class="form-control form-control-sm" placeholder="Name" aria-label="ROItitle" v-model="ROItitle" aria-describedby="button-roi-title" v-if="showOtherROItitle">
				<div class="input-group-append">
					<button class="btn btn-primary btn-sm" type="button" id="button-roi-title" @click="saveAnnotations(true)" :disabled="!ROItitle">Save</button>
				</div>
			</div>
		</div>
		
		
		<div id="ifquantTooltip"></div>
		<div style = 'position:absolute; left: 10px; top: 10px; width: 500px;z-index: 10'><router-link to="/"><button class="btn btn-outline-light btn-sm">back to the list of samples</button></router-link></div>
		<div class = 'row' style="margin-top: 200px">
			<!-- <div :class="tissueThresholdAdjust?'col-10':'col-12'"> -->
				<!-- PARAMETERS -->
				<div id="leftPanelLoading" v-if="!sampleIds.sample_id">
					<h1 class = 'mt-3 h4'>
						{{sample}}
					</h1>
					<h5 class="text-center text-muted"><i>loading...</i></h5>
				</div>
				<div id="leftPanel" :style="`visibility: ${sampleIds.sample_id?'visible':'hidden'}`">
					<h1 class = 'mt-3 h4'>
						{{sample}}						
					</h1>
					<template v-if="processingStep==='processing'">
						<h5 class="text-warning" >Processing in progress...</h5>
					</template>
					
					<template v-else>
						<div class = 'card' style="margin-top: 20px; background-color: #000; color: #FFF; border-color: #999" >
							<div class = 'card-body'>
								<div class="btn-group d-flex justify-content-between" role="group" aria-label="cell types" v-if="!isExclusion">
									<button
									type="button"
									v-for ="ct in cellTypes"
									:key="ct"
									class="btn btn-sm"
									:class="(ct===cellType)?'btn-primary active':'btn-outline-primary'"
									:style="getCellTypeStyle(ct)"
									@click="toggleCellType(ct)"
									>
										{{ct}}
									</button>
								</div>

								<div :style="`border: 1px solid rgb(${(cellType)?colorMaps[cellType].color:'0,0,0'}); position: relative;`" class="p-3" v-if="!isExclusion">
									<div  v-if="cellType" style="font-size: 0.8rem">
										<div class='row'>
											<div class='h5' :class="`${showCells?'col-8 text-right':'col-12 text-center'}`" :style="`color: rgb(${colorMaps[cellType].color}`">{{(showCells)?`Visible ${cellType} cells`:cellType}}</div>
											<template v-if="showCells">
												<div class='h5 col-4' v-if="!loading" :style="`color: rgb(${colorMaps[cellType].color}`">{{total}}</div>
												<div class='h5 col-4 text-muted' v-if="loading"><small><i>...</i></small></div>
											</template>
											<span class="badge badge-dark"  style='position: absolute; top: 2px; left: 2px' >{{colorMaps[cellType].marker}}</span>
										</div>
										<p class="w-100  text-center" :style="`visibility:${(factor>1 && cells.length)?'visible':'hidden'}`"><span class = 'text-faded'>({{cells.length}} displayed)</span></p>
										<div class = 'row' v-if="cellType!=='DAPI'">
											<div class="col-4 text-right pl-1 pr-0"><label class="w-100" for="threshold">{{cellType}} Threshold</label></div>
											<div class="col-4">
												<b-form-input id="threshold" v-model="thresholds[cellType].value" type="range" min="0" max="40" step="0.1" @change="updateThreshold" v-if="canEdit && cellType!==tumorChannel"></b-form-input>
												<p v-else class="text-center">{{Math.round(thresholds[cellType].value*10)/10}}</p>
											</div>
											<div class="col-4 px-0">
												<button type="button" class="btn btn-sm py-0 px-1 m-0" :class="(showDensity)?'btn-info':'btn-outline-info'" style = 'line-height: 0.9rem; font-size: 0.75rem' v-b-tooltip.hover :title="thresholds[cellType].method" @click="toggleDensity" v-if="hasDensities"><v-icon name="chart-area" scale="0.6" /> {{Math.round(threshold*100)/100}}</button>
												<span class="badge badge-info" v-else>{{Math.round(threshold*100)/100}}</span>
												<button type="button" class="btn btn-sm btn-link py-0 px-1 my-0" v-if="originalThresholds[cellType].value!==thresholds[cellType].value && canEdit" @click="resetThreshold"><v-icon name="undo-alt" scale="0.7"/></button>
											</div>
										</div>
										<p class="text-center"  v-if="canEdit && cellType!==tumorChannel">	
											<button type = 'button' class="btn btn-sm btn-success" :class="originalThresholds[cellType].value===thresholds[cellType].value?'btn-outline-success':'btn-success'" :disabled="originalThresholds[cellType].value===thresholds[cellType].value" style = 'line-height: 0.9rem; font-size: 0.75rem' @click="saveThreshold(cellType)" ><v-icon name='save' scale="0.9" /><span class="ml-2">save threshold</span></button>
										</p>
									</div>
								</div>
							
								<div v-if="cellType && hasCellsDb && !tissueDisplayed && !tlsDisplayed && !isExclusion" style="border: 1px solid #FFF" :style="`visibility:${showCells?'visible':'hidden'}`" class="p-2" >
									<p>Highlight cells <button type="button" class="btn btn-sm btn-link p-0 ml-2 my-0" @click="showHighlightCells=!showHighlightCells"><v-icon :name="showHighlightCells?'chevron-down':'chevron-right'" /></button></p>
									<div class="d-flex justify-content-between" role="group" aria-label="cell types" v-if="showHighlightCells">
										<div v-for="ct in cellTypes" :key="`highlight${ct}`">
											<p class="text-center mb-0 px-1 py-0" :style="`background-color: rgb(${ct===cellType?colorMaps[ct].color:'0,0,0'});color: ${(ct===cellType)?getTextColor(colorMaps[ct].color):'rgb('+colorMaps[ct].color+')'}`">{{ct}}</p>
											<div class="progress my-1 mx-2" style="height: 6px; background-color: #333;" v-if="!loadingNotifications" v-b-tooltip.hover :title="`${notifications[ct].count} (${notifications[ct].percent}%)`">
												<div class="progress-bar" role="progressbar" :style="`width: ${notifications[ct].percent}%; background-color:rgb(${colorMaps[ct].color})`" :aria-valuenow="notifications[ct].percent" aria-valuemin="0" aria-valuemax="100"></div>
											</div>
											<div class="btn-group-vertical w-100 px-2">
												<button type="button" class="btn btn-sm px-1 py-0 " :class="highlightCells[ct]===true?'btn-success':'btn-outline-success'" @click="setHighlightCells(ct,true)" :disabled="ct===cellType">pos</button>
												<button type="button" class="btn btn-sm px-1 py-0" :class="highlightCells[ct]===false?'btn-danger':'btn-outline-danger'" @click="setHighlightCells(ct,false)" v-if="ct!==cellType">neg</button>
											</div>
										</div>
									</div>
								</div>
														
								<div class = 'row mt-2' v-if="!cellType && !isExclusion">
									<p class="text-center w-100"><strong>Select a cell type to highlight it and display its channel</strong></p>
								</div>
								<div class="d-flex justify-content-between mt-3" v-if="!isExclusion">
									<h5 v-if="cellType" class="w-100">
										<span class = 'badge mt-2' :class="(factor===1)?'badge-success':(factor > 3)?'badge-danger':'badge-warning'" v-if="showCells && !loading">{{`${(factor===1)?"all":"1/"+factor} cells displayed`}}</span>
										<button type="button" class="btn btn-outline-info btn-sm py-1 float-right" @click="toggleCells"  :disabled="(loading)" ><v-icon :name="showCells?'eye-slash':'eye'" scale="1" v-if="!loading"></v-icon>&nbsp;{{loading?'loading':(showCells?'hide':'show')}} cells<span v-if="loading">...</span> </button>
									</h5>
								</div>
							</div>
							<div class="p-3 mt-0 mb-3 mx-3" style="border: 1px solid white;">
								<template v-for="(channel,channelIdx) in channels">
									<div class="row"  :key="`channel${channelIdx}`">
										<div class="col-4">
											<div class="form-check">
												<label class="form-check-label pointer"  :style="getChannelStyle(channel)" @click="toggleChannelVisibility(channelIdx)">
													{{channel.marker}}
												</label>
											</div>

										</div>
										<div class="col-5">
											<b-form-input :id="`${channelIdx}_intensity`" v-model="channel.intensity" type="range" min="0" max="5" step="0.1"></b-form-input>
										</div>
										<div class="col-3" ><span class="badge badge-info pointer" v-b-tooltip.hover title="reset" @click="channel.intensity=1">{{channel.intensity}}</span></div>
									</div>
								</template>
								<p class="text-center mb-0 pb-0"><small><em>SHIFT-click to toggle ALL channels at once</em></small></p>
							</div>
						</div>

						<div class = 'card' style="margin-top: 20px; background-color: #000; color: #FFF; border-color: #999" >
							<div class = 'card-body'>
								<a style = 'position: absolute; top: 5px; right: 2px' class="btn btn-link float-right" @click="toggleTissueMask" v-if="!loading &&  (tissueDisplayed || tlsDisplayed)"><v-icon :name="showTissueMask?'eye-slash':'eye'" scale="1"></v-icon></a>
								<h6 v-if="!isExclusion">Percent tumor tissue: <strong>{{percentTumor}}%</strong> <span class="text-warning ml-2" v-if="warningPercentTumor" v-b-tooltip.hover title="Does NOT consider excluded regions"><v-icon name = "exclamation-triangle" /></span> <span class="float-right badge badge-danger" v-if="warningThreshold" v-b-modal.ckModal>check segmentation</span></h6>
								<div class = 'p-3'  v-if="tissueDisplayed || sharpnessDisplayed || saturationDisplayed || tlsDisplayed">
									<div class='row' >
										<div class="col-5 text-right"><label class="px-1" :style="`background-color:${tlsDisplayed?'rgb(204,0,204)':''}`">{{(tissueDisplayed)?"Tissue":(sharpnessDisplayed)?"Sharpness":(saturationDisplayed?"Saturation":"TLS")}} opacity</label></div>
										<div class="col-4"><b-form-input id="opacity" v-model="opacity" type="range" min="0" max="1" step="0.1"></b-form-input></div>
										<div class="col-3"><span class="badge badge-info">{{opacity*100}}%</span></div>
									</div>
									<p class="p-2 text-center" v-if="saturationDisplayed"><small><span class="px-2 py-1" style="background-color: #0F0; border: 1px solid #0C0; color: #000;">ok</span> <span class="ml-1 px-2 py-1" style="background-color: #F00; border: 1px solid #C00; color: #000;">saturating</span> <br/> <span class="text-warning" >unmixing might be problematic in saturating regions</span></small></p>
									<p class="p-2 text-center" style="line-height: 2em;" v-if="sharpnessDisplayed"><small><span class="px-2 py-1" style="background-color: #FFF; color: #000;">empty</span> <span class="px-2 py-1" style="background-color: #CCC; color: #000;">low dapi</span> <span class="px-2 py-1" style="background-color: #F00; color: #000;">DAPI out of focus</span> <br/> <span class="px-2 py-1" style="background-color: #FF0; color: #000;">DAPI focus warning</span> <span class="px-2 py-1" style="background-color: #0F0; color: #000;">DAPI focus OK</span></small></p>
								</div>
								<div class = "btn-group d-flex">
									<button type="button" class="btn btn-sm flex-fill" :class="(saturationDisplayed?'btn-light':'btn-outline-light')" @click="toggleOverlay('saturation')" v-if="QCs.indexOf('saturation') > -1 && !tissueDisplayed && !sharpnessDisplayed && !tlsDisplayed">{{`${saturationDisplayed?"hide":"show"} saturation`}}</button>
									<button type="button" class="btn btn-sm flex-fill" :class="(sharpnessDisplayed?'btn-light':'btn-outline-light')" @click="toggleOverlay('sharpness')" v-if="QCs.indexOf('sharpness') > -1 && !tissueDisplayed && !saturationDisplayed && !tlsDisplayed">{{`${sharpnessDisplayed?"hide":"show"} sharpness`}}</button>
									<button type="button" class="btn btn-sm flex-fill" :class="(tlsDisplayed?'btn-light':'btn-outline-light')" @click="toggleOverlay('tls')" v-if="QCs.indexOf('tls') > -1 && !tissueDisplayed && !saturationDisplayed && !sharpnessDisplayed">{{`${tlsDisplayed?"hide":"show"} TLS`}}<span class="badge ml-2" :class="TLS.total>0?'badge-info':'badge-danger'" v-if="TLS.total>-1">{{TLS.total}}</span></button>
									<button type="button" class="btn btn-sm flex-fill" :class="(warningThreshold)? (tissueDisplayed?'btn-danger':'btn-outline-danger'):(tissueDisplayed?'btn-light':'btn-outline-light')" @click="toggleOverlay('tissue')"  v-if="!saturationDisplayed && !sharpnessDisplayed && !tlsDisplayed">{{`${tissueDisplayed?"hide":"show"} tissue segmentation`}}</button>
									<button class = 'btn btn-sm btn-outline-light flex-fill' @click="tissueThresholdAdjust=!tissueThresholdAdjust" v-if="canEdit && tissueSegmentations.length && tissueDisplayed && (!cellType || cellType===tumorChannel)">{{tissueThresholdAdjust?"close":"adjust"}} segmentation</button>
								</div>

							</div>
						</div>

						<!-- // Annotation -->
						<div id = 'annots' class = "card mt-3" style="margin-top: 20px; background-color: #000; color: #FFF; border-color: #999">
							<div class="card-body">
								<div class="card-title">
									ROIs
									<div class="float-right" v-if="cellTypes.indexOf('CD20') > -1 && !confirmResetAnnotation && !isExclusion && +TLS.total !== -1">
										<label class="mr-2"><strong>has TLS: </strong></label>
										<span  class="h5" :class="TLS.total > 0?'text-success':'text-danger'">{{+TLS.total?'YES':'NO'}}</span>
										
									</div>
								</div>

								<div class="card text-danger bg-primary" v-if="confirmResetAnnotation" style="margin-top: 20px; background-color: #000; color: #FFF; border-color: #999">
									<div class="card-body">
										<div class="card-title"><strong>This action will reset all ROIs and exclusions</strong></div>
										<p class="text-center">
											<button type="button" class="btn btn-sm btn-danger mr-1" @click="resetAnnotations">confirm</button>
											<button type="button" class="btn btn-sm btn-outline-light ml-1" @click="confirmResetAnnotation=false">cancel</button>
										</p>
									</div>
								</div>
								<template v-else>
									<h5 class="text-warning" v-if="isExclusion && openSeadragonReady && !fabricOverlay.fabricCanvas().getObjects().length">Please first select regions to exclude</h5>
									<div class="btn-group"  v-if="canEdit || isExclusion">
										<button type="button" class="btn" :class="annotateMode&&!shiftKey?'btn-light':'btn-outline-dark'" @click="toggleAnnotate"><v-icon name="mouse-pointer" /></button>
										<button type="button" class="btn" :class="(drawMode==='exclusion'&&!shiftKey)?'btn-danger':'btn-outline-danger'" @click="toggleDraw('exclusion')" :disabled="!openSeadragonReady"  v-b-tooltip.hover title="EXCLUSION (CTRL+x)"><v-icon name="draw-polygon" /></button>
										<button type="button" class="btn" :class="(drawMode==='roi'&&!shiftKey)?'btn-success':'btn-outline-success'" @click="toggleDraw('roi')" :disabled="!openSeadragonReady"  v-b-tooltip.hover title="ROI (CTRL+r)"><v-icon name="draw-polygon" /></button>
									</div>
									<button type="button" class="btn btn-danger ml-2" v-if="isAnnotationSelected && canEdit" @click="removePath"><v-icon name="trash-alt" /></button>
									<span class="float-right badge badge-info" v-if="!openSeadragonReady">loading...</span>
									<button type="button" class="btn btn-light float-right"  v-if="openSeadragonReady && isExclusion" @click="saveAnnotations('SUBMIT')" :disabled="reportInPreparation">{{`${(reportInPreparation)?"preparing...":"save and compute statistics"}`}}</button>
									<button type="button" class="btn btn-sm btn-outline-danger float-right" @click="resetAnnotations" v-if="processingStep !== 'annotation' && openSeadragonReady && !isExclusion && canEdit">reset...</button>
								</template>
							</div>
							<table class="table table-sm table-hover" id="ROItable" v-if="ROIs.length && !confirmResetAnnotation">
								<thead>
									<tr>
										<th class="text-center">ID</th>
										<th>Type</th>
										<th v-if="canEdit"></th>
									</tr>
								</thead>
								<tbody>
									<tr v-for="ROI in ROIs" :key="ROI.id" @mouseenter="highlightROI(ROI.id,true)" @mouseleave="highlightROI(ROI.id,false)" @click="selectROI(ROI.id)">
										<td class="text-center">{{ROI.id}}</td>
										<td>
											<template v-if="ROI.id !== activeROIidx">{{ROI.title}}</template>
											<template v-else>
												<select class="form-control form-control-sm" v-model="ROItitle">
													<option :value="null">-- select --</option>
													<option v-for="title in cvROItitles" :key="title" :value="title">{{title}}</option>
												</select>
											</template>
										</td>
										<td class="text-center" v-if="canEdit">
											<template v-if="ROI.id !== activeROIidx">
												<button type="button" class="btn btn-sm btn-link text-info" @click="editROI(ROI.id)"><v-icon name="pencil-alt" /></button>
											</template>
											<template v-else>
												<button type="button" class="btn btn-sm btn-link text-success" @click="saveAnnotations(true)"><v-icon name="save" /></button>
												<button type="button" class="btn btn-sm btn-link" @click="cancelROI()">cancel</button>
											</template>
										</td>
									</tr>
								</tbody>
							</table>
							
						</div>


						<!-- STATS -->
						<div id = 'stats' v-if="(stats.ifquant.DAPI)  && !isExclusion && showCells" class = "card mt-3" style="margin-top: 20px; background-color: #000; color: #FFF; border-color: #999">
							<div class = 'card-body'>
								<template v-if="quantType.indexOf('Q')>-1">
									<div class="card-title">{{quantType.indexOf('I')>-1?'IFQuant':'View'}} counts
										<template v-if="!loadingStats">
											<span class='float-right'>{{Number(stats.ifquant.DAPI).toLocaleString()}}</span>
										</template>
									</div>									
									<table class="table table-sm text-right" v-if="stats.ifquant.DAPI">
										<thead>
											<th v-for="ct in cellTypes" :key="`thIFQuant${ct}`" :style="getTableStyle(ct)">{{ct}}</th>
										</thead>
										<tbody v-if="loadingStats">
											<tr>
												<td rowspan="2" :colspan="cellTypes.length" class="text-center text-muted">fetching counts...</td>
											</tr>
										</tbody>
										<tbody v-else>
											<tr>
												<td v-for="ct in cellTypes" :key="`tdIFQuantCounts${ct}`" :style="getTableStyle(ct)">{{stats.ifquant[ct]}}</td>
											</tr>
											<tr>
												<td v-for="ct in cellTypes" :key="`tdIFQuantPct${ct}`" :style="getTableStyle(ct)" >{{Math.round(stats.ifquant[ct]/stats.ifquant.DAPI*1000)/10}}%</td>
											</tr>
										</tbody>
									</table>
								</template>
							</div>
						</div>

						<!-- NOTIFICATIONS -->

						<div id = 'notifications' v-if="!loadingNotifications && cellType  && !isExclusion" class = "card mt-3" style="margin-top: 20px; background-color: #222; color: #EEE;" :style="`border: 1px solid rgb(${(cellType)?colorMaps[cellType].color:'0,0,0'}); position: relative;`">
							<div class = 'card-body'>
									<div class="card-title" :style="`font-weight: bold; color: rgb(${(cellType)?colorMaps[cellType].color:'0,0,0'});`">{{cellType}} positive cells<span class='float-right'>{{Number(notifications[cellType].count)}}</span></div>
									<table class="table table-sm text-right">
										<thead>
											<th v-for="ct in otherCellTypes" :key="`thIFQuantNotifs${ct}`" :style="getTableStyle(ct)">{{ct}}</th>
										</thead>
										<tbody>
											<tr>
												<td v-for="ct in otherCellTypes" :key="`tdIFQuantNotifs${ct}`" :style="getTableStyle(ct)">{{notifications[ct].count}}</td>
											</tr>
											<tr>
												<td v-for="ct in otherCellTypes" :key="`tdIFQuantNotifPcts${ct}`" :style="getTableStyle(ct)" >{{notifications[ct].percent}}%</td>
											</tr>
										</tbody>
									</table>
							</div>
						</div>


						<!-- REPORT -->
						<div id = 'reports' class = "card mt-3" style="margin-top: 20px; background-color: #000; color: #FFF; border-color: #999" v-if="sampleIds.panel  && !isExclusion">
							<div class = 'card-body'>
								<div class="card-title">Report <small class="float-right" v-if="sampleIds.reporter">{{`${sampleIds.reporter} `}} <template  v-if="sampleIds.report_date">{{sampleIds.report_date}}</template></small></div>
								<template v-if="!downloadingReport">
									<div class="card-text" v-if="!reportInPreparation">
										<p v-if="sampleIds.pdf_report"><a  @click="download(sampleIds.pdf_report,sample+'.pdf')" v-if="sampleIds.pdf_report" class="pointer"><span class=" text-danger mr-2"><v-icon name="file-pdf" /></span> {{sample}}.pdf</a></p>
										<p v-if="sampleIds.pdf_report_neotil"><a  @click="download(sampleIds.pdf_report_neotil,sample+'_immune_classification.pdf')" v-if="sampleIds.pdf_report_neotil" class="pointer"><span class=" text-warning mr-2"><v-icon name="file-pdf" /></span> {{sample}}_immune_classification.pdf</a></p>
										<p v-if="sampleIds.xlsx_data"><a  @click="download(sampleIds.xlsx_data,sample+'.xlsx')" v-if="sampleIds.xlsx_data" class="pointer"><span class=" text-success mr-2"><v-icon name="file-excel" /></span> {{sample}}.xlsx</a></p>
										<p v-for="(xlsx_roi,roiIdx) in sampleIds.xlsx_rois" :key="xlsx_roi.file"><a  @click="download(xlsx_roi.file,`${sample}_${(xlsx_roi.name.indexOf('&')>-1)?'all_ROIs':(isNaN(+xlsx_roi.name)?xlsx_roi.name:'ROI'+(roiIdx+1))}.xlsx`)" v-if="sampleIds.xlsx_data" class="pointer"><span class=" text-success mr-2"><v-icon name="file-excel" /></span> {{`${sample}_${(xlsx_roi.name.indexOf('&')>-1)?"all_ROIs":(isNaN(+xlsx_roi.name)?xlsx_roi.name:"ROI"+(roiIdx+1))}.xlsx`}}</a></p>
										<p v-if="sampleIds.cells_properties_data"><a  @click="download(sampleIds.cells_properties_data,sample+'.tsv.gz')" v-if="sampleIds.cells_properties_data" class="pointer"><span class=" text-info mr-2"><v-icon name="file-archive" /></span> {{sample}}.tsv.gz</a></p>
										<div class="text-center">
											<span v-if="confirmReport" class="text-warning mr-2">Really delete this report?</span>
											<p class="text-warning text-center" v-if="!sampleIds.pdf_report && ROIwithoutLabel">Please assign a type to all ROIs ({{ROIwithoutLabel}} missing)</p>
											<button type="button" class="btn btn-sm btn-outline-info" @click="createReport" v-if="!sampleIds.pdf_report" :disabled="reportInPreparation || ROIwithoutLabel>0">{{(reportInPreparation)?"preparing...":"create report"}}</button>
											<button type="button" class="btn btn-sm" :class="confirmReport?'btn-danger':'btn-outline-danger'" v-if="sampleIds.pdf_report  " @click="deleteReport" :disabled="reportDeletionInProgress">{{confirmReport?(reportDeletionInProgress?"request submitted...":"confirm"):"delete report..."}}</button>
											<button type="button" class="btn btn-sm btn-outline-light ml-2" v-if="confirmReport" @click="confirmReport=false;">cancel</button>
										</div>
									</div>
									<div class="card-text" v-else>
										<p class="text-info text-center">We are preparing your report.</p>
									</div>
								</template>
								<template v-else>
									<p class="text-faded text-center">downloading report...</p>
								</template>
							</div>
						</div>
					</template>

				</div>
				<!-- IMAGE -->
				<div id = "imagePanel" >
					<div style = 'position:absolute; right: 10px; bottom: -15px; width: 300px;z-index: 10;text-align: right; align: right;color: rgb(90,101,120)'><small>powered by: <a href='https://iipimage.sourceforge.io/' target='_blank'><img src="../assets/iip-badge.png" width="80" height="15" alt="Iip Badge"></a></small></div>
					<div id="densityContainer" v-if="showDensity" :style="`border-color:rgb(${(cellType)?colorMaps[cellType].color:'0,0,0'}); min-width: 1200px; overflow: auto;`">
						<channel-densities :sample="sample" :cellType="cellType" :canEdit="canEdit" :thresholds="thresholds" @set-threshold="updateThreshold($event)" @close-density="showDensity=false" :tumorChannel="tumorChannel"></channel-densities>
					</div>
					<div id = 'coordinates' >
						<div id = "navigator" ></div>
						<div id = 'topleft'>{{Math.round(coordinates.x)}}:{{Math.round(coordinates.y)}}</div>
						<div id = 'bottomright'>{{Math.round(coordinates.x+coordinates.width)}}:{{Math.round(coordinates.y+coordinates.height)}}</div>
						<span class="badge badge-info" style="position: absolute; top: 5px; right: 5px;" v-if="!openSeadragonReady">loading...</span>
					</div>
					<div id = 'cells'>
						<svg height="9" width="9" v-for="(cell,cellIdx) in cells" :key="cellIdx" :id="`cell${cellIdx}`" style="z-index:99999;">
							<circle cx="5" cy="5" :r="getRadius(cell[cellType])" :fill="showCells?getColor(cell[cellType]):'transparent'" :stroke="getStrokeColor(cell[cellType])" :stroke-width='`${showCells?1:0}`' />
						</svg>
					</div>
					<div id = 'openseadragon'></div>
				</div>
			</div>

				<!-- TISSUE THRESHOLD -->
			<div v-if="tissueThresholdAdjust && !tissueSegmentationsLoaded" id="divTissueThresholdLoading">
				<h1 class="h5 text-muted">Loading...</h1>
				<b-progress :value="nbTissueSegmentationsImgs" :max="tissueSegmentations.length" animated></b-progress>
			</div>
			<div id="divTissueThreshold" :style="`display:${(tissueThresholdAdjust && tissueSegmentationsLoaded)?'block':'none'}`">
				<h1 class="h5">Adjust segmentation
					<b-button v-b-modal.tumorModal variant="outline-light" size="sm" v-b-tooltip.hover :title="`Show ${tumorChannel} intensity distribution`"><v-icon name='chart-area'></v-icon></b-button>
					<button type="button" class="close float-right" aria-label="Close" @click="tissueThresholdAdjust=false">
						<span aria-hidden="true">&times;</span>
					</button>
				</h1>
				<div class="list-group" style="height:100%; overflow: auto;">
					<a class="list-group-item list-group-item-action" :class='tissueThreshold===tisSeg.cutoff?"":"active"' v-for="tisSeg in tissueSegmentations" :key="tisSeg.cutoff" @click="displayOverlay('tissue',tisSeg.cutoff)" :id="`${tissueThreshold===tisSeg.cutoff?'default'+tumorChannel:''}`">
						<div class="d-flex w-100 justify-content-between" >
							<h5 class="mb-1 w-100" :style='`color: ${tissueThreshold===tisSeg.cutoff?"#000":"#FFF"}`'>
								{{Math.round(tisSeg.cutoff.replace(tissueRegExp,"")*100)/100}}
								<span class="badge badge-info mx-1" v-if="defaultCutoff(tumorChannel,tisSeg.cutoff.replace(tissueRegExp,''))">INITIAL</span>
								<span class="badge badge-info mx-1" v-if="originalCutoff(tumorChannel,tisSeg.cutoff.replace(tissueRegExp,''))">AUTOMATIC</span>
								<span class="float-right">
									<b-button v-b-modal.tumorModal variant="outline-light" size="sm" v-b-tooltip.hover :title="`Show ${tumorChannel} intensity distribution`" v-if="originalCutoff(tumorChannel,tisSeg.cutoff.replace(tissueRegExp,'')) || defaultCutoff(tumorChannel,tisSeg.cutoff.replace(tissueRegExp,''))"><v-icon name='chart-area'></v-icon></b-button>
								</span>
							</h5>
						</div>
						<img :src = 'tisSeg.img'>
					</a>
				</div>
			</div>

			<b-modal ref="tumorModal" id='tumorModal' :title="`${tumorChannel} intensities distribution`" :hide-footer="true" :hide-header="true" size="xl">
			<div v-if="qcPDF">
				<img :src='qcPDF' class="img-fluid">
			</div>
		</b-modal>
		<b-modal ref="ifquantCmdModal" id="ifquantCmdModal" :title="cmdTitle" :hide-footer="true" title-class="text-dark" size="xl">
			<div class = 'container'>
				<div class="p-2 border pt-4" style="position: relative">
					<button type="button" class="btn btn-outline-secondary btn-sm" style="position: absolute; top: 4px; right: 4px" v-clipboard="() => ifquantCmd" v-clipboard:success="clipboardSuccessHandler" v-b-tooltip.hover title="Copy Docker CMD"><v-icon name="clipboard" scale="0.9" /></button>
					<pre>{{ifquantCmd}}</pre>
					<ul class="bg-secondary text-light p-1 pl-4">
						<li>The <code>nprocesses</code> parameter can be adapted depending on the number of available CPUs. Be aware that the process will also consume more memory.</li>
						<li>The <code>--tmpdir=&lt;TEMPORARY_DIR&gt;</code> parameter can be specified (the default is <code>&lt;ANALYSIS_DIR&gt;/tmp</code>). If enough memory is available, <code>/dev/shm</code> is an option to speed up the process.</li>
					</ul>
					<p class="bg-info p-2">Reload the page once the process is finished.</p>
				</div>
				
			</div>
		</b-modal>
	</div>
</template>

<script>
import Vue from 'vue'
import OpenSeadragon from 'openseadragon'
import '@/assets/openseadragon-filtering.js'
import '@/assets/openseadragon-fabricjs-overlay.js'
import '@/assets/openseadragon-scalebar.js'
import { fabric } from 'fabric'
import axios from 'axios'
import { HTTP, IIP } from '@/router/http'
import { mapGetters } from 'vuex'
import { iipURL } from '@/app_config'
import channelDensities from '@/components/channelDensities.vue'
var timeout, interval
const CancelToken = axios.CancelToken
let cancel, cancelStat
let fetchCells = true
function getMetaDataURL (sample) {
	let path = `analyses/${sample}/sqrt_unmixed_images/image_unmixed.tiff`
	let url = `?FIF=${path}&obj=IIP,1.0&obj=Max-size&obj=Tile-size&obj=Resolution-number&obj=Resolutions`
	return url
}


function parseIIFMetadata (data) {
	let imageParams = {
		height: 0,
		width: 0,
		tileSize: 0,
		maxLevel: 0,
		resolutions: []
	}
	let parts = data.split(/\r\n/)
	_.forEach(parts, p => {
		let content = p.split(':')
		const k = content[0]
		const v = content[1]
		if (k === 'Max-size') {
			const values = v.split(' ')
			imageParams.width = +values[0]
			imageParams.height = +values[1]
		} else if (k === 'Tile-size') {
			const values = v.split(' ')
			imageParams.tileSize = +values[0]
		} else if (k === 'Resolution-number') {
			imageParams.maxLevel = +v
		} else if (k === 'Resolutions') {
			var levels = v.split(/,/)
			_.forEach(levels, l => {
				let dims = l.split(/ /)
				let nx = Math.ceil(dims[0] / imageParams.tileSize)
				let ny = Math.ceil(dims[1] / imageParams.tileSize)
				imageParams.resolutions.push({ nx: nx, ny: ny })
			})
		}
	})
	return imageParams
}

function computeCTW (channels) {
	var R = []; var G = []; var B = []; var intensity; var value
	for (let i = 0; i < channels.length; i++) {
		intensity = +channels[i].intensity
		value = Math.round(channels[i].color[0] / 255 * 100 * intensity)/100
		R.push(value)
		value = Math.round(channels[i].color[1] / 255 * 100 * intensity)/100
		G.push(value)
		value = Math.round(channels[i].color[2] / 255 * 100 * intensity)/100
		B.push(value)
	}
	return '[' + R.join(',') + ';' + G.join(',') + ';' + B.join(',') + ']'
}


var colorMap = function (color, factor) {
	factor = +factor
	if (factor < 0) {
		throw new Error('Contrast adjustment must be positive.')
	}
	var precomputedContrast = {
		r: [],
		g: [],
		b: []
	}
	for (var i = 0; i < 256; i++) {
		precomputedContrast.r[i] = Math.min(i * color[0] / 255 * factor, 255)
		precomputedContrast.g[i] = Math.min(i * color[1] / 255 * factor, 255)
		precomputedContrast.b[i] = Math.min(i * color[2] / 255 * factor, 255)
	}
	return function (context, callback) {
		var imgData = context.getImageData(0, 0, context.canvas.width, context.canvas.height)
		var pixels = imgData.data
		for (var i = 0; i < pixels.length; i += 4) {
			pixels[i] = precomputedContrast.r[pixels[i]]
			pixels[i + 1] = precomputedContrast.g[pixels[i + 1]]
			pixels[i + 2] = precomputedContrast.b[pixels[i + 2]]
		}
		context.putImageData(imgData, 0, 0)
		callback()
	}
}
var imageWidth = 1; var imageHeight = 1
var heImageWidth = 1; var heImageHeight = 1

export default {
	name: 'ifquantApp',
	components: { channelDensities },
	data () {
		return {
			imageParams: {
				height: 0,
				width: 0,
				tileSize: 0,
				maxLevel: 0,
				resolutions: []
			},
			prevRoute: {
				path: '',
				query: {}
			},
			processingStep: 'annotation',
			sample: '',
			sampleIds: {
				cells_properties_data: null,
				panel: null,
				pdf_report: null,
				report_date: null,
				report_status: null,
				reporter: null,
				sample_id: null,
				status: null,
				xlsx_data: null,
				xlsx_rois: []
			},
			viewer: null,
			bounds: {
				x: 0,
				y: 0,
				height: 1,
				width: 1
			},
			tumorChannel: 'CK',
			nucleusChannel: '',
			fabricOverlay: {},
			existingUnlabelledRoiIdx: [], // do not remove existing unlabelled ROIs
			overlaySet: [],
			cellType: '',
			thresholds: {},
			originalThresholds: {},
			autoThresholds: {},
			highlightCells: {},
			showHighlightCells: false,
			hasDensities: false,
			hasCellsDb: true,
			opacity: 0.5,
			tissueOpacity: 0.5,
			recomputeDisplayedROIs: 0,
			factor: 1,
			cells: [],
			total: 0,
			loading: false,
			loadingStats: false,
			loadingSampleIds: false,
			loadingNotifications: false,
			saturationDisplayed: false,
			sharpnessDisplayed: false,
			tissueDisplayed: false,
			tlsDisplayed: false,
			tissueThresholdAdjust: false,
			showCells: false,
			showTissueMask: true,
			tissueThreshold: 0,
			tissueSegmentations: [],
			colorMaps: {},
			channels: [],
			TLS: {},
			qcPDF: null,
			backgroundImage: 'composite',
			showNegatives: false,
			// showInform: false,
			showStats: true,
			stats: {
				ifquant: {},
				ifquant_tumor: {},
				ifquant_stroma: {},
				inform: {}
			},
			notifications: {

			},
			coordinates: {
				x: 0,
				y: 0,
				width: 0,
				height: 0
			},
			cvROItitles: ['Tumor tissue', 'Next to tumor tissue', 'TLS', 'Host tissue', 'Adipose tissue', 'Necrosis'],
			ROItitle: null,
			activeROIidx: -1,
			showOtherROItitle: false,
			annotateMode: false,
			drawMode: '',
			isAnnotationSelected: false,
			shiftKey: false,
			ctrlKey: false,
			openSeadragonReady: false,
			confirmReport: false,
			reportInPreparation: false,
			downloadingReport: false,
			confirmPublishAnalysis: false,
			confirmUnpublish: false,
			loadingOtherPhenotypes: false,
			QCs: [],
			showDensity: false,
			reportDeletionInProgress: false,
			confirmResetAnnotation: false,
			densityCellType: '',
			reviewedCellTypes: {},
			ifquantCmd: '',
			cmdTitle: ''
		}
	},
	methods: {
		clipboardSuccessHandler () {
			this.$snotify.success("Command copied successfully to the clipboard")
		},

		toggleChannelVisibility (idx) {
			let intensity
			if (this.channels[idx].intensity) {
				Vue.set(this.channels[idx], 'previousIntensity', (+this.channels[idx].intensity + 0))
				intensity = 0
			} else {
				intensity = (this.channels[idx].previousIntensity !== undefined) ? Math.round(this.channels[idx].previousIntensity * 10) / 10 : 1
			}
			this.channels[idx].intensity = intensity
			if (this.ctrlKey || this.shiftKey) {
				if (intensity) {
					_.forEach(this.channels, (c, cidx) => {
						if (cidx !== idx && !c.intensity && c.marker !== 'DAPI' && c.marker !== this.cellType) {
							let channelIntensity = (c.previousIntensity !== undefined && c.previousIntensity > 0) ? c.previousIntensity : 1
							Vue.set(this.channels[cidx], 'intensity', channelIntensity)
						}
					})
				} else {
					_.forEach(this.channels, (c, cidx) => {
						if (cidx !== idx && c.marker !== 'DAPI' && c.marker !== this.cellType) {
							if (+this.channels[cidx].intensity) {
								Vue.set(this.channels[cidx], 'previousIntensity', this.channels[cidx].intensity + 0)
							}
							Vue.set(this.channels[cidx], 'intensity', 0)
						}
					})
				}
			}
		},

		getTextColor (bgColor) {
			let rgbValue = []
			if (_.isArray(bgColor)) rgbValue = bgColor
			else rgbValue = bgColor.split(',')
			var color = Math.round(((parseInt(rgbValue[0]) * 299) +
                (parseInt(rgbValue[1]) * 587) +
                (parseInt(rgbValue[2]) * 114)) / 1000)
			return (color > 125) ? 'black' : 'white'
		},
		getCellTypeStyle (cellType) {
			let color = this.colorMaps[cellType].color
			if (cellType === this.cellType) {
				let textColor = this.getTextColor(color)
				return `background-color: rgb(${color}); color: ${textColor}; width: 100%; padding-left: 5px; font-size: 1rem`
			} else {
				return `background-color: transparent; color: rgb(${color}); width: 100%; padding-left: 5px; border: 1px solid rgb(${color}); font-size: 1rem`
			}
		},
		getChannelStyle (channel) {
			if (+channel.intensity) {
				let textColor = this.getTextColor(channel.color)
				return `background-color: rgb(${channel.color.join(',')}); color: ${textColor}; width: 100%; padding-left: 5px;`
			} else {
				return `background-color: transparent; color: white; width: 100%; padding-left: 5px; border: 1px solid rgb(${channel.color.join(',')})`
			}
		},

		backToList () {
			if (this.prevRoute.path !== '/') {
				this.$router.push({
					path: '/',
					query: {}
				})
			} else {
				this.$router.push({
					path: this.prevRoute.path,
					query: this.prevRoute.query
				})
			}
		},
	
		createViewer () {
			const _this = this
			let tileSources = this.getTileSources()
			this.viewer = OpenSeadragon({
				id: 'openseadragon',
				loadTilesWithAjax: true,
				prefixUrl: '../../openseadragon-icons/',
				tileSources: [
					{
						x: 0,
						y: 0,
						width: this.imageParams.width,
						tileSource: tileSources
					}
				],
				imageSmoothingEnabled: false,
				showNavigator: true,
				sequenceMode: false,
				navigatorId: 'navigator',
				navigatorAutoFade: false,
				maxZoomPixelRatio: 10,
				showFullPageControl: false
			})
			this.fabricOverlay = this.viewer.fabricjsOverlay({ scale: 1 })
			this.fabricOverlay.fabricCanvas().freeDrawingBrush.width = 10
			this.fabricOverlay.fabricCanvas().freeDrawingBrush.color = '#FFF'
			this.fabricOverlay.fabricCanvas().on('mouse:up', function () {
				Vue.nextTick().then(() => {
					_this.fabricOverlay.fabricCanvas().getObjects().forEach(o => {
						if (o.path.length < 20) {
							_this.fabricOverlay.fabricCanvas().remove(o)
							_this.saveAnnotations()
						} else {
							if (o.stroke === '#F00') {
								if (!o.fill) {
									o.fill = 'rgba(16,0,0,0.8)'
									// _this.saveAnnotations()
									_this.processingStep = 'annotation'
								}
							}
						}
					})
					_this.fabricOverlay.fabricCanvas().renderAll()
					_this.viewer.forceRedraw()
				})
			})

			this.fabricOverlay.fabricCanvas().on('selection:created', function (ev) {
				if (_this.drawMode === 'roi') {
					let annotItem = _this.fabricOverlay.fabricCanvas().getActiveObject()
					var pointer = _this.fabricOverlay.fabricCanvas().getPointer(ev.e, true)
					const offsetX = document.getElementById('leftPanel').offsetWidth
					var posX = pointer.x + offsetX
					var posY = pointer.y
					if (this.activeROIidx === -1) {
						let titleDiv = document.getElementById('ROIannotation')
						titleDiv.style.left = (posX - 40) + 'px'
						titleDiv.style.top = (posY + 10) + 'px'
						titleDiv.style.visibility = 'visible'
					}
					if (annotItem.title !== undefined) {
						_this.ROItitle = annotItem.title
					}
				}
				if (ev.target.path !== undefined) {
					let annotItem = _this.fabricOverlay.fabricCanvas().getActiveObject()
					if (annotItem.title !== undefined) {
						_this.ROItitle = annotItem.title
					}
					if (ev && ev.target !== undefined) {
						_this.showAnnotationTitle(ev)
						ev.target.set({
							hasControls: false,
							lockScalingX: true,
							lockScalingY: true
						})
					}
				} else {
					ev.target.set({
						hasControls: true,
						hasRotatingPoint: false
					})
				}
			})
			this.fabricOverlay.fabricCanvas().on('selection:updated', function (ev) {
				if (_this.drawMode === 'roi') {
					let annotItem = _this.fabricOverlay.fabricCanvas().getActiveObject()
					var pointer = _this.fabricOverlay.fabricCanvas().getPointer(ev.e, true)
					const offsetX = document.getElementById('leftPanel').offsetWidth
					var posX = pointer.x + offsetX
					var posY = pointer.y
					if (this.activeROIidx === -1) {
						let titleDiv = document.getElementById('ROIannotation')
						titleDiv.style.left = (posX - 40) + 'px'
						titleDiv.style.top = (posY + 10) + 'px'
						titleDiv.style.visibility = 'visible'
					}
					_this.ROItitle = annotItem.title
				}
				if (ev.target.path !== undefined) {
					let annotItem = _this.fabricOverlay.fabricCanvas().getActiveObject()
					if (annotItem.title !== undefined) {
						_this.ROItitle = annotItem.title
					}
					if (ev && ev.target !== undefined) {
						_this.showAnnotationTitle(ev)
						ev.target.set({
							hasControls: false,
							lockScalingX: true,
							lockScalingY: true
						})
					}
				} else {
					ev.target.set({
						hasControls: true,
						hasRotatingPoint: false
					})
				}
			})
			this.fabricOverlay.fabricCanvas().on('selection:cleared', function () {
				_this.ROItitle = null
				let titleDiv = document.getElementById('ROIannotation')
				titleDiv.style.left = '0px'
				titleDiv.style.top = '0px'
				titleDiv.style.visibility = 'hidden'
				_this.fabricOverlay.fabricCanvas().discardActiveObject().renderAll()
			})
			this.fabricOverlay.fabricCanvas().on('object:modified', function () {
				_this.saveAnnotations()
			})
			this.fabricOverlay.fabricCanvas().on('path:created', function (ev) {
				_this.showAnnotationTitle(ev)
			})
			this.viewer.addHandler('open', () => {
				let bounds = _this.viewer.viewport.getBoundsNoRotate()
				_this.bounds.x = bounds.x
				_this.bounds.y = bounds.y
				_this.bounds.height = bounds.height
				_this.bounds.width = bounds.width
				_this.getCells()
				if (_this.viewer.world.getItemCount()) {
					let tiledImage = _this.viewer.world.getItemAt(0)
					if (!tiledImage) return
					if (tiledImage) {
						_this.openSeadragonReady = true
						_this.loadQC()
					}
				}
				HTTP.get('/' + this.sample + '/annotations').then(res => {
					if (res.data) {
						if (res.data === 'processing') {
							_this.processingStep = 'processing'
						} else {
							_this.processingStep = 'analysis'
							_.forEach(res.data.objects, (o, oidx) => {
								if (o.fill === 'rgba(255,0,0,0.4)') {
									res.data.objects[oidx].fill = 'rgba(16,0,0,0.8)'
								}
							})
							_this.fabricOverlay.fabricCanvas().loadFromJSON(res.data)
							let objs = _this.fabricOverlay.fabricCanvas().getObjects()
							_.forEach(objs, (o, idx) => {
								if (o.stroke !== undefined && o.stroke !== '#F00') {
									if (o.title === undefined || !o.title) _this.existingUnlabelledRoiIdx.push(idx)
								}
							})
						}
					}
				}).catch(() => {
					_this.processingStep = 'annotation'
					_this.toggleOverlay('tissue')
					_this.toggleDraw('exclusion')
				})
				let pixelsPerMeter = Math.sqrt(this.tissueSegmentations[0].data.tumor_px / this.tissueSegmentations[0].data.tumor_area)*1e6
				_this.viewer.scalebar({
					type: OpenSeadragon.ScalebarType.MICROSCOPY,
					location: OpenSeadragon.ScalebarLocation.BOTTOM_LEFT,
				  pixelsPerMeter: pixelsPerMeter,
					stayInsideImage: false,
					color: '#FFF',
					fontColor: '#FFF',
					width: "150px",
					barThickness: 2
				});
				
			})
			this.viewer.addHandler('viewport-change', () => {
				if (timeout) {
					clearTimeout(timeout)
				}
				timeout = setTimeout(() => {
					let tooltip = document.getElementById('ifquantTooltip')
					tooltip.style.visibility = 'hidden'

					let bounds = _this.viewer.viewport.getBoundsNoRotate()
					_this.bounds.x = bounds.x
					_this.bounds.y = bounds.y
					_this.bounds.height = bounds.height
					_this.bounds.width = bounds.width
					_this.recomputeDisplayedROIs++
					_this.viewer.clearOverlays()
				}, 200)
			})
			this.viewer.addHandler('clear-overlay', () => {
				let tooltip = document.getElementById('ifquantTooltip')
				if (tooltip) tooltip.style.visibility = 'hidden'

				this.cells = []
				Vue.nextTick().then(() => {
					_this.getCells()
				})
			})


			window.addEventListener('keydown', function (ev) {
				_this.shiftKey = ev.shiftKey
				_this.ctrlKey = ev.ctrlKey
				if ((_this.annotateMode) && ev.shiftKey) {
					_this.viewer.setMouseNavEnabled(true)
					_this.viewer.outerTracker.setTracking(true)
				}
				if (ev.key === 'r' && ev.ctrlKey) {
					if (_this.openSeadragonReady) {
						_this.toggleDraw('roi')
					}
				} else if ((ev.key === 'x' || ev.key === 'e') && ev.ctrlKey) {
					if (_this.openSeadragonReady) {
						_this.toggleDraw('exclusion')
					}
				} else if (ev.key === 'a' && ev.ctrlKey) {
					if (_this.openSeadragonReady) {
						_this.toggleAnnotate()
					}
				}
			})
			window.addEventListener('keyup', function (ev) {
				if ((_this.annotateMode) && _this.shiftKey) {
					_this.viewer.setMouseNavEnabled(false)
					_this.viewer.outerTracker.setTracking(false)
				}
				_this.shiftKey = ev.shiftKey
				_this.ctrlKey = ev.ctrlKey
			})
		},

		updateViewer () {
			const _this = this
			const bounds = this.viewer.viewport.getBounds()
			let tileSources = this.getTileSources()
			this.viewer.addTiledImage({
				tileSource: tileSources,
				opacity: 1,
				index: 1,
				width: this.imageParams.width,
				success () {
					_this.viewer.viewport.fitBounds(bounds)
					const item = _this.viewer.world.getItemAt(0)
					_this.viewer.world.removeItem(item)
				}
			})
		},
		
		loadTissueSegmentations () {
			if (!this.canEdit) return
			const _this = this
			let promises = []
			_.forEach(this.tissueSegmentations, (seg, idx) => {
				promises.push(new Promise((resolve, reject) => {
					if (_this.tissueSegmentations[idx].img) resolve(_this.tissueSegmentations[idx].img)
					let proxyurl = `?`
					let path = 'analyses/' + _this.sample + '/tissue_segmentation/' + seg.cutoff + '/tissue_type_mask.tiff'
					let wid = 'WID=200&'
					let url = proxyurl + 'FIF=' + path + '&' + wid + 'CVT=jpeg'
					return HTTP.get(`/${_this.sample}/tissue_sementation_thumbnail${url}`, {
						responseType: 'arraybuffer',
						headers: {
							'Accept': 'image/jpeg'
						}
					}).then(res2 => {
						let b64 = btoa(new Uint8Array(res2.data).reduce(function (data, byte) {
							return data + String.fromCharCode(byte)
						}, ''))
						var mimeType = res2.headers['content-type'].toLowerCase()
						_this.tissueSegmentations[idx].img = 'data:' + mimeType + ';base64,' + b64
						resolve(_this.tissueSegmentations[idx].img)
					}).catch(err => reject(err))
				}))
			})
			return Promise.all(promises)
		},

		loadQC () {			
			const _this = this
			if (_this.qcPDF) return
				
				
			HTTP.get('/' + _this.sample + '/qcpdf', {
				responseType: 'arraybuffer',
				headers: {
					'Accept': 'application/png'
				}
			}).then(res2 => {
				let b64 = btoa(new Uint8Array(res2.data).reduce(function (data, byte) {
					return data + String.fromCharCode(byte)
				}, ''))
				var mimeType = res2.headers['content-type'].toLowerCase()
				_this.qcPDF = 'data:' + mimeType + ';base64,' + b64
			})			
			let qcs = ['saturation', 'sharpness']
			if (this.cellTypes.indexOf('CD20') > -1) qcs.push('tls');
			_.forEach(qcs, qc => {				
				const dir = (qc === 'tls') ? 'TLS' : 'cell_segmentation'
				const f = (qc === 'tls') ? 'TLS_mask' : qc
			
				let path = 'analyses/' + _this.sample + '/'+ dir +'/' + f + '.tiff'
				let url = `?FIF=${path}&obj=IIP,1.0&obj=Max-size&obj=Tile-size&obj=Resolution-number&obj=Resolutions`		
				return IIP.get(url).then( (res) => {
					let imageParams = parseIIFMetadata(res.data)
					if (_this.QCs.indexOf(qc) === -1) _this.QCs.push(qc)
				}).catch(() => {
					const idx = _this.QCs.indexOf(qc)
					if (idx > -1) _this.QCs.splice(idx, 1)
				})
			})				
		},
		
	
		init (data) {
			return new Promise((resolve) => {	
				const _this = this
				if (interval) clearInterval(interval)
				imageWidth = data.width
				imageHeight = data.height
				this.bounds = {
					x: 0,
					y: 0,
					width: imageWidth,
					height: imageHeight
				}
				this.sample = data.sample
				this.colorMaps = data.colorMaps
				_.forEach(data.colorMaps, (c, m) => {
					Vue.set(_this.channels, +c.channel, { marker: m, color: c.color.split(','), intensity: 1 })
				})
				_.forEach(data.colorMaps, (data,marker) => {
					if (data.type.indexOf('tumor')>-1){
						_this.tumorChannel = marker
					}
					if (data.type !== 'nucleus'){
						_this.highlightCells[marker] = null
					}
					if (data.type.indexOf('nucleus2') > -1){
						_this.nucleusChannel = marker
					}
				})
				this.TLS = data.TLS
				this.thresholds = data.thresholds
				this.originalThresholds = data.originalThresholds
				this.imageParams = Object.assign({}, this.imageParams, data.imageParams)
				this.hasDensities = data.hasDensities
			
				this.hasCellsDb = data.hasCellsDb
			
				_.forEach(Object.keys(this.colorMaps), k => {
					if (k !== 'DAPI') this.highlightCells[k] = null
				})
			
				_.forEach(Object.keys(data.thresholds), ct => {
					Vue.set(_this.stats.ifquant, ct, 0)
					Vue.set(_this.stats.inform, ct, 0)
				})
				this.autoThresholds = JSON.parse(JSON.stringify(data.thresholds))
				this.tissueThreshold = _this.tumorChannel.toLowerCase()+'_' + data.thresholds[_this.tumorChannel].value
				this.tissueSegmentations = data.tissue_segmentations
				resolve(true);
			})
		},
		defaultCutoff (cat, value) {
			return this.autoThresholds[cat].value === +value
		},
		originalCutoff (cat, value) {
			return this.originalThresholds[cat].value === +value
		},
		notify (message, type) {
			this.$snotify[type](message)
		},
		getRadius (value) {
			if (this.showNegatives) {
				return (Math.abs(value) > 0) ? 4 : 2
			} else {
				return 4
			}
		},
		getStrokeColor (value) {
			if (this.showNegatives) {
				return (Math.abs(value) > 0) ? '#FFF' : '#888'
			} else {
				return '#FFF'
			}
		},
		getColor (value) {
			if (this.showNegatives) {
				return (Math.abs(value) > 0) ?'#F00' : '#888'
			} else {
				return '#F00'
			}
		},		
		getTableStyle (ct) {
			if (ct === this.cellType) {
				return `width: ${100 / this.cellTypes.length}%; background-color: rgb(${this.colorMaps[ct].color}); color:${this.getTextColor(this.colorMaps[ct].color)}; font-weight:bold"}`
			} else {
				return `width: ${100 / this.cellTypes.length}%;color: rgb(${this.colorMaps[ct].color})`
			}
		},
		addOverlay (cell, cellIdx) {
			const _this = this
			const tiledImage = _this.viewer.world.getItemAt(0)
			if (!tiledImage) return
			let overlay = {
				x: +cell.x,
				y: +cell.y,
				id: `cell${cellIdx}`,
				checkResize: false,
				placement: 'CENTER'
			}
			let point = tiledImage.imageToViewportCoordinates(overlay.x, overlay.y)
			overlay.x = point.x
			overlay.y = point.y
			if (document.getElementById(overlay.id) && !isNaN(overlay.x)) {
				_this.viewer.addOverlay(overlay)
			}
		},
		getImageParams () {
			return this.imageParams
		},
		getTileSources () {
			const _this = this
			let sample = this.sample
			let imageParams = this.getImageParams()
			return {
				height: imageParams.height,
				width: imageParams.width,
				preload: true,
				tileSize: imageParams.tileSize,
				maxLevel: imageParams.maxLevel,
				minLevel: 1,
				getTileUrl: function (level, x, y) {
					level--
					let r, CTW
					r = imageParams.resolutions[level].nx * (y) + (x)
					CTW = computeCTW(_this.channels)
					let path = `analyses/${sample}/sqrt_unmixed_images/image_unmixed.tiff`
					return `${iipURL}?FIF=${path}&CTW=${CTW}&GAM=2&JTL=${level},${r}`
				}
			}
		},
		
		getStats () {
			if (!this.showStats) return
			let _this = this
			if (cancelStat !== undefined) {
				cancelStat()
			}
			return new Promise((resolve,reject) => {
				let tissueParam='';
				this.loadingStats = true
				HTTP.get(`/${this.sample}/stats?x=${Math.round(this.coordinates.x)}&y=${Math.round(this.coordinates.y)}&width=${Math.round(this.coordinates.width)}&height=${Math.round(this.coordinates.height)}&marker=${this.cellType}&threshold=${this.threshold}&type=${this.quantType}${tissueParam}`, {
					cancelToken: new CancelToken(function executor (c) {
						cancelStat = c
					})
				}).then(res => {
					_this.loadingStats = false
					_.forEach(res.data, (stats, type) => {
						_.forEach(stats, (nb, marker) => {
							_this.stats[type][marker] = +nb
						})
					})
					resolve(_this.stats)
				}).catch(() => {
					_this.loadingStats = false
					reject('error')
				})				
			})
		},
		getCells () {
			const _this = this
			fetchCells = true
			if (cancel !== undefined) {
				cancel()
			}
			if (cancelStat !== undefined) {
				cancelStat()
			}
			const tiledImage = _this.viewer.world.getItemAt(0)
			if (!tiledImage) return
			if (!_this.loading){
				let viewPortPointStart = new OpenSeadragon.Point(_this.bounds.x, _this.bounds.y)
				let	 imagePointStart = tiledImage.viewportToImageCoordinates(viewPortPointStart)
				let viewPortPointEnd = new OpenSeadragon.Point(_this.bounds.x + _this.bounds.width, _this.bounds.y + _this.bounds.height)
				let	 imagePointEnd = tiledImage.viewportToImageCoordinates(viewPortPointEnd)
				this.coordinates.x = imagePointStart.x
				this.coordinates.y = imagePointStart.y
				this.coordinates.width = imagePointEnd.x - this.coordinates.x
				this.coordinates.height = imagePointEnd.y - this.coordinates.y
				if (this.cellType === 'tissue' || !this.cellType || !this.showCells){
					return
				} 
				this.loading = true
				this.loadingStats = true
				let thresholds = []
				_.forEach(this.highlightCells, (v, ct) => {
					if (v !== null) {
						thresholds.push({
							marker: ct,
							threshold: _this.thresholds[ct].value,
							status: v
						})
					}
				})
				let params = {
					x: Math.round(this.coordinates.x),
					y: Math.round(this.coordinates.y),
					width: Math.round(this.coordinates.width),
					height: Math.round(this.coordinates.height),
					thresholds: thresholds,
					marker: this.cellType,
					threshold: this.threshold,
					type: this.quantType
				}
				HTTP.post(`/${this.sample}/cells`, {
					params: params,
					cancelToken: new CancelToken(function executor (c) {
						cancel = c
					})
				}).then(res => {
					_this.total = res.data.total
					_this.cells = res.data.cells
					_this.factor = res.data.factor
					_this.showNegatives = res.data.showNegatives
					Vue.nextTick()
						.then(function () {
							_.forEach(_this.cells, (cell, cellIdx) => {
								if (document.getElementById(`cell${cellIdx}`)) {
									if (cell.x !== undefined) {
										_this.addOverlay(cell, cellIdx)
										/* eslint-disable no-unused-vars */
										var tracker = new OpenSeadragon.MouseTracker({
											element: `cell${cellIdx}`,
											clickHandler: function(event) {
												if (_this.cellType){
													let formattedCellType = (_this.cellType.length > 8) ? _this.cellType.substr(0,8)+"." : _this.cellType
													let windowCoords = new OpenSeadragon.Point(event.originalEvent.x, event.originalEvent.y);
													let tooltip = document.getElementById('ifquantTooltip')
													tooltip.style.left=(windowCoords.x-50)+"px"
													tooltip.style.top=(windowCoords.y+10)+"px"
													tooltip.innerHTML = "<strong>"+formattedCellType+": "+Math.round(_this.cells[cellIdx].tooltip*10)/10																									
													tooltip.style.visibility='visible'
												}
											}
										});
									}
								}
							})
							_this.loading = false
						})
					_this.getStats().then(() => {
						_this.loadingStats = false
					})						
				}).catch(err => this.$snotify.error(err))
				
			}
		},
		toggleDensity () {
			this.showDensity = !this.showDensity
		},
		toggleTissueMask () {
			if (this.viewer.world.getItemCount() === 1) return
			if (this.opacity) {
				this.viewer.world.getItemAt(1).setOpacity(0)
				this.opacity = 0
			} else {
				this.viewer.world.getItemAt(1).setOpacity(0.5)
				this.opacity = 0.5
			}
		},
		toggleSaturation () {
			this.saturationDisplayed = !this.saturationDisplayed
		},
		toggleSharpness () {
			this.sharpnessDisplayed = !this.sharpnessDisplayed
		},
		toggleOverlay (category) {
			const _this = this
			this[`${category}Displayed`] = !this[`${category}Displayed`]
			let c = 0
			let intensity
			if (this[`${category}Displayed`]) {
				if (category === 'tissue') {
					this.showCells = false
					_this.toggleCellType(this.tumorChannel)
					_.forEach(this.channels, (c, idx) => {
						if (c.marker !== this.tumorChannel && c.marker !== 'DAPI') {
							if (this.channels[idx].intensity) {
								Vue.set(this.channels[idx], 'previousIntensity', (+this.channels[idx].intensity + 0))
							}

							this.channels[idx].intensity = 0
						} else {
							intensity = (this.channels[idx].previousIntensity !== undefined) ? Math.round(this.channels[idx].previousIntensity * 10) / 10 : 1
							this.channels[idx].intensity = intensity
						}
					})
					this.$store.commit('RESET_DENSITIES')
				} else if (category === 'tls') {
					if (this.cellTypes.indexOf('CD20') > -1) {
						this.showCells = false
						_.forEach(this.channels, (c, idx) => {
							if (c.marker !== 'CD20' && c.marker !== 'DAPI') {
								if (this.channels[idx].intensity) {
									Vue.set(this.channels[idx], 'previousIntensity', (+this.channels[idx].intensity + 0))
								}
								this.channels[idx].intensity = 0
							} else {
								intensity = (this.channels[idx].previousIntensity !== undefined) ? Math.round(this.channels[idx].previousIntensity * 10) / 10 : 1
								this.channels[idx].intensity = intensity
							}
						})
					}
				}
				this.displayOverlay(category)
			} else {
				if (category === 'tissue') {
					_this.toggleCellType(this.tumorChannel)
					this.showCells = false
				} else if (category === 'tls') {
					if (this.cellTypes.indexOf('CD20') > -1) {
						this.toggleCellType('CD20')
					}
				}
				const item = _this.viewer.world.getItemAt(1)
				_this.viewer.world.removeItem(item)
				this.tissueThresholdAdjust = false
				this.opacity = 0.5
				this.tissueOpacity = 0.5
			}
		},
		displayOverlay (category, cutoff) {
			const _this = this
			if (cutoff) {
				this[`${category}Threshold`] = cutoff
				
				this.thresholds[this.tumorChannel].value = +cutoff.replace(_this.tissueRegExp, '')
				this.saveThreshold(this.tumorChannel)
				this.viewer.clearOverlays()
			}
			const maxLevel = 1
			if (_this.viewer.world.getItemCount() > maxLevel) {
				const item = _this.viewer.world.getItemAt(maxLevel)
				_this.viewer.world.removeItem(item)
			}
			const bounds = this.viewer.viewport.getBounds()
			const dir = (category === 'tls') ? 'TLS' : 'cell_segmentation'
			const f = (category === 'tls') ? 'TLS_mask' : category

			const path = (category === 'tissue') ? `analyses/${this.sample}/tissue_segmentation/${this.tissueThreshold}/tissue_type_mask.tiff.dzi` : `analyses/${this.sample}/${dir}/${f}.tiff.dzi`
			this.viewer.addTiledImage({
				x: 0,
				y: 0,
				width: this.imageParams.width,
				tileSource: `${iipURL}?DeepZoom=${path}`,
				opacity: this.opacity,
				index: 1,
				preserveViewport: true,
				error (err) {
					_this.$snotify.error(err.message)
				},
				success () {
					_this.viewer.viewport.fitBounds(bounds)
					_this.updateViewerFilters(1)
				}
			})
		},
		toggleCellType (cellType) {
			this.showDensity = false
			if (this.cellType === cellType) {
				this.cellType = null
				this.viewer.clearOverlays()
			} else {
				this.cellType = cellType
				this.$store.commit("RESET_DENSITIES")
			}
			_.forEach(this.highlightCells, (v, cT) => {
				this.highlightCells[cT] = (cT === cellType) ? true : null
			})
			this.updateThreshold()
		},
		toggleCells () {
			this.showCells = !this.showCells
			if (this.showCells){
				if ( fetchCells) this.getCells()
			}
			else {
				fetchCells = false
			}
		},
		toggleInform (value) {
			this.quantType = value
			this.viewer.clearOverlays()
		},
		displayCellType (cellType) {
			const _this = this
			let intensity
			if (cellType) {
				_.forEach(this.channels, (c, idx) => {
					if (c.marker !== cellType && c.marker !== 'DAPI') {
						this.channels[idx].intensity = 0
					} else {
						intensity = (this.channels[idx].previousIntensity !== undefined) ? Math.round(this.channels[idx].previousIntensity * 10) / 10 : 1
						this.channels[idx].intensity = intensity
					}
				})
			} else {
				_.forEach(this.channels, (c, idx) => {
					if (c.marker !== 'DAPI') {
						this.channels[idx].intensity = 0
					} else {
						intensity = (this.channels[idx].previousIntensity !== undefined) ? Math.round(this.channels[idx].previousIntensity * 10) / 10 : 1
						this.channels[idx].intensity = intensity
					}
				})
			}
			this.viewer.clearOverlays()
		},
		updateViewerFilters (idx) {
			const _this = this
			let filters
			if (idx === 1 && this.tlsDisplayed) {
				let stopColor = [204, 0, 204]
				filters = [{
					items: _this.viewer.world.getItemAt(1),
					processors: [
						OpenSeadragon.Filters.GAMMA(2),
						colorMap(stopColor, 5)
					]
				}]
			}
			if (filters) {
				this.viewer.setFilterOptions({
					filters: filters,
					loadMode: 'sync'
				})
			}
		},
		resetThreshold () {
			this.showDensity = false
			this.updateThreshold(this.originalThresholds[this.cellType].value)
		},
		setHighlightCells (ct, value) {
			this.highlightCells[ct] = (this.highlightCells[ct] === value) ? null : value
			this.updateThreshold()
		},
		updateThreshold (value) {
			if (value !== undefined) {
				this.thresholds[this.cellType].value = value
			}
			const _this = this
			this.loadingNotifications = true
			if (this.thresholds[this.cellType] === undefined) return
			HTTP.get('/'+this.sample + '/notifications?marker=' + this.cellType + '&threshold=' + this.thresholds[this.cellType].value).then(res => {
				this.loadingNotifications = false
				_.forEach(res.data.thresholds, (data, ct) => {
					Vue.set(_this.notifications, ct, data)
				})
			}).catch(err => this.$snotify.error(err))
			this.viewer.clearOverlays()
		},
		saveThreshold (cT) {
			let _this = this
			if (!cT) cT = this.cellType
			if (cT) {
				HTTP.patch('/'+this.sample+'/thresholds', { marker: cT, threshold: this.thresholds[cT].value + '' }).then(() => {
					_this.$snotify.success('Threshold saved successfully')
				}).catch(err => _this.$snotify.error(err))
			}
		},

		// annotations

		toggleAnnotate () {
			this.annotateMode = !this.annotateMode
			if (this.annotateMode) {
				this.viewer.setMouseNavEnabled(false)
				this.viewer.outerTracker.setTracking(false)
				if (this.drawMode === 'exclusion') {
					this.fabricOverlay.fabricCanvas().isDrawingMode = true
					this.fabricOverlay.fabricCanvas().freeDrawingBrush.color = '#F00'
				}
				if (this.drawMode === 'roi') {
					this.fabricOverlay.fabricCanvas().isDrawingMode = true
					this.fabricOverlay.fabricCanvas().freeDrawingBrush.color = '#0F0'
				}

				// Activate fabric freedrawing mode
			} else {
				if (this.drawMode) this.toggleDraw(this.drawMode)
				this.viewer.setMouseNavEnabled(true)
				this.viewer.outerTracker.setTracking(true)
				this.fabricOverlay.fabricCanvas().discardActiveObject()
				this.fabricOverlay.fabricCanvas().requestRenderAll()
			}
		},
		toggleDraw (mode) {
			let _this = this
			this.drawMode = (this.drawMode === mode) ? '' : mode
			if (this.drawMode) {
				if (!this.annotateMode) {
					this.toggleAnnotate()
				}
				if (this.drawMode === 'exclusion') {
					this.fabricOverlay.fabricCanvas().isDrawingMode = true
					this.fabricOverlay.fabricCanvas().freeDrawingBrush.color = '#F00'
				} else if (this.drawMode === 'roi') {
					this.fabricOverlay.fabricCanvas().isDrawingMode = true
					this.fabricOverlay.fabricCanvas().freeDrawingBrush.color = '#0F0'
				} else if (this.drawMode === 'roir') {
					var rect, isDown, origX, origY

					this.fabricOverlay.fabricCanvas().on('mouse:down', function (o) {
						isDown = true
						var pointer = _this.fabricOverlay.fabricCanvas().getPointer(o.e)
						origX = pointer.x
						origY = pointer.y
						rect = new fabric.Rect({
							left: origX,
							top: origY,
							originX: 'left',
							originY: 'top',
							width: pointer.x - origX,
							height: pointer.y - origY,
							angle: 0,
							fill: 'transparent',
							stroke: 'rgb(30,255,01)',
							strokeWidth: '5',
							hasControls: true,
							hasRotatingPoint: false,
							transparentCorners: false
						})
						_this.fabricOverlay.fabricCanvas().add(rect)
						_this.fabricOverlay.fabricCanvas().setActiveObject(rect)
					})

					_this.fabricOverlay.fabricCanvas().on('mouse:move', function (o) {
						if (!isDown) return
						var pointer = _this.fabricOverlay.fabricCanvas().getPointer(o.e)

						if (origX > pointer.x) {
							rect.set({ left: Math.abs(pointer.x) })
						}
						if (origY > pointer.y) {
							rect.set({ top: Math.abs(pointer.y) })
						}

						rect.set({ width: Math.abs(origX - pointer.x) })
						rect.set({ height: Math.abs(origY - pointer.y) })


						_this.fabricOverlay.fabricCanvas().renderAll()
					})

					this.fabricOverlay.fabricCanvas().on('mouse:up', function () {
						isDown = false
						_this.fabricOverlay.fabricCanvas().off('mouse:down').off('mouse:move').off('mouse:up')
						_this.fabricOverlay.fabricCanvas().setActiveObject(rect)
						_this.toggleDraw('roir')
						_this.saveAnnotations()
					})
				}
			}
			if (this.drawMode !== 'roi' && this.drawMode !== 'exclusion') {
				// this.viewer.setMouseNavEnabled(true);
				// this.viewer.outerTracker.setTracking(true);
				// Disable freedrawing mode
				this.fabricOverlay.fabricCanvas().isDrawingMode = false
			}
		},
		removePath () {
			if (this.isAnnotationSelected) {
				const target = this.fabricOverlay.fabricCanvas().getActiveObject()
				if (target.stroke === '#F00') {
					this.processingStep = 'annotation'
				}
				let oidx = this.fabricOverlay.fabricCanvas().getObjects().indexOf(target)
				if (oidx > -1) {
					let idx = this.existingUnlabelledRoiIdx.indexOf(oidx)
					if (idx > -1) this.existingUnlabelledRoiIdx.splice(idx, 1)
				}
				this.fabricOverlay.fabricCanvas().remove(target)
				
			}
			this.checkAnnotationStatus()
			if (!this.isExclusion) this.saveAnnotations()
		},
		checkAnnotationStatus () {
			if (this.fabricOverlay && this.fabricOverlay.fabricCanvas && {}.toString.call(this.fabricOverlay.fabricCanvas) === '[object Function]' && this.fabricOverlay.fabricCanvas().getActiveObject()) {
				this.isAnnotationSelected = true
				let annotItem = this.fabricOverlay.fabricCanvas().getActiveObject()
				let titleDiv = document.getElementById('ROIannotation')
				if (titleDiv.style.visibility !== 'visible' && this.drawMode === 'roi') {
					if (this.activeROIidx === -1) {
						var posX = event.clientX
						var posY = event.clientY
						titleDiv.style.left = (posX - 100) + 'px'
						titleDiv.style.top = (posY - 85) + 'px'
						titleDiv.style.visibility = 'visible'
					}
					this.ROItitle = annotItem.title
				}
			} else this.isAnnotationSelected = false
		},
		showAnnotationTitle (event) {
			let pointer
			if (this.drawMode === 'exclusion') return
			if (event && event.target && event.target.stroke === '#F00') return
			if (this.activeROIidx > -1) return
			pointer = this.fabricOverlay.fabricCanvas().getPointer(event.e, true)
			const offsetX = document.getElementById('leftPanel').offsetWidth
			var posX = pointer.x + offsetX
			var posY = pointer.y
			let titleDiv = document.getElementById('ROIannotation')
			titleDiv.style.left = (posX - 40) + 'px'
			titleDiv.style.top = (posY + 10) + 'px'
			titleDiv.style.visibility = 'visible'
			this.showOtherROItitle = (this.ROItitle && this.cvROItitles.indexOf(this.ROItitle) === -1)
		},
		saveAnnotations (addTitle) {
			const _this = this
			let objects
			this.activeROIidx = -1
			let jsonPaths = this.fabricOverlay.fabricCanvas().toJSON(['title'])
			let activeObject = this.fabricOverlay.fabricCanvas().getActiveObject()
			if (addTitle) {
				let activeObject = this.fabricOverlay.fabricCanvas().getActiveObject()
				if (!activeObject) {
					objects = this.fabricOverlay.fabricCanvas().getObjects()
					let lastObject = objects[objects.length - 1]
					this.fabricOverlay.fabricCanvas().setActiveObject(lastObject)
				}
				activeObject = this.fabricOverlay.fabricCanvas().getActiveObject()
				let idx = -1
				if (activeObject) {
					activeObject.set('title', this.ROItitle)
					idx = _.findIndex(jsonPaths.objects, o => {
						return o.top === activeObject.top && o.left === activeObject.left
					})
				} else {
					idx = jsonPaths.objects.length - 1
				}
				if (idx > -1) {
					jsonPaths.objects[idx].title = this.ROItitle
				}
			}
			objects = this.fabricOverlay.fabricCanvas().getObjects()
			this.fabricOverlay.fabricCanvas().getObjects().forEach((o, oidx) => {
				if (o.stroke === '#0F0' && (o.title === undefined || o.title === '') && _this.existingUnlabelledRoiIdx.indexOf(oidx) === -1) {
					_this.fabricOverlay.fabricCanvas().remove(o)
				}
			})
			this.fabricOverlay.fabricCanvas().renderAll()
			this.viewer.forceRedraw()
			
			if (this.ROItitle && this.cvROItitles.indexOf(this.ROItitle) === -1) {
				this.cvROItitles.push(this.ROItitle)
			}
			jsonPaths = this.fabricOverlay.fabricCanvas().toJSON(['title'])
			if (this.processingStep !== 'annotation' || addTitle === 'SUBMIT') {
				if (addTitle === 'SUBMIT') {
					this.reportInPreparation = true
				}
				HTTP.post('/' + this.sample + '/annotations', jsonPaths).then(res => {
					this.reportInPreparation = false
					this.ROItitle = null
					let titleDiv = document.getElementById('ROIannotation')
					titleDiv.style.left = '0px'
					titleDiv.style.top = '0px'
					titleDiv.style.visibility = 'hidden'
					this.fabricOverlay.fabricCanvas().discardActiveObject().renderAll()
					this.processingStep = res.data.status
					if (res.data.cmd){
						_this.ifquantCmd = res.data.cmd
						_this.cmdTitle = 'Run IFQuant analysis'
						_this.$refs.ifquantCmdModal.show()
					}
					HTTP.get('/' + this.sample + '/annotations').then(res => {
						if (res.data) {
							if (res.data === 'processing') {
								_this.processingStep = 'processing'
							} else {
								_this.processingStep = 'analysis'
								_.forEach(res.data.objects, (o, oidx) => {
									if (o.fill === 'rgba(255,0,0,0.4)') {
										res.data.objects[oidx].fill = 'rgba(16,0,0,0.8)'
									}
								})
							}
							_this.fabricOverlay.fabricCanvas().loadFromJSON(res.data)							
						}
					}).catch(() => {
						_this.processingStep = 'annotation'
						_this.toggleOverlay('tissue')
						_this.toggleDraw('exclusion')
					})
				}).catch(err => this.$snotify.error(err))
			}
			if (activeObject) {
				this.fabricOverlay.fabricCanvas().discardActiveObject().renderAll()
			}
			this.isAnnotationSelected = false
		},

		// REPORT

		createReport () {
			const _this = this
			if (this.sampleIds.report_date && !this.confirmReport) {
				this.confirmReport = true
			} else {
				this.reportInPreparation = true
				HTTP.put('/'+ this.sample +'/report').then(res => {
					_this.ifquantCmd = res.data
					_this.cmdTitle = 'Create IFQuant Report'
					_this.$refs.ifquantCmdModal.show()
				}).catch(err => {
					_this.$snotify.error(err)
				})
			}
		},
		deleteReport () {
			const _this = this
			if (this.sampleIds.report_date && !this.confirmReport) {
				this.confirmReport = true
			} else {
				this.reportDeletionInProgress = true
				HTTP.delete('/'+this.sample+'/report').then(() => {
					_this.reportDeletionInProgress = false
					_this.sampleIds.reporter = null
					_this.sampleIds.report_date = null
					_this.sampleIds.report_status = null
					_this.sampleIds.pdf_report = null
					_this.sampleIds.pdf_report_neotil = null
					_this.sampleIds.xlsx_data = null
					_this.sampleIds.cells_properties_data = null
					_this.sampleIds.xlsx_rois = []
					_this.confirmReport = false
					_this.$snotify.success('Report deleted successfully')
				}).catch(err => {
					_this.$snotify.error(err)
					_this.confirmReport = false
					_this.reportDeletionInProgress = false
				})
			}
		},

		download (file, filename) {
			const _this = this
			this.downloadingReport = true
			HTTP.get('/'+this.sample+'/report/' + file, {
				responseType: 'arraybuffer'
			}).then(res => {
				let blob = new Blob([res.data], { type: 'application/binary' })
				let link = document.createElement('a')
				link.href = window.URL.createObjectURL(blob)
				link.download = filename
				link.click()
				_this.downloadingReport = false
			}).catch(err => {
				_this.$snotify.error(err)
				_this.downloadingReport = false
			})
		},

		formatPhenotype (pheno) {
			const parts = pheno.match(/(\w+)([+-])(\w+)?([+-])?(\w+)?([+-])?(\w+)?([+-])?(\w+)?([+-])?(\w+)?([+-])?/)
			let max = 0;
			var i = 0;
			for (i = 0; i < parts.length; i++){
				if (parts[i] !== undefined) max = (i+1)
			}
			let div = ''
			let c = ''
			for (i = 1; i < max; i = i + 2) {
				c = ''
				if (parts[i + 1] === '-') c = 'danger'
				if (parts[i + 1] === '+') c = 'success'
				div += "<small class='text-" + c + "'>" + parts[i] + parts[i + 1] + '</small>'
			}
			return div
		},
		highlightROI (idx, active) {
			let objects = this.fabricOverlay.fabricCanvas().getObjects()
			let activeObject = objects[idx]
			if (active) {
				activeObject.setOptions({ fill: 'rgba(255,255,255,0.1)', strokeWidth: 20 })
			} else {
				activeObject.setOptions({ fill: 'transparent', strokeWidth: 10 })
			}
			this.fabricOverlay.fabricCanvas().renderAll()
		},
		
		selectROI (idx) {
			if (!this.canEdit || this.isExclusion) return
			let objects = this.fabricOverlay.fabricCanvas().getObjects()
			let activeObject = objects[idx]
			this.fabricOverlay.fabricCanvas().setActiveObject(activeObject).renderAll()
		},		
		editROI (idx) {
			this.activeROIidx = idx
			let objects = this.fabricOverlay.fabricCanvas().getObjects()
			let activeObject = objects[idx]
			this.fabricOverlay.fabricCanvas().setActiveObject(activeObject).renderAll()
			this.ROItitle = activeObject.title
		},
		cancelROI () {
			this.activeROIidx = -1
			this.fabricOverlay.fabricCanvas().discardActiveObject().renderAll()
			this.ROItitle = ''
			this.isAnnotationSelected = false
		},
		resetAnnotations () {
			const _this = this
			if (!this.confirmResetAnnotation) {
				this.confirmResetAnnotation = true
			} else {
				if (this.sampleIds.report_date) {
					this.confirmReport = true
					this.deleteReport()
				}

				HTTP.delete('/' + this.sampleIds.sample_id + '/annotations').then(res => {
					_this.reportInPreparation = false
					_this.confirmResetAnnotation = false
					_this.$snotify.success('Annotations reset successfully')
					_this.fabricOverlay.fabricCanvas().clear()
					_this.processingStep = 'annotation'
					_this.toggleOverlay('tissue')
					_this.toggleDraw('exclusion')
				}).catch(err => this.$snotify.error(err))
			}
		},
		resetReviewedCellTypes () {
			_.forEach(_.filter(Object.keys(this.colorMaps), k => k !== 'DAPI'), ct => {
				if (!this.densityCellType) {
					this.densityCellType = ct
					this.$set(this.reviewedCellTypes, ct, true)
				} else this.$set(this.reviewedCellTypes, ct, false)
			})
		},
		setDensityCellType (ct) {
			this.$set(this.reviewedCellTypes, ct, true)
			this.densityCellType = ct
		}
		
		
	},		


	computed: {
		cellTypes () {
			return _.filter(Object.keys(this.colorMaps), k => k !== 'DAPI')
		},
		otherCellTypes () {
			return _.filter(this.cellTypes, ct => ct !== this.cellType)
		},
		threshold () {
			if (this.thresholds[this.cellType] === undefined) {
				return 0
			}
			return (this.thresholds[this.cellType].value)
		},
		percentTumor () {
			const _this = this
			let thr = _.filter(_this.tissueSegmentations, t => {
				return t.cutoff === _this.tumorChannel.toLowerCase()+'_' + _this.thresholds[_this.tumorChannel].value
			})
			if (!thr.length) return ''
			return Math.round((thr[0].data.tumor_area) / (thr[0].data.stroma_area + thr[0].data.tumor_area) * 1000) / 10
		},
		warningThreshold () {
			if (this.thresholds === undefined || this.thresholds[this.tumorChannel] === undefined) return true
			return this.thresholds[this.tumorChannel].status !== 'SUCCESS'
		},
		isExclusion () {
			return (this.processingStep === 'annotation' || this.processingStep === 'processing')
		},
		canEdit () {
			return !this.loadingSampleIds && this.processingStep !== 'annotation' && !this.sampleIds.pdf_report && this.sampleIds.report_status !== 'PENDING' && this.sampleIds.report_status !== 'RUNING' && !this.reportInPreparation
		},
		tissueRegExp () {
			return new RegExp(this.tumorChannel+"_", "i");
		},
		warningPercentTumor () {
			const objs = this.fabricOverlay.fabricCanvas().getObjects()
			let ret = false
			_.forEach(objs, o => {
				if (o.stroke !== undefined && o.stroke === '#F00') {
					ret = true
				}
			})
			return ret
		},
		ROIs () {
			let ROIs = []
			if (this.fabricOverlay.fabricCanvas !== undefined) {
				let objs = this.fabricOverlay.fabricCanvas().getObjects()
				_.forEach(objs, (o, idx) => {
					if (o.stroke !== undefined && o.stroke !== '#F00') {
						ROIs.push({ id: idx, title: o.title })
					}
				})
				return ROIs
			}
			return []
		},
		heROIs () {
			let heROIs = []
			if (this.HEcanvas.getObjects !== undefined) {
				let objs = this.HEcanvas.getObjects()
				_.forEach(objs, (o, idx) => {
					if (o.stroke !== undefined && o.stroke !== '#F00') {
						heROIs.push({ id: `${idx}`, title: o.title })
					}
				})
				return heROIs
			}
			return []
		},
		ROIwithoutLabel () {
			return _.filter(this.ROIs, R => !R.title).length
		},
		tissueSegmentationsLoaded () {
			let loaded = true
			_.forEach(this.tissueSegmentations, t => {
				if (!t.img) loaded = false
			})
			return loaded
		},
		nbTissueSegmentationsImgs () {
			let nb = 0
			_.forEach(this.tissueSegmentations, t => {
				if (t.img) nb++
			})
			return nb
		}
	},
	mounted () {
		const _this = this
		if (!this.sample) {
			this.sample = this.$route.params.sample
		}
		this.loadingSampleIds = true
		HTTP.get('/' + this.sample + '/sample').then(res => {
			this.loadingSampleIds = false
			this.sampleIds = res.data
			if (res.data.cmd){
				_this.ifquantCmd = res.data.cmd
				_this.cmdTitle = 'Run IFQuant analysis'
				_this.$refs.ifquantCmdModal.show()
			}
			
			if (res.data.report_status === 'PENDING' || res.data.report_status === 'RUNNING') _this.reportInPreparation = true
		}).catch(err => {
			this.$snotify.error(err)
			this.$router.push('/')
		})

		let wheight = window.innerHeight
		document.getElementById('openseadragon').style.height = (wheight - 120) + 'px'
		document.getElementById('leftPanel').style.height = (wheight - 180) + 'px'
		if (!_this.colorMaps.length) {
			HTTP.get('/'+_this.$route.params.sample+'/thresholds').then(res => {
				let allData = {
					TLS: res.data.TLS,
					colorMaps: res.data.colorMaps,
					thresholds: res.data.thresholds,
					originalThresholds: res.data.original_thresholds,
					tissue_segmentations: [],
					sample: _this.$route.params.sample,
					width: res.data.dimensions.width,
					height: res.data.dimensions.height,
					hasDensities: res.data.has_densities,
					hasCellsDb: res.data.has_cells_db
					
				}
				let tumorChannel = 'CK'
				_.forEach(res.data.colorMaps, (data,marker) => {
					if (data.type.indexOf('tumor') > -1){
						tumorChannel = marker
					}
				})
				_.forEach(res.data.tissue_segmentations, seg => {
					allData.tissue_segmentations.push({ cutoff: seg[tumorChannel.toLowerCase()+"_threshold"], img: '', data: seg })
				})

				const meatadataUrl = getMetaDataURL(_this.$route.params.sample)
				IIP.get(meatadataUrl).then(res => {
					allData.imageParams = parseIIFMetadata(res.data)
					_this.init(allData).then(() => {
						Vue.nextTick().then(() => {
							_this.createViewer()
						})
					})
				}).catch(err => {
					_this.notify(err, 'error')
				})				
			}).catch(err => {
				_this.notify(err, 'error')
			})
		} else {
			_this.createViewer()
		}
		this.updateViewer = _.debounce(this.updateViewer, 200)
	},
	watch: {
		sample: {
			handler () {
				if (this.viewer !== null) {
					this.viewer.world.removeAll()
					let tileSources = this.getTileSources()
					this.viewer.close()
					this.viewer.open(tileSources)					
				}
			},
			deep: true
		},
		
		cellType (n) {
			this.displayCellType(n)
		},
		tissueThresholdAdjust (displayed) {
			if (displayed) {
				let wheight = window.innerHeight
				if (document.getElementById('divTissueThresholdLoading')) {
					document.getElementById('divTissueThresholdLoading').style.height = (wheight - 75) + 'px'
				}
				this.loadTissueSegmentations().then(() => {
					Vue.nextTick().then(() => {
						let wheight = window.innerHeight
						if (document.getElementById('divTissueThreshold')) {
							document.getElementById('divTissueThreshold').style.height = (wheight - 75) + 'px'
						}

						const el = document.getElementById('default'+this.tumorChannel)
						if (el) {
							el.previousSibling.scrollIntoView()
						}
						window.scrollTo(0, 0)
					})
				})
			}
		},
		ROItitle (n) {
			if (n === 'other...') {
				this.ROItitle = null
				this.showOtherROItitle = true
			}
		},
		channels: {
			handler (n, o) {
				if (this.viewer && this.viewer.viewport !== undefined) {
					_.forEach(n, (c, idx) => {
						if (c.intensity && o[idx].intensity !== n.intensity) {
							Vue.set(this.channels[idx], 'previousIntensity', (+this.channels[idx].intensity + 0))
						}
					})
					this.updateViewer()
				}
			},
			deep: true
		},
		opacity (n, o) {
			if (n !== o) {
				if (this.viewer.world.getItemCount() > 1) {
					this.viewer.world.getItemAt(1).setOpacity(n)
				}
			}
		}
		
	},
	beforeRouteEnter (to, from, next) {
		next(_this => {
			_this.prevRoute.path = from.path
			_this.prevRoute.query = from.query
		})
	},
	beforeDestroy () {
		if (this.viewer){
			this.viewer.destroy()	
		}
		if (interval) clearInterval(interval)
	}

}
</script>
<style>
div.ifquant{
	background-color: black;
	color: white;
}
img.thumbnail {
	width: 600px;
}
.viewer {
	position: relative;
}


#openseadragon {
	margin: 0 5%;
	width: 90%;
	height: 850px;
}
button.active {
	-webkit-box-shadow: inset 1px 1px 2px -1px rgba(0,0,0,0.75);
	-moz-box-shadow: inset 1px 1px 2px -1px rgba(0,0,0,0.75);
	box-shadow: inset 1px 1px 2px -1px rgba(0,0,0,0.75);
}
#leftPanel, #leftPanelLoading {
	position: absolute;
	top: 50px;
	left: 0;
	padding: 20px;
	width: 450px;
	height: 100%;
	z-index: 2;
/*	border: 1px solid yellow;*/
	overflow-y: auto;
}
#imagePanel {
	position: absolute;
	width: 100%;
	left: 0;
	top: 20px;
	padding-left: 450px;
	z-index: 1;
}
#coordinates {
	position: absolute;
	bottom: 9px;
	right: 110px;
	color: #CCC;
	font-weight: bold;
	font: 14px Courier;
	z-index: 100;
	width: 325px;
	height: 180px;
}
#navigator {
	position: absolute;
	top: 0;
	left: 0;
	width: 100%;
	height: 100%;
	background-color: rgba(33,33,33,0.3);
	border: 1px solid #333;
}
#topleft{
	position: absolute;
	top: 5px;
	left: 5px;
	z-index: 10;
}
#bottomright {
	position: absolute;
	bottom: 5px;
	right: 5px;
	z-index: 10;
}

#divTissueThreshold,#divTissueThresholdLoading {
	position: absolute;
	top:  -22px;
	right: -22px;
	width: 300px;
	height: 100%;
	padding: 20px;
	background-color: #2C3E50;
	z-index: 3;
}
#ROIannotation {
	position: fixed;
	width: 200px;
	height: 75px;
	font-size: 12px;
	color: black;
	text-align: center;
	box-shadow: 1px 1px 1px 1px rgba(255, 255, 255, .3);
	background: white;
	left: 100px;
	right: 100px;
	z-index: 100000;
	border-radius: 6px;
	visibility: hidden;
}

#ifquantTooltip {
	position: fixed;
	width: 100px;
	height: 20px;
	font-size: 12px;
	color: black;
	text-align: center;
	box-shadow: 1px 1px 1px 1px rgba(255, 255, 255, .3);
	background: white;
	left: 10px;
	right: 10px;
	z-index: 100000;
	border-radius: 6px;
	visibility: hidden;
}

#ifquantTooltip::after {
  content: " ";
  position: absolute;
  bottom: 100%;  /* At the top of the tooltip */
  left: 50%;
  margin-left: -5px;
  border-width: 5px;
  border-style: solid;
  border-color: transparent transparent white transparent;
}

#densityContainer {
	width: 100%;
	height: auto;
	padding-bottom: 20px;
	border: 1px solid white;
	background-color: #222;
}
#ROItable tr {
	color: white;
	border-color: white;
}
#ROItable tbody>tr:hover{
	background-color: #222;
}
.highlight {
	opacity: 0.4;
	filter: alpha(opacity=40);
	outline: 12px auto #0A7EbE;
	background-color: white;
	z-index: 2000;
}
th.inputColumn {
	min-width: 65px !important;
}
#IFQuantContainer code{
	color: yellow;
}
</style>
