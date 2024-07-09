<?php
use function Amp\ParallelFunctions\parallelMap;
use function Amp\Promise\wait;

if (!defined("IFQUANT_DROPBOX")) define("IFQUANT_DROPBOX","/home/local/immucan/dropbox_ifquant/");

function getCells($sample,$params) {
	set_time_limit(120);
	$limit =  2000;
	if (preg_match("/(^[^_]*_\d{4})_?.*/",$sample,$regs)) $sample = $regs[1];
	$file = DATA_PATH."/analyses/".$sample."/cells.db";
	if (!file_exists($file)) {
		throw new Exception("ERROR: no quantification file available", 404);
		return false;
	}

	$output = array();
	$readFromDB = false;
	if (file_exists(DATA_PATH."/analyses/".$sample."/cells.db")) {
		if (!is_readable(DATA_PATH."/analyses/".$sample."/cells.db")){
			throw new Exception("ERROR: index file is not readable", 1);
		}
		$readFromDB = true;
		$nbTrials = 0;
		while($nbTrials < 5){
			$nbTrials++;
			usleep(rand(10,100));
			$db = new SQLite3(DATA_PATH."/analyses/".$sample."/cells.db");
			if ($db) {
				break;
			}
		}
		if (!$db) {
			return;
		}


		$db->busyTimeout(5000);
		// WAL mode has better control over concurrency.
		// Source: https://www.sqlite.org/wal.html
		$db->exec('PRAGMA journal_mode = WAL');
		$db->exec('PRAGMA synchronous = normal');
		$db->exec('PRAGMA temp_store = memory');
		$db->exec('PRAGMA mmap_size = 30000000000');
		
		if (!$db) {
			throw new Exception("ERROR: unable to open cells.db file", 404);
		}
		if (isset($params['marker']) && isset($params['threshold']) && !isset($params['thresholds'])){
			$params['thresholds'] = array(
				array(
					"marker" => $params['marker'],
					"threshold" => $params['threshold'],
					"status" => TRUE
				)
			);
		}
		$where = "";
		foreach($params['thresholds'] as $idx => $thr) {
			$where .= " and `".strtolower($thr['marker'])."` ".($thr['status']?">=":"<")." ".$thr['threshold']." ";
		}
		$dbmarker = strtolower($params['marker']);
		$q = "SELECT count(*) as nb from cells where x >= ".($params['x']<0?0:$params['x'])." and x <= ".($params['x']+$params['width'])." and y >= ".($params['y']<0?0:$params['y'])." and y <= ".($params['y']+$params['height']).$where;
		$total = intval($db->querySingle($q));
		$factor = ceil($total / $limit);
		if ($factor==0) $factor = 1;
		$q = "SELECT x,y,`".$dbmarker."` as marker from cells where x >= ".($params['x']<0?0:$params['x'])." and x <= ".($params['x']+$params['width'])." and y >= ".($params['y']<0?0:$params['y'])." and y <= ".($params['y']+$params['height']).$where;
		$r = $db->query($q);
		$idx = -1;
		while ($s = $r->fetchArray()) {
			$idx++;
			if ($idx % $factor) continue;
			$output[] = array(
				"x" => +$s['x'],
				"y" => +$s['y'],
				$params['marker'] => +$s['marker'],
				"tooltip" => +$s['marker']
			);
		}
	}
	$showNegatives = false;
	if ($factor <= 1) {
		$q = "SELECT count(*) as nb from cells where x >= ".($params['x']<0?0:$params['x'])." and x <= ".($params['x']+$params['width'])." and y >= ".($params['y']<0?0:$params['y'])." and y <= ".($params['y']+$params['height'])." and `".$dbmarker."` < ".$params['threshold'];
		$totalNeg = intval($db->querySingle($q));
		if (($totalNeg + $total) < $limit) {
			$showNegatives = true;
			$q = "SELECT x,y,`".$dbmarker."` as marker from cells where x >= ".($params['x']<0?0:$params['x'])." and x <= ".($params['x']+$params['width'])." and y >= ".($params['y']<0?0:$params['y'])." and y <= ".($params['y']+$params['height'])." and `".$dbmarker."` < ".$params['threshold'];
			$r = $db->query($q);
			$idx = -1;
			while ($s = $r->fetchArray()) {
				$idx++;
				if ($idx % $factor) continue;
				$output[] = array(
					"x" => +$s['x'],
					"y" => +$s['y'],
					$params['marker'] => 0,
					"tooltip" => +$s['marker']
				);
			}
		}
	}
	return array('factor' => $factor, 'total' => $total,"cells" => $output,"showNegatives" => $showNegatives);

	return $params;
}


function getColorMapsAndThresholds($sample) {
	$file = DATA_PATH."/analyses/".$sample."/cells.db";
	$dir = dirname($file);
	if (!file_exists($file)) {
		throw new Exception("ERROR: sample unknwown", 404);
		return false;
	}
	$markers = array();
	$thresholds = array();
	$original_thresholds = array();
	$has_densities = file_exists($dir."/score_density/density_1_2.png");
	$has_cells_db = file_exists($dir."/cells.db");


	$panelFile = $dir."/data/metadata_panel.txt";
	if (file_exists($panelFile)) {
		$rows = file($panelFile,FILE_IGNORE_NEW_LINES);
		$header = array_shift($rows);
		$headers = str_getcsv($header,"\t");
		foreach($rows as $row) {
			$cols = str_getcsv($row,"\t");
			$markerData = array_combine($headers,$cols);
			if ($markerData['filter'] == 'AUTOFLUO') continue;
			$markers[$markerData['name']] = array("color" => $markerData['color'], "cellType" => "undefined", "marker" => $markerData['filter'], "channel" => $markerData['channel'], "type" => $markerData['type']);
			$thresholds[$markerData['name']] = array("value" => 5,"method" => "default","status" => "NOT_DONE");
			$original_thresholds[$markerData['name']] = array("value" => 5,"method" => "default","status" => "NOT_DONE");
		}
	}
	$thresholding_file = $dir."/data/analysis/metadata_channel_thresholding.txt";
	if (file_exists($thresholding_file)) {
		$rows = file($thresholding_file,FILE_IGNORE_NEW_LINES);
		$header = array_shift($rows);
		$headers = str_getcsv($header,"\t");
		foreach($rows as $row) {
			$cols = str_getcsv($row,"\t");
			if (count($headers) == count($cols)){
				$data = array_combine($headers,$cols);
				$thresholds[$data["name"]] = array("value" => +$data["threshold"],"method" => $data["score.type"]);
				$original_thresholds[$data["name"]] = array("value" => +$data["threshold"],"method" => $data["score.type"]);
			}
		}
	}
	$orig_thresholding_file = $dir."/data/analysis/metadata_channel_thresholding_orig.txt";
	if (file_exists($orig_thresholding_file)) {
		$rows = file($orig_thresholding_file,FILE_IGNORE_NEW_LINES);
		$header = array_shift($rows);
		$headers = str_getcsv($header,"\t");
		foreach($rows as $row) {
			$cols = str_getcsv($row,"\t");
			if (count($headers) == count($cols)){
				$data = array_combine($headers,$cols);
				$original_thresholds[$data["name"]] = array("value" => +$$data["threshold"],"method" => $data["score.type"]);
			}
		}
	}
	if (isset($thresholds['DAPI'])) $thresholds['DAPI']['value'] = 0;
	if (isset($original_thresholds['DAPI'])) $original_thresholds['DAPI']['value'] = 0;
	$thresholding_status_file = $dir."/automatic_channel_thresholding/automatic_channel_thresholding_status.txt";
	if (file_exists($thresholding_status_file)) {
		$rows = file($thresholding_status_file,FILE_IGNORE_NEW_LINES);
		$header = array_shift($rows);
		$headers = str_getcsv($header,"\t");
		foreach($rows as $row) {
			$cols = str_getcsv($row,"\t");
			if (count($headers) == count($cols)){
				$data = array_combine($headers,$cols);
				if (isset($thresholds[$data["name"]])) $thresholds[$data["name"]]['status'] = $data["status"];
			}

		}
	}
	if (isset($thresholds['DAPI'])) $thresholds['DAPI']['status'] = "SUCCESS";

	$tissue_segmentation_data = array();
	$tissue_segs = glob($dir."/tissue_segmentation/ck_*",GLOB_ONLYDIR);
	$headers = array("ck_threshold","tumor_px","tumor_area","stroma_px","stroma_area","other_px","other_area","status");
	foreach($tissue_segs as $tissue_seg) {
		$seg = basename($tissue_seg);
		if (!file_exists($tissue_seg."/tissue_area.txt")) {
			throw new Exception("ERROR: Unable to parse tissue segmentation files. ".$tissue_seg."/tissue_area.txt is missing", 1);
		}
		$segData = array();
		$rows = file($tissue_seg."/tissue_area.txt",FILE_IGNORE_NEW_LINES);
		$header = array_shift($rows);
		$headers = str_getcsv($header,"\t");
		foreach($rows as $row) {
			$cols = str_getcsv($row,"\t");
			if (count($cols) == count($headers)) {
				$data = array_combine($headers,$cols);
				$segData[$data['tissue.type']] = array("px" => $data['tissue.area.pixel2'], 'area' => $data['tissue.area.micron2']);
			}
		}
		$tissue_segmentation_data[] = array(
			"ck_threshold" => $seg,
			"tumor_px" => +$segData['tumor']['px'],
			"tumor_area" => +$segData['tumor']['area'],
			"stroma_px" => +$segData['stroma']['px'],
			"stroma_area" => +$segData['stroma']['area'],
			"other_px" => +$segData['other']['px'],
			"other_area" => +$segData['other']['area'],
			"status" => "SUCCESS"
		);
	}
	usort($tissue_segmentation_data, function($a,$b){
		$ai = floatval(preg_replace("/[^0-9.]/","",$a['ck_threshold']));
		$bi = floatval(preg_replace("/[^0-9.]/","",$b['ck_threshold']));
		if (!$ai) return 1;
		if (!$bi) return -1;
		if ($ai < $bi) return -1;
		if ($ai > $bi) return 1;
		return 0;
	});

	$img_path = "samples/".$sample."/sqrt_unmixed_images/image_unmixed.tiff";
	$iip_path = IIP_SERVER."Zoomify=".$img_path."/ImageProperties.xml";
	$arrContextOptions=array(
	    "ssl"=>array(
	        "verify_peer"=>false,
	        "verify_peer_name"=>false,
	    ),
	);

	$data = @file_get_contents($iip_path,false, stream_context_create($arrContextOptions));
	$dimensions = array('width'=>1, "height" => 1);
	if ($data) {
		$xml = simplexml_load_string($data);
		$dimensions =  array('width' => +(string)$xml[0]['WIDTH'],'height' => +(string)$xml[0]['HEIGHT']);
	}
	$TLS = array("total" => -1);
	if (file_exists($dir."/TLS/summary.tsv")){
		$tls_rows = file($dir."/TLS/summary.tsv",FILE_IGNORE_NEW_LINES);
		$header = array_shift($tls_rows);
		$headers = str_getcsv($header,"\t");
		foreach($tls_rows as $tls_row){
			$tls_cols = str_getcsv($tls_row,"\t");
			if (count($tls_cols) == count($headers)){
				$data = array_combine($headers,$tls_cols);
				if (isset($data['name']) && isset($data['value'])){
					$TLS[$data['name']] = $data['value'].((isset($data['unit'])&&$data['unit'])?" [".$data['unit']."]":"");
					if (is_numeric($TLS[$data['name']])) $TLS[$data['name']] = +$TLS[$data['name']];
					if ($data['name'] == 'Number of patches') $TLS['total'] = +$TLS[$data['name']];
				}
			}
		}
	}
	return array("thresholds" => $thresholds, "original_thresholds" => $original_thresholds, "colorMaps" => $markers,"tissue_segmentations" => $tissue_segmentation_data,"dimensions" => $dimensions,"has_densities" => $has_densities, 'has_cells_db' => $has_cells_db, "TLS" => $TLS);
}

function getQCPDF($sample) {
	$file = DATA_PATH."/analyses/".$sample."/automatic_channel_thresholding/automatic_channel_thresholding_ck.pdf";
	if (!file_exists($file)) {
		throw new Exception("ERROR: sample unknwown", 404);
		return false;
	}
	$png = str_replace(".pdf",".png",$file);
	if (!file_exists($png)) {
		$cmd = "convert -density 150 ".$file." -quality 80 ".$png;
		exec($cmd);
	}
	if (file_exists($png)) {
		$file = fopen($png, "rb");
		$imagedata = fread($file, filesize($png));
		fclose($file);
		return $imagedata;
	}
	throw new Exception("ERROR: unable to convert PDF", 404);

}

function cellPhenotypes($sample,$params = null){
	set_time_limit(180);
	$file = DATA_PATH."/analyses/".$sample."/cells.db";
	$dir = dirname($file);

	if (!file_exists($file)){
		error_log($dir." NOT FOUND");
		throw new Exception("ERROR: unable to find cells.db", 1);
	}
	chdir($dir);

	$phenotypes = array();
	$thresholds = array();


	$nbTrials = 0;
	while($nbTrials < 5){
		$nbTrials++;
		usleep(rand(10,100));
		$db = new SQLite3('cells.db');
		if ($db) {
			break;
		}
	}
	if (!$db) {
		return;
	}
	$db->busyTimeout(5000);
	$db->exec('PRAGMA journal_mode = WAL');
	$db->exec('PRAGMA synchronous = normal');
	$db->exec('PRAGMA temp_store = memory');
	$db->exec('PRAGMA mmap_size = 30000000000');

	if (!$db) {
		return;
	}

	$r = $db->query("SELECT * from thresholds")	;
	$channels = array();
	while($row = $r->fetchArray()){
		$threshold = ($params && strtolower($params['marker']) == $row['name']) ? $params['threshold'] : $row['threshold'];
		$thresholds[$row['name']] = $threshold;
		$channels[$row['name']] = "channel_".$row['channel'];
	}
	$db->query("update cells set phenotype = null");
	$r = $db->query("SELECT * from phenotypes")	;
	while($row = $r->fetchArray()){
		$cmd = "update cells set phenotype = '".$row['label']."' where ";
		$cmds = array();
		foreach($thresholds as $name => $threshold){
			$cT = (isset($row[$name])) ? $row[$name] : (isset($row[$channels[$name]]) ? $row[$channels[$name]] : '');
			if ($cT){
				if ($cT == '+') $cmds[] = $name." >= ".$threshold;
				elseif ($cT == '-') $cmds[] = $name." < ".$threshold;
			}
		}
		$cmd .= implode(" and ",$cmds);
		$db->query($cmd);
	}
	$r = $db->query("SELECT * from cells where phenotype is null");
	$c = 0;
	$other_phenotypes = array();
	while($row = $r->fetchArray()){
		$cellphenotype = "";
		foreach($thresholds as $name => $threshold){
			$cellphenotype .= strtoupper($name).((+$row[$name] < +$threshold) ? "-" : "+");
		}
		if (!isset($other_phenotypes[$cellphenotype])) $other_phenotypes[$cellphenotype] = 0;
		$other_phenotypes[$cellphenotype]++;
	}

	arsort($other_phenotypes);
	$total = $db->querySingle("select count(*) as nb from cells");
	$db->close();
	unset($db);
	$return = array();
	foreach($other_phenotypes as $name => $nb){
		$return[] = array("phenotype" => $name, "count" => $nb, "percent" => round(+$nb/$total*100,1));
	}

	return $return;
}


function patchTreshold($sample,$params) {
		$file = DATA_PATH."/analyses/".$sample."/data/analysis/metadata_channel_thresholding.txt";
		if (!file_exists($file)) {
			throw new Exception("ERROR: sample unknwown", 404);
			return false;
		}
		$origFile = str_replace(".txt","_orig.txt",$file);
		if (!file_exists($origFile)) copy($file,$origFile);
		$data = file($file,FILE_IGNORE_NEW_LINES);
		$header = array_shift($data);
		$headers = explode("\t",$header);
		$nameIdx = array_search('name',$headers);
		$thresIdx = array_search('threshold',$headers);
		if ($nameIdx === FALSE || $thresIdx === FALSE) {
			throw new Exception("ERROR: file cannot be parsed", 1);
		}
		foreach($data as $idx => $row) {
			$cols = explode("\t",$row);
			if ($cols[$nameIdx] === $params['marker']){
				$cols[$thresIdx] = $params['threshold'];
				$data[$idx] = implode("\t",$cols);
			}
		}
		$dbfile = DATA_PATH."/analyses/".$sample."/cells.db";
		$dir = dirname($dbfile);
		chdir($dir);
		if (!file_exists($dbfile)){
			throw new Exception("ERROR: unable to find cells.db", 1);
		}
		$nbTrials = 0;
		while($nbTrials < 5){
			$nbTrials++;
			usleep(rand(10,100));
			$db = new SQLite3($dbfile);
			if ($db) {
				break;
			}
		}
		if (!$db) {
			return;
		}


		$db->busyTimeout(5000);
		// WAL mode has better control over concurrency.
		// Source: https://www.sqlite.org/wal.html
		$db->exec('PRAGMA journal_mode = WAL');
		$db->exec('PRAGMA synchronous = normal');
		$db->exec('PRAGMA temp_store = memory');
		$db->exec('PRAGMA mmap_size = 30000000000');

		$db->query("update thresholds set threshold = ".$params['threshold']." where name = '".strtolower($params['marker'])."'");
		$db->close();
		return file_put_contents($file,$header."\n".implode("\n",$data));
}



function cleanAnnotationJson($json){
// remove if user specified annotation is disabled
	return $json; 
//
	$csv = array(
		"Adipose tissue" => "adipose_tissue",
		"Host tissue" => "host_tissue",
		"Necrosis" => "necrosis",
		"Next to tumor tissue" => "next_to_tumor_tissue",
		"TLS" => "tls",
		"Tumor tissue" => "tumor_tissue"
	);

	$data = json_decode($json);
	$cleanData =json_decode($json);;
	$cleanData->objects = array();
	foreach($data->objects as $oid => $obj){
		if ($obj->stroke == '#0F0'){
			if (isset($obj->title) && isset($csv[$obj->title])){
				$cleanData->objects[] = $obj;
			}
		}
		else {
			$cleanData->objects[] = $obj;
		}
	}

	return json_encode($cleanData);

}

function saveAnnotations($sample, $json) {
	
	$file = DATA_PATH."/analyses/".$sample."/data/annotations.json";
	if (!file_exists(dirname($file))) {
		throw new Exception("ERROR: sample $sample unknwown in file system", 404);
		return false;
	}
	if (file_exists($file)){
		$old_annots = formatAnnotations($file);
	}
	else {
		$old_annots = array("exclusion" => "","ROI" => "");
	}
	$old_exlusions =  md5(json_encode($old_annots['exclusion']));
	$cleanJson = cleanAnnotationJson($json);
	file_put_contents($file,$cleanJson);
	if (!file_exists($file)) {
		throw new Exception("ERROR: annotation not saved", 404);
	}
	$new_annots = formatAnnotations($file);
	$new_exlusions =  md5(json_encode($new_annots['exclusion']));
	$status = ($new_exlusions === $old_exlusions) ? "analysis" : "processing";
	$cmd = "";
	if ($status == 'processing') {
		touch(dirname(dirname($file))."/PROCESSING");
		chmod(dirname(dirname($file))."/PROCESSING",0770);
		$cmd = submitReport($sample,$user,false);
	
	}		
	$return = array("status" => $status, "cmd" => $cmd);
	return $return;
}

function getAnnotations ($sample) {
	$file = DATA_PATH."/analyses/".$sample."/data/annotations.json";
	if (file_exists(dirname(dirname($file))."/PROCESSING")) return 'processing';
	if (!file_exists($file)) {
		throw new Exception("ERROR: no annotation", 404);
	}
	return file_get_contents($file);
}

function deleteAnnotations($sample_id){
	$file = DATA_PATH."/analyses/".$sample_id."/data/annotations.json";
	if (file_exists($file)){
		$rm = unlink($file);
		if ($rm === FALSE){
			error_log("ERROR: ".$file." NOT DELETED");
		}
	}
	else error_log("ERROR: ".$file." not found");
	return $sample_id;	
}


function formatAnnotations($jsonfile){
	if (!file_exists($jsonfile)) {
		throw new Exception("ERROR: file unknown", 404);
	}
	$data = json_decode(file_get_contents($jsonfile),JSON_OBJECT_AS_ARRAY);
	$exclusion_id = 0;
	$ROI_id = 0;
	$ROI = ['id,x,y,label'];
	$exclusion = ['id,x,y,label'];
	foreach($data['objects'] as $object) {
		$type = "";
		$label = "";
		if (count($object['path']) < 20) continue;
		if ($object['stroke'] == '#F00') {
			$exclusion_id++;
			$type = "exclusion";
		}
		else if ($object['stroke'] == '#0F0') {
			$ROI_id++;
			$type = 'ROI';
		}
		if (isset($object['title'])) {
			$label = trim(str_replace(","," ",$object['title']));
		}
		if ($type) {
			if (!$label) $label = ${$type."_id"};
			foreach($object['path'] as $path) {
				if (count($path)>2) {
					if ($path[0] == 'M' || $path[0] == 'L'){
						${$type}[] = ${$type."_id"}.",".($path[1]).",".($path[2]).",".$label;	
					}
					else if($path[0] == 'Q' && count($path) > 4){
						${$type}[] = ${$type."_id"}.",".($path[3]).",".($path[4]).",".$label;	
					}
				}
			}
		}
	}
	return array("exclusion" => $exclusion,"ROI" => $ROI);
}

function getNotifications($sampleId,$params) {
	set_time_limit(120);
	
	$dir = DATA_PATH."/analyses/".$sampleId;
	if (!file_exists($dir)) {
		throw new Exception("ERROR: sample unknown", 404);
	}
	$thresholding_file = $dir."/data/analysis/metadata_channel_thresholding.txt";
	if (!file_exists($thresholding_file)) {
		throw new Exception("ERROR: unable to get thresholds", 404);
	}
	if (!file_exists($dir."/cells.db")) {
		throw new Exception("ERROR: unable to read cells.db", 404);

	}

	$nbTrials = 0;
	while($nbTrials < 5){
		$nbTrials++;
		usleep(rand(10,100));
		$db = new SQLite3($dir."/cells.db");
		if ($db) {
			break;
		}
	}
	if (!$db) {
		return;
	}

	$db->busyTimeout(5000);
	// WAL mode has better control over concurrency.
	// Source: https://www.sqlite.org/wal.html
	$db->exec('PRAGMA journal_mode = WAL');
	$db->exec('PRAGMA synchronous = normal');
	$db->exec('PRAGMA temp_store = memory');
	$db->exec('PRAGMA mmap_size = 30000000000');


	$dbmarker = strtolower($params['marker']);
	$total = $db->querySingle("SELECT count(*) from cells where `".$dbmarker."` >= ".+$params['threshold']);
	$db->query("UPDATE thresholds set threshold = ".$params['threshold']." where name = '".$dbmarker."'");		
	$thresholds = array();
	$rows = file($thresholding_file,FILE_IGNORE_NEW_LINES);
	array_shift($rows);
	foreach($rows as $row) {
		$cols = explode("\t",$row);
		$q = "SELECT count(*) as nb from cells where `".$dbmarker."` >= ".$params['threshold']." and ".strtolower($cols[1])." >= ".$cols[3];
		$nb = (strtolower($cols[1]) == $dbmarker) ? +$total : intval($db->querySingle($q));
		$percent = ($total) ? round(+$nb/$total*100,1) : 0;
		$thresholds[$cols[1]] = array("threshold" => +$cols[3], "count" => $nb, "percent" => $percent);
	}
	$db->close();
	return array("thresholds" => $thresholds);
}

function getOtherPhenotypes($sample) {
	$dir = DATA_PATH."/analyses/".$sample;
	$other_phenotypes = array();
	if (file_exists($dir."/cells.db")){
		$other_phenotypes = cellPhenotypes($sample);
	}
	return $other_phenotypes;
}

function getReportStatus($sample){
	$dir = DATA_PATH."/analyses/".$sample;
	if (!file_exists($dir)) {
		throw new Exception("ERROR: sample unknown", 404);
	}

	if(file_exists($dir."/PROCESSING")) return "RUNNING";
	$db_status = DB::queryFirstField("SELECT
			ifquant_analyses.status
		FROM
			ifquant_analyses
			inner join extract_id_view on ifquant_analyses.sample_id = extract_id_view.extract_id
			INNER JOIN users ON ifquant_analyses.user_id = users.user_id
		WHERE
			extract_id_view.sample_id=%s
			and ifquant_analyses.type <> 'TLS'
		ORDER BY
			ifquant_analyses.ifquant_analysis_id DESC
		LIMIT 1;",$sample);
		return ($db_status === 'RUNNING' || $db_status === 'PENDING') ? $db_status : "DONE";
}

function submitReport($sample,$withReport=TRUE) {	
	$README_file = DATA_PATH."/analyses/".$sample."/data/README.txt";
	if (!file_exists($README_file)){
		throw new Exception("ERROR: unable to find README file", 404);
	}
	$qptiff = exec("grep  -e '^image=.*ome.tiff$' -e '^image=.*qptiff$' -e '^image=.*ome.tif$' ".$README_file." | cut -d= -f 2");
	if (!file_exists($qptiff)){
		throw new Exception("ERROR: QPTIFF file not found in ".$qptiff, 404);
	}
	$dir = DATA_PATH."/analyses/".$sample."/data";
	if (!file_exists($dir)) {
		throw new Exception("ERROR: sample unknown", 404);
	}
	if (!file_exists($dir."/metadata_channel_thresholding.txt")){
		throw new Exception("ERROR: channel thresholding file missing", 404);		
	}
	if (!file_exists(dirname($dir)."/sqrt_unmixed_images/image_unmixed.tiff")){
		throw new Exception("ERROR: image file missing", 1);		
	}
	$panelFile = $dir."/metadata_panel.txt";
	$tumorMarker = exec("cut -f 2,5 ".$dir."/metadata_panel.txt|grep 'tumor'|cut -f 1");
	$tumorMarker = trim($tumorMarker);
	$testCD20 = exec("cut -f 2 ".$panelFile."|grep CD20");
	$testCD19 = exec("cut -f 2 ".$panelFile."|grep CD19");
	$TLS = ($testCD20=='CD20') ? "CD20" : (($testCD19=='CD19')?"CD19":"");
	if (file_exists($dir."/annotations.json")) {
		$annots = formatAnnotations($dir."/annotations.json");
		if (count($annots['exclusion']) > 20) {
			file_put_contents($dir."/exclusion.csv",implode("\n",$annots['exclusion']));
		}
		if (count($annots['ROI']) > 20) {
			file_put_contents($dir."/ROI.csv",implode("\n",$annots['ROI']));
		}
	}
	$f = '';
	if (file_exists(__DIR__."/../../docker-compose.yml")){
		$f = " -f ".realpath(__DIR__."/../../docker-compose.yml")." ";
	}
	$cmd = 'docker compose '.$f.' run --rm ifquant-engine run_analysis.sh \\';
	$cmd .= PHP_EOL.'  --nprocesses='.NPROCESSES.' \\';
	if (defined("TMPDIR") && TMPDIR && file_exists(TMPDIR)) $cmd .= PHP_EOL.'  --tmpdir='.TMPDIR.' \\';
	$cmd .= PHP_EOL.'  --path='.dirname($dir)." \\";
	// $cmd .= PHP_EOL.'  --channel-thresholding='.$dir."/metadata_channel_thresholding.txt \\";
	$cmd .= PHP_EOL.'  --image='.$qptiff." \\";
	if ($TLS && $withReport){
		$cmd .= PHP_EOL."  --TLS \\";
		if ($TLS == 'CD20' && $tumorMarker){
			$cmd .= PHP_EOL."  --TLS-phenotype='CD20+,".$tumorMarker."-' \\";
		}
		else if ($TLS == 'CD19' && $tumorMarker){
			$cmd .= PHP_EOL."  --TLS-phenotype='CD19+,".$tumorMarker."-' \\";
		}
		else if ($TLS == 'CD20' && !$tumorMarker){
			$cmd .= PHP_EOL."  --TLS-phenotype='CD20+' \\";
		}
		else if ($TLS == 'CD19' && !$tumorMarker){
			$cmd .= PHP_EOL."  --TLS-phenotype='CD19+' \\";
		}
	}
	if (file_exists($dir."/exclusion.csv")){
		$cmd .= PHP_EOL.'  --excluded-regions='.$dir."/exclusion.csv \\";
	}
	if (file_exists($dir."/ROI.csv")){
		$cmd .= PHP_EOL.'  --ROI='.$dir."/ROI.csv \\";
	}
	if (!$withReport){
		$cmd .= PHP_EOL."  --no-report \\";
	}
	if (file_exists(TOOLS_PATH."/createCellDB.php") && is_readable(TOOLS_PATH."/createCellDB.php")){
		$cmd .= PHP_EOL." && docker compose ".$f." run --rm ifquant-app php /var/www/tools/createCellDB.php -s ".$sample." -f \\";
	}
	$cmd .= PHP_EOL." && docker compose ".$f." run --rm ifquant-engine rm -f ".DATA_PATH."/analyses/".$sample."/PROCESSING"." ".$dir."/run_analysis.sh \\";
	$cmd .= PHP_EOL." && docker compose ".$f." run --rm ifquant-engine chmod -R 777 ".DATA_PATH."/analyses/".$sample;
	file_put_contents($dir."/run_analysis.sh",$cmd);
	chmod($dir."/run_analysis.sh",0777);
	touch(DATA_PATH."/analyses/".$sample."/PROCESSING");
	return $cmd;
}

function getIFQuantReport ($sample_id, $file) {
	
	$file = DATA_PATH."/analyses/".$sample_id."/report/".$file;
	if (!file_exists($file)) {
		throw new Exception("ERROR: unknown file", 404);
	}
	return array(
		"filename" => basename($file),
		"file" => $file
	);
}

function deleteIFQuant ($sample_id,$deleteQptiff){
	if (!file_exists(DATA_PATH."/analyses/".$sample_id)){
		throw new Exception("ERROR: analysis unknown", 404);
	}
	$param = array("sample_id:".$sample_id,"delete_qptiff:".(($deleteQptiff)?"Y":"N"));
	file_put_contents(IFQUANT_DROPBOX."delete_".$sample_id.".txt",implode("\n",$param).PHP_EOL);
	return $sample_id;
}

function deleteReport ($sample_id){	
	if (!$sample_id) {
		throw new Exception("ERROR: empty sample", 404);
	}
	$dir = DATA_PATH."/analyses/".$sample_id."/report";
	if (!file_exists($dir)){
		throw new Exception("ERROR: no report for this sample", 404);
	}
	exec("rm -rf ".$dir);
	return $dir;
}

// get info from failed analyses.
function getSlide($sample_id, $qptiff){
	$return = array(
		"sample_id" => $sample_id,
		"status" => NULL,
		"message" => NULL,
		"segmentation" => array(),
		"ycoords" => array(
			"min" => -1,
			"max" => -1
		),
		"image" => array(
			"height" => 0,
			"width" => 0,
			"url" => NULL,
			"original_name" => NULL
		),
		"otherImages" => array(),
		"info" => array()
	);
	$return['image']['original_name'] = DB::queryFirstField("SELECT original_name from files inner join extract_id_view on files.extract_id = extract_id_view.extract_id where extract_id_view.sample_id = %s and files.name like %ss and files.is_deleted = 'N' and files.mime_type = 'image/tiff' order by files.file_id desc limit 1;",$sample_id,$qptiff);
	$otherImages = DB::queryFirstColumn("SELECT substring_index(files.name,'/',-1) as qptiff from files inner join extract_id_view on files.extract_id = extract_id_view.extract_id where extract_id_view.sample_id = %s and files.name not like %ss and files.is_deleted = 'N' and files.mime_type = 'image/tiff'",$sample_id,$qptiff);
	$return['info'] = DB::queryFirstRow("SELECT * from ifquant_sample_info_materialized where sample_id = %s",$sample_id);
	$return['tracking'] = DB::queryFirstRow("SELECT
	chuv_slides.chuv_slide_id,
	chuv_slides.reception_date,
	chuv_slides.reception_status1 as reception_status,
	chuv_slides.reception_comment1 as reception_comment,
	chuv_slides.staining_date as staining_date,
	chuv_slides.staining_status1 as staining_status,
	chuv_slides.staining_comment1 as staining_comment,
	chuv_slides.scanning_date as scanning_date,
	chuv_slides.scanning_status1 as scanning_status,
	chuv_slides.scanning_comment1 as scanning_comment
FROM
	chuv_slides
	INNER JOIN extract_id_view ON chuv_slides.extract_id1 = extract_id_view.extract_id
WHERE
	extract_id_view.sample_id = %s
union 
SELECT
	chuv_slides.chuv_slide_id,
	chuv_slides.reception_date,
	chuv_slides.reception_status2 as reception_status,
	chuv_slides.reception_comment2 as reception_comment,
	chuv_slides.staining_date as staining_date,
	chuv_slides.staining_status2 as staining_status,
	chuv_slides.staining_comment2 as staining_comment,
	chuv_slides.scanning_date as scanning_date,
	chuv_slides.scanning_status2 as scanning_status,
	chuv_slides.scanning_comment2 as scanning_comment
FROM
	chuv_slides
	INNER JOIN extract_id_view ON chuv_slides.extract_id2 = extract_id_view.extract_id
WHERE
	extract_id_view.sample_id = %s;",$sample_id,$sample_id);
	if (!$return['tracking']) {
		$return['tracking'] = DB::queryFirstRow("SELECT `reception_#_slide_id`, reception_date, reception_status, reception_comment,  staining_date, staining_status, staining_comment, scanning_date, scanning_status, scanning_comment from tracking_view where sample_sample_id = %s",$sample_id);	
	}
	$qptiffDir = str_replace(array(".qptiff",'.ome.tiff','.ome.tif'),"",$qptiff);
	$dir = '';
	$dirs = glob(DATA_PATH."/analyses/analysis_failed/".$qptiffDir."*",GLOB_ONLYDIR);
	if (count($dirs) == 1) $dir = $dirs[0];
	if (!$dir) {
		throw new Exception("ERROR: unable to find data directory for sample ".$qptiffDir, 404);
	}
	foreach($otherImages as $otherImage){
		$otherDirs = glob(DATA_PATH."/analyses/analysis_failed/".$otherImage."*",GLOB_ONLYDIR);	
		if (count($otherDirs) == 1) {
			$return['otherImages'] = $otherImage;
		}
	}
	
	
	
	if (!file_exists($dir."/sample_selection/sample_selection.txt")) {
		$return['status'] = "ERROR";
		$return['message'] = "No sample selection file identified";
	}
	else if (!file_exists($dir."/sample_selection/sample_selection.log")) {
		$return['status'] = "ERROR";
		$return['message'] = "No sample selection log file identified";
	}
	else if (!file_exists($dir."/sample_selection/image.png")){
		$return['status'] = "ERROR";
		$return['message'] = "No image identified";
	}
	else {
		$return['status'] = "SEGMENTATION";
		$return['message'] = "";
		if (count($return['otherImages'])) $return['message'] = count($return['otherImages'])." other QPTIFF available for this sample";
		$log = exec('grep "Selected region start:end (fraction of image height):" '.$dir."/sample_selection/sample_selection.log");
		if ($log) {
			$parts = explode(":",$log);
			$return['ycoords']['max'] = array_pop($parts);
			$return['ycoords']['min'] = array_pop($parts);
			$return['ycoords']['max'] = floatval(trim($return['ycoords']['max']));
			$return['ycoords']['min'] = floatval(trim($return['ycoords']['min']));
		}
		$seg_rows = file($dir."/sample_selection/sample_selection.txt",FILE_IGNORE_NEW_LINES);
		$header = array_shift($seg_rows);
		$headers = explode(",",$header);
		foreach($seg_rows as $seg_row) {
			$cols = explode(",",$seg_row);
			if (count($cols) == count($headers)) {
				$data = array_combine($headers,$cols);
				if (!isset($return['segmenation'][$data['id']])) {
					$return['segmenation'][$data['id']] = array(
						'xmin' => -1,
						'ymin' => -1,
						'xmax' => -1,
						'ymax' => -1
					);
				}
				if ($return['segmenation'][$data['id']]['xmin'] == -1 || $return['segmenation'][$data['id']]['xmin'] > $data['x']) {
					$return['segmenation'][$data['id']]['xmin'] = +$data['x'];
				}
				if ($return['segmenation'][$data['id']]['xmax'] == -1 || $return['segmenation'][$data['id']]['xmax'] < $data['x']) {
					$return['segmenation'][$data['id']]['xmax'] = +$data['x'];
				}
				if ($return['segmenation'][$data['id']]['ymin'] == -1 || $return['segmenation'][$data['id']]['ymin'] > $data['x']) {
					$return['segmenation'][$data['id']]['ymin'] = +$data['y'];
				}
				if ($return['segmenation'][$data['id']]['ymax'] == -1 || $return['segmenation'][$data['id']]['ymax'] < $data['x']) {
					$return['segmenation'][$data['id']]['ymax'] = +$data['y'];
				}
			}
		}
		$path = $dir."/sample_selection/image.png";
		$type = pathinfo($path, PATHINFO_EXTENSION);
		$data = file_get_contents($path);
		list($width, $height, $type, $attr) = getimagesize($path);
		$return['image']['width'] = $width;
		$return['image']['height'] = $height;
		$return['image']['url'] = 'data:image/' . $type . ';base64,' . base64_encode($data);
	}
	return $return;
}

function registerSlideAnalysis($sample,$params) {
	
	$ifquant = DB::queryFirstRow("SELECT extract_id_view.sample_id, analyses.analysis_id, extract_id_view.extract_id from extract_id_view inner join extract_analyses on extract_id_view.extract_id = extract_analyses.extract_id inner join analyses on extract_analyses.analysis_id = analyses.analysis_id and analyses.status in ('FAILED','CURATION') and analyses.protocol = 'IFQuant' where sample_id = %s order by analyses.analysis_id desc limit 1",$sample);
	if (!$ifquant['sample_id']) {
		throw new Exception("ERROR: ifquant sample is unknown", 404);
	}
	$run = array();
	foreach($ifquant as $key => $value) {
		$run[] = $key."\t".$value;
	}
	$run[]="sample-selection-range\t".round(+$params['ycoords']['min'],2).":".round(+$params['ycoords']['max'],2);
	file_put_contents(IFQUANT_DROPBOX."run_".$params['extract_id'].".txt",implode("\n",$run));
	$formatted_metadata = [];
	foreach($run as $row) {
		$cols = explode("\t",$row);
		if (count($cols) === 2) {
			$formatted_metadata[$cols[0]] = $cols[1];
		}
	}
	return $formatted_metadata;
}


function deleteSlide($extract_id){
	
	$analysis_id = DB::queryFirstField("SELECT analyses.analysis_id from analyses inner join extract_analyses on analyses.analysis_id = extract_analyses.analysis_id where analyses.protocol = 'IFQuant' and analyses.status in ('PEN','RUN','DONE') and extract_analyses.extract_id = %i",$extract_id);
	if ($analysis_id) {
		throw new Exception("ERROR: unable to delete this sample. An IFQuant analysis is associated.", 404);
		return false;
	}
	$db_id = DB::queryFirstField("SELECT extract_id from extracts where extract_id = %i",$extract_id);
	if (!$db_id){
		throw new Exception("ERROR: extract is unknown", 404);
		return false;
	}
	DB::update("extracts",array("is_na" => 'Y'),"extract_id = %i",$extract_id);
	$status = DB::queryFirstField("SELECT is_na from extracts where extract_id = %i",$extract_id);
	return ($status == 'Y');
}

function deleteSampleFromQptiff($extract_id, $file_id){
	$file = DB::queryFirstRow("SELECT name, original_name, file_id from files where file_id = %i and is_deleted = 'N'",$file_id);
	if (!$file){
		throw new Exception("ERROR: file is unknown", 404);
	}
	$filename = $file['name'];
	$analysis_id = DB::queryFirstField("SELECT analyses.analysis_id from analyses inner join extract_analyses on analyses.analysis_id = extract_analyses.analysis_id where analyses.protocol = 'IFQuant' and analyses.status in ('PEN','RUN','DONE') and extract_analyses.extract_id = %i and analyses.cmd like %s",$extract_id,basename($filename));
	if ($analysis_id) {
		throw new Exception("ERROR: unable to delete this sample. An IFQuant analysis is associated.", 404);
		return false;
	}
	$extract = DB::queryFirstRow("SELECT extract_id, fs_data_path  from extract_id_view where extract_id = %i",$extract_id);
	if (!$extract){
		throw new Exception("ERROR: extract is unknown", 404);
		return false;
	}
	$DATA_PATH = constant($extract['fs_data_path']."_PATH");
	DB::update("files",array("is_deleted" => "Y", "comment" => "Extract ".$extract_id." not in this image"),"file_id = %i",$file_id);
	$analysis_id = DB::queryFirstField("SELECT analyses.analysis_id from analyses inner join extract_analyses on analyses.analysis_id = extract_analyses.analysis_id where analyses.protocol = 'IFQuant' and analyses.status in ('FAILED') and extract_analyses.extract_id = %i and analyses.cmd like %s",$extract_id,basename($filename));
	if ($analysis_id) {
		DB::update("analyses",array("status" => "DELETED","publication_date" => NULL,'publication_status' => NULL),"analysis_id = %i",$analysis_id);
	}
	touch(IFQUANT_DROPBOX."/deleteSampleFromQptiff_".$file_id);
	
	return $file_id;
	
}

function getIfquantDensitiesChannels($sample_name, $cell_type) {
	$metadata_file = DATA_PATH."/analyses/".$sample_name."/data/metadata_panel.txt";
	if (!file_exists($metadata_file)) {
		throw new Exception("ERROR: cannot read metadata file", 404);
	}
	$metadata_rows = file($metadata_file,FILE_IGNORE_NEW_LINES);
	$metadata = array();
	array_shift($metadata_rows);
	foreach($metadata_rows as $metadata_row) {
		$cols = explode("\t",$metadata_row);
		$metadata[$cols[1]] = $cols[0];
	}
	if (!isset($metadata[$cell_type])) {
		throw new Exception("ERROR: cannot find ".$cell_type." in this sample", 404);
	}

	return $metadata;
}

function getDensityData ($sample_name, $channelX = 1,$channelY = 2) {
	$dir = DATA_PATH."/analyses/".$sample_name."/score_density";
	if (!file_exists($dir)) {
		throw new Exception("ERROR: sample cannot be found", 404);
	}
	$data = array();
	$path = $dir."/metadata_".$channelX."_".$channelY.".txt";
	if (file_exists($path)) {
		$rows = file($path,FILE_IGNORE_NEW_LINES);
		foreach($rows as $row){
			if (strpos($row,"=") !== FALSE) {
				list ($key,$value) = explode("=",$row);
				$data[str_replace(".","_",$key)] = $value;
			}
		}
		return $data;
	}
	$path = $dir."/metadata_".$channelY."_".$channelX.".txt";
	if (file_exists($path)) {
		$rows = file($path,FILE_IGNORE_NEW_LINES);
		foreach($rows as $row){
			if (strpos($row,"=") !== FALSE) {
				list ($key,$value) = explode("=",$row);
				$key = str_replace(".x",".z",$key);
				$key = str_replace(".y",".x",$key);
				$key = str_replace(".z",".y",$key);
				$data[str_replace(".","_",$key)] = $value;
			}
		}
		return $data;
	}
}

function getDensityPlot ($sample_name, $channelX = 1,$channelY = 2) {
	$dir = DATA_PATH."/analyses/".$sample_name."/score_density";
	if (!file_exists($dir)) {
		throw new Exception("ERROR: sample cannot be found", 404);
	}
	$path = $dir."/density_".$channelX."_".$channelY.".png";
	if (file_exists($path)) {
		$type = pathinfo($path, PATHINFO_EXTENSION);
		$file = fopen($path, "rb");
		$imagedata = fread($file, filesize($path));
		fclose($file);
		return $imagedata;
	}
	$path = $dir."/density_".$channelY."_".$channelX.".png";
	if (file_exists($path)) {
		$tmp = dirname($path)."/".str_replace(".png","_tmp.png",basename($path));
		$tmp = tempnam("/tmp","IFQ");
		if (file_exists($tmp)) unlink($tmp);
		exec("convert -transverse ".$path." ".$tmp);
		if (file_exists($tmp)){
			$type = pathinfo($tmp, PATHINFO_EXTENSION);
			$file = fopen($tmp, "rb");
			$imagedata = fread($file, filesize($path));
			fclose($file);
			if (file_exists($tmp)) unlink($tmp);
			return $imagedata;
		}
	}
	throw new Exception("Image not found: ".$path, 404);

}

function getStats($sample,$params) {
	$panelFile = DATA_PATH."/analyses/".$sample."/data/metadata_panel.txt";
	if (!file_exists($panelFile)) {
		throw new Exception("ERROR: sample unknwown: ".basename($panelFile), 404);
		return false;
	}
	$thresholdFile = DATA_PATH."/analyses/".$sample."/data/analysis/metadata_channel_thresholding.txt";
	if (!file_exists($thresholdFile)) {
		throw new Exception("ERROR: sample unknwown: ".basename($thresholdFile), 404);
		return false;
	}
	$file = DATA_PATH."/analyses/".$sample."/cells.db";
	if (!file_exists($file)) {
		throw new Exception("ERROR: sample unknwown: ".basename($file), 404);
		return false;
	}
	$thresholds = array();
	
	$dataPanel = file($panelFile,FILE_IGNORE_NEW_LINES);
	$headerPanel = array_shift($dataPanel);
	$headersPanel = explode("\t",$headerPanel);
	$nameIdx = array_search('name',$headersPanel);
	foreach($dataPanel as $idx => $row) {
		$cols = explode("\t",$row);
		$marker = $cols[$nameIdx];
		$thresholds[$marker] = 0;		
	}
	$data = file($thresholdFile,FILE_IGNORE_NEW_LINES);
	$header = array_shift($data);
	$headers = explode("\t",$header);
	$nameIdx = array_search('name',$headers);
	$thresIdx = array_search('threshold',$headers);
	if ($nameIdx === FALSE || $thresIdx === FALSE) {
		throw new Exception("ERROR: threshold file cannot be parsed", 1);
	}
	$results = array("ifquant" => array());
	$cmds = array();
	foreach($data as $idx => $row) {
		$cols = explode("\t",$row);
		$marker = $cols[$nameIdx];
		$threshold = ($marker == $params['marker']) ? floatval($params['threshold']) : floatval($cols[$thresIdx]);
		$thresholds[$marker] = $threshold;
	}
	
	$readFromDB = true;
	$nbTrials = 0;
	while($nbTrials < 5){
		$nbTrials++;
		usleep(rand(10,100));
		$db = new SQLite3(DATA_PATH."/analyses/".$sample."/cells.db");
		if ($db) {
			break;
		}
	}
	if (!$db) {
		return;
	}


	$db->busyTimeout(5000);
	// WAL mode has better control over concurrency.
	// Source: https://www.sqlite.org/wal.html
	$db->exec('PRAGMA journal_mode = WAL');
	$db->exec('PRAGMA synchronous = normal');
	$db->exec('PRAGMA temp_store = memory');
	$db->exec('PRAGMA mmap_size = 30000000000');

	if (!$db) {
		throw new Exception("ERROR: unable to open cells.db file", 404);
	}
	
	
	foreach($thresholds as $marker => $threshold) {
		$results['ifquant'][$marker] = 0;
		$where = " and ".strtolower($marker)." >= ".$threshold;
		$q = "SELECT count(*) as nb from cells where x >= ".($params['x']<0?0:$params['x'])." and x <= ".($params['x']+$params['width'])." and y >= ".($params['y']<0?0:$params['y'])." and y <= ".($params['y']+$params['height']).$where;
		$total = intval($db->querySingle($q));
		$results['ifquant'][$marker] = +$total;
	}
	return $results;

}

function setTLS($params) {	
	if (!isset($params['sample_id'])) {
		throw new Exception("IMMUcan ID not provided", 404);
	}
	if (!isset($params['tls'])){
		throw new Exception("No TLS value provided", 404);
	}
	$extract_id = DB::queryFirstField("SELECT extract_id from extract_id_view where sample_id = %s",$params['sample_id']);
	if (!$extract_id) {
		throw new Exception("ERROR: Sample is unknown", 404);
	}
	if (!is_numeric($params['tls'])){
		throw new Exception("ERROR: tls value is not valid", 404);
	}
	DB::update("extracts",array("tls" => +$params['tls']),"extract_id = %i",$extract_id);
	return DB::queryFirstField("SELECT tls from extracts where extract_id = %i",$extract_id);
}

?>
