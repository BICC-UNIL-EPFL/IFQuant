<?php
function formatAnnotations($roi_files,$annotation_file){
	function initObject () {
		$object = array(
	  "type" => "path",
	  "version" => "4.6.0",
	  "originX" => "left",
	  "originY" => "top",
	  "left" => 0,
	  "top" => 0,
	  "width" => 0,
	  "height" => 0,
		"path" => array(),
	  "fill" => "",
	  "stroke" => "#0F0",
	  "strokeWidth" => 10,
	  "strokeDashArray" =>null,
	  "strokeLineCap" => "round",
	  "strokeDashOffset" => 0,
	  "strokeLineJoin" => "round",
	  "strokeUniform" =>false,
	  "strokeMiterLimit" => 10,
	  "scaleX" => 1,
	  "scaleY" => 1,
	  "angle" => 0,
	  "flipX" =>false,
	  "flipY" =>false,
	  "opacity" => 1,
	  "shadow" =>null,
	  "visible" => true,
	  "backgroundColor" =>"",
	  "fillRule" => "nonzero",
	  "paintFirst" => "fill",
	  "globalCompositeOperation" => "source-over",
	  "skewX" => 0,
	  "skewY" => 0,
		"title" => "",
		"index" => 0
	);
		return $object;
	}
	
	
	if (file_exists($annotation_file)){
		$bkp_file = str_replace(".json","_bkp.json",$annotation_file);
		if (!file_exists($bkp_file)){
			copy($annotation_file,$bkp_file);
		}
		$json = file_get_contents($bkp_file);
		$data = json_decode($json,true);
	}
	else {
		$data = array("version" => "4.6.0","objects" => array());
	}
	$ROIs = array();
	foreach($roi_files as $type => $roi_file){
		$rows = file($roi_file,FILE_IGNORE_NEW_LINES);
		$header = array_shift($rows);
		$headers = str_getcsv($header);
		$ROI = array("title" => "","type" => $type,"coordinates" => array());
		while(count($rows)){
			$row = array_shift($rows);
			$cols = str_getcsv($row);
			if (count($headers) == count($cols)){
				$roi_data = array_combine($headers,$cols);
				if (!$ROI['title']){
					$ROI = array("title" => $roi_data['label'],"type" => $type,"coordinates" => array());
				}
				elseif ($ROI['title'] && $ROI['title'] != $roi_data['label'] && count($ROI['coordinates'])){
					$ROIs[] = $ROI;
					$ROI = array("title" => $roi_data['label'],"type" => $type,"coordinates" => array());
				}
				$ROI['coordinates'][] = array(+$roi_data['x'],+$roi_data['y']);
			}
		}
		if ($ROI['title'] && count($ROI['coordinates'])){
			$ROIs[] = $ROI;
		}
	}
	foreach($ROIs as $ROIidx => $ROI){
		$idx = count($data['objects']);
		$object = initObject();
		$object['stroke'] = ($ROI['type']=='exclusion') ? "#F00" : "#0F0";
		$object['fill'] = ($ROI['type']=='exclusion') ? "rgba(16,0,0,0.8)" : "";
		$object['index'] = $idx;
		$object['title'] = $ROI['title'];
		$object['path'] = array();
		$minX = 1000000000;
		$minY = 1000000000;
		$maxX = -1000000000;
		$maxY = -1000000000;
		foreach($ROI['coordinates'] as $cidx => $coord){
			if ($coord[0] < $minX) $minX = $coord[0];
			if ($coord[1] < $minY) $minY = $coord[1];
			if ($coord[0] > $maxX) $maxX = $coord[0];
			if ($coord[1] > $maxY) $maxY = $coord[1];
			$pathCat = (count($object['path'])) ? "L" : "M";
			$object['path'][] = array($pathCat,+$coord[0],$coord[1]);
		}
		$object['height'] = (+$maxY-$minY);
		$object['width'] = (+$maxX-$minX);
		$object['left'] = +$minX-$object['strokeWidth']/2;
		$object['top'] = +$minY-$object['strokeWidth']/2;
		$objIdx = -1;
		foreach($data['objects'] as $i => $o){
			if ($o['title'] == $object['title']){
				$objIdx = $i;
				$data['objects'][$i] = $object;
			}
		}
		if ($objIdx < 0){
			$data['objects'][] = $object;
		}
	}
	$json = json_encode($data);
	file_put_contents($annotation_file,$json);
	return $annotation_file;
	
}

$options = getopt("r:x:o:hv");

function print_usage(){
	fwrite(STDOUT,"usage: php ".basename(__FILE__)." [-r <ROI.csv>] [-x <excluded_regions.csv] [-o <annotations.json>] [-h] [-v]".PHP_EOL);
	fwrite(STDOUT,"  -r : ROI csv file. Default: ROI.csv".PHP_EOL);
	fwrite(STDOUT,"  -x : excluded_regions csv file. Default: excluded_regions.csv".PHP_EOL);
	fwrite(STDOUT,"  -o : output json file. Default: annotations.json".PHP_EOL);
	fwrite(STDOUT,"  -v : verbose".PHP_EOL);
	fwrite(STDOUT,"  -h : this help".PHP_EOL);
	return 0;
}

$ROI_file = isset($options['r']) ? $options['r'] : "ROI.csv";
$exclusion_file = isset($options['x']) ? $options['x'] : "excluded_regions.csv";
$annotation_file = isset($options['o']) ? $options['o'] : "annotations.json";
$verbose = isset($options['v']);
$help = isset($options['h']);
if (!file_exists($ROI_file) || !is_readable($ROI_file)) {
	$ROI_file = "";
}
if (!file_exists($exclusion_file) || !is_readable($exclusion_file)){
	$exclusion_file = "";
}

$files = array("ROI" => $ROI_file,"exclusion" => $exclusion_file);

if ((!$ROI_file && !$exclusion_file) || $help){
	print_usage();
	exit(0);
}
try {
	$file = formatAnnotations($files,$annotation_file);
	fwrite(STDOUT,$file.PHP_EOL);
	exit(0);
} catch (Exception $e) {
	fwrite(STDERR,$e->getMessage.PHP_EOL);
	exit(1);
}
?>