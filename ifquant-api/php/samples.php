<?php
function listSamples(){
	$cells = glob(DATA_PATH."/analyses/*/cells_properties_pixels.txt");
	$params = array();
	$samples = array();
	foreach($cells as $c){
		$sample = basename(dirname($c));
		if (file_exists(dirname($c)."/DB_RUNNING")){
			$samples[] = array("sample" => $sample,"ready" => false);
		}
		elseif (file_exists(dirname($c)."/cells.db")){
			$samples[] = array("sample" => $sample,"ready" => true);
		}
		else{
			$samples[] = array("sample" => $sample,"ready" => false);
			$params[] = $sample;
		}
	}
	if (count($params)){
		if (file_exists(TOOLS_PATH."/createCellDB.php") && is_readable(TOOLS_PATH."/createCellDB.php")){
			exec("php ".TOOLS_PATH."/createCellDB.php -s ".implode(",",$params)." >/dev/null 2>&1 &");
		}
	}
	return $samples;
}

function listQptiffs(){
	$allQptiffs = glob(DATA_PATH."/samples/*/*.{qptiff,ome.tiff,ome.tif}",GLOB_BRACE);
	$qptiffs = array();
	foreach($allQptiffs as $qptiff){
		$sample = pathinfo($qptiff,PATHINFO_FILENAME);
		if (strtolower(substr($sample,-4,4))===".ome") $sample = substr($sample,0,-4);
		$dir =  pathinfo($qptiff,PATHINFO_DIRNAME);
		$paramFiles = array(
			"channel_thresholding.tsv" => (file_exists($dir."/channel_thresholding.tsv")?TRUE:"MISSING"),
			"panel.tsv" => (file_exists($dir."/panel.tsv")?TRUE:"MISSING"),
			"phenotypes.tsv" => (file_exists($dir."/phenotypes.tsv")?TRUE:"MISSING"),
			"unmixing_parameters.csv" => (file_exists($dir."/unmixing_parameters.csv")?TRUE:"MISSING"),
			"unmixing_parameters_values_distribution.csv" => (file_exists($dir."/unmixing_parameters_values_distribution.csv")?TRUE:"MISSING")
		);
		$showCMD = TRUE;
		foreach($paramFiles as $f => $exists){
			if ($exists !== TRUE) $showCMD = FALSE;
		}
		$analysisDir = DATA_PATH."/analyses/".$sample;
		if (!file_exists($analysisDir)){
			if ($showCMD){
				$optionalFields = array("x","y","height","width","automatic.thresholding.method");
				$has_errors = false;
				foreach($paramFiles as $paramFile => $status){
					if (file_exists(TEMPLATE_PATH."/".$paramFile)){
						$templateRows = file(TEMPLATE_PATH."/".$paramFile,FILE_IGNORE_NEW_LINES);
						$dataRows = file($dir."/".$paramFile,FILE_IGNORE_NEW_LINES);
						if (count($dataRows) < 3) {
							$paramFiles[$paramFile] = "less than 3 lines";
							$has_errors = true;
							continue;
						}
						$sep = (substr($paramFile,-3,3) == 'csv') ? "," : "\t";
						$template_header = array_shift($templateRows);
						$data_header = array_shift($dataRows);
						$template_headers = str_getcsv($template_header,$sep);
						$data_headers = str_getcsv($data_header,$sep);
						$diffs = array_diff($template_headers,$data_headers);
						if (count($diffs)){
							$missing_fields = array();
							foreach($diffs as $diff){
								if (!in_array($diff,$optionalFields)){
									$missing_fields[] = $diff;
								}
							}
							if (count($missing_fields)){
								$paramFiles[$paramFile] = "missing '".(implode("', '",$missing_fields))."' column".(count($missing_fields)>1?"s":"");
								$has_errors = true;
								continue;								
							}
						}
						if ($paramFile == 'panel.tsv'){
							$has_nucleus = false;
							$has_tumor = false;
							$has_AF = false;
							while(count($dataRows)){
								$row = array_shift($dataRows);
								$cols = str_getcsv($row,"\t");
								if (count($cols) == count($data_headers)){
									$chanel_data = array_combine($data_headers,$cols);
									if ($chanel_data['type'] == 'tumor') $has_tumor = true;
									if ($chanel_data['type'] == 'nucleus') $has_nucleus = true;
									if ($chanel_data['type'] == 'AF') $has_AF = true;
								}
							}
							if (!$has_tumor || !$has_nucleus || !$has_AF){
								$required_fields = array("nucleus","tumor","AF");
								$msg = array();
								foreach($required_fields as $rf){
									if (!${"has_".$rf}) $msg[] = "No ".$rf." channel";
								}
								$paramFiles[$paramFile] = implode(". ",$msg);
								$has_errors = true;
							}
						}
					}
				}
				if ($has_errors){
					$segmentationCmd = NULL;
				}
				else{
					$tmpdircmd = (defined("TMPDIR") && TMPDIR && file_exists(TMPDIR)) ? PHP_EOL.'  --tmpdir='.TMPDIR.' \\' : "";
					$ROI_cmd = "";
					$cp_json_cmd = "";
					if ((file_exists($dir.'/ROI.csv') || file_exists($dir.'/excluded_regions.csv')) && !file_exists($dir.'/annotations.json')){
						$cp_json_cmd = " && \\".PHP_EOL."docker compose run --rm ifquant-app php /var/www/tools/ROI2json.php \\";
						if (file_exists($dir."/excluded_regions.csv")){
							$ROI_cmd .= PHP_EOL.'  --excluded-regions='.$dir."/excluded_regions.csv \\";
							$cp_json_cmd .= PHP_EOL."  -x ".$dir."/excluded_regions.csv \\";
						}
						if (file_exists($dir."/ROI.csv")){
							$ROI_cmd .= PHP_EOL.'  --ROI='.$dir."/ROI.csv \\";
							$cp_json_cmd .= PHP_EOL."  -r ".$dir."/ROI.csv \\";
						}
						$cp_json_cmd .= PHP_EOL."  -o /var/www/data/analyses/".$sample."/data/annotations.json";
						
					}
					$segmentationCmd = "docker compose run --rm ifquant-engine run_segmentation.sh \\"
	          .PHP_EOL."  --output=/var/www/data/analyses/ \\"
	          .PHP_EOL."  --nprocesses=".NPROCESSES." \\"
						.$tmpdircmd
	          .PHP_EOL."  --unmixing-parameters=".$dir."/unmixing_parameters.csv \\"
	          .PHP_EOL."  --metadata-panel=".$dir."/panel.tsv \\"
	          .PHP_EOL."  --channel-thresholding=".$dir."/channel_thresholding.tsv  \\"
	          .PHP_EOL."  --channel-normalization=".$dir."/unmixing_parameters_values_distribution.csv \\"
	          .PHP_EOL."  --phenotypes=".$dir."/phenotypes.tsv \\"
	          .PHP_EOL."  --image=\"/var/www/data/samples/".basename($dir)."/".basename($qptiff)."\" && \\"
	          .PHP_EOL."docker compose run --rm ifquant-engine run_analysis.sh \\"
						.$ROI_cmd
	          .PHP_EOL."  --no-report \\"
	          .PHP_EOL."  --nprocesses=2 \\"
	          .PHP_EOL."  --path=/var/www/data/analyses/".$sample." && \\"
						.PHP_EOL."docker compose run --rm ifquant-engine chmod -R 777 /var/www/data/analyses/".$sample
						.$cp_json_cmd;					
					
				}
				$qptiffs[] = array("qptiff" => basename($qptiff), "sample" => $sample, "CMD" => $segmentationCmd,"paramFiles" => $paramFiles);	
			}
			else{
				$qptiffs[] = array("qptiff" => basename($qptiff), "sample" => $sample, "CMD" => "", "paramFiles" => $paramFiles);	
			}
		}
	}
	return $qptiffs;
}

function getSample($sample_id) {
	$dir = DATA_PATH."/analyses/".$sample_id;
	$data = array(
		"sample_id" => $sample_id,
		"panel" => NULL
	);
	
	$panelFile = $dir."/data/metadata_panel.txt";
	if (file_exists($panelFile)) {
		$rows = file($panelFile,FILE_IGNORE_NEW_LINES);
		$header = array_shift($rows);
		$headers = str_getcsv($header,"\t");
		$panelMarkers = [];
		foreach($rows as $row) {
			$cols = str_getcsv($row,"\t");
			$markerData = array_combine($headers,$cols);
			if ($markerData['filter'] == 'AUTOFLUO') continue;
			$panelMarkers[] = $markerData['name'];
		}
		$data['panel'] = implode("|",$panelMarkers);
	}
	
	
	$data['status'] = "SUCCESS";
	$data['report_status'] = NULL;
	$data['pdf_report'] = NULL;
	$data['xlsx_data'] = NULL;
	$data['cells_properties_data'] = NULL;
	$data['cells_properties_data2'] = NULL;
	$data['report_date'] = NULL;
	$data['xlsx_rois'] = array();
	if (file_exists($dir."/PROCESSING")){
		$data['status'] = "RUNNING";
		if (file_exists($dir."/data/run_analysis.sh")){
			$data['cmd'] = file_get_contents($dir."/data/run_analysis.sh");
		}
	}
	else{
		if (file_exists($dir."/data/run_analysis.sh")){
			unlink($dir."/data/run_analysis.sh");
		}
	}
	if (!file_exists($dir."/PROCESSING") && file_exists($dir."/report/report.pdf")){
		$data['status']	 = "SUCCESS";
		$data['report_status'] = "SUCCESS";
		$data['report_date'] = date("Y-m-d",filemtime($dir."/report/report.pdf"));
		$data['pdf_report'] = "report.pdf";
		if (file_exists($dir."/report/summary_all.xlsx")) $data['xlsx_data'] = "summary_all.xlsx";
		if (file_exists($dir."/report/cells_properties.tsv.gz")) $data['cells_properties_data'] = "cells_properties.tsv.gz";
		if (file_exists($dir."/report/cells_properties_2.tsv.gz")) $data['cells_properties_data2'] = "cells_properties_2.tsv.gz";
		$xlsxfiles = glob($dir."/report/summary_ROI_*.xlsx");
		foreach($xlsxfiles as $xlsxfile) {
			$xls_roi = array("file" => basename($xlsxfile),"name" => basename($xlsxfile));
			if ($xlsx_template = SimpleXLSX::parse(file_get_contents($xlsxfile),true)) {
				$rows = $xlsx_template->rows();
				foreach($rows as $cols) {
					if ($cols[0]=='ROI labels:') {
						$xls_roi['name'] = $cols[1];
					}
				}
			}
			$data['xlsx_rois'][] = $xls_roi;
		}
	}
	return $data;
}

?>