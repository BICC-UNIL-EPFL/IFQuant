#!/usr/bin/php
<?php
require __DIR__."/../conf/config.php";
function createDB($file,$verbose,$force) {
	
	$dir = dirname($file);
	$ignores = array("id","phenotype");
	chdir($dir);
	if (file_exists('cells.db') && !$force){
		if ($verbose) fwrite(STDOUT," ".basename($dir)." already exists. SKIPPING.".PHP_EOL);
		return "SKIP";
	}

	if (file_exists("cells.db")) unlink("cells.db");
	// $memFile = tempnam("/dev/shm","IFQcells");
	$memFile = tempnam(sys_get_temp_dir(),"IFQcells");
	$db = new Sqlite3($memFile);


	// create cells

	$header = exec("head -1 ".$file);
	
	$headers = explode("\t",$header);
	$dbcols = array("id","x","y","type");
	$typeFound = false;
	$cols = array();
	for($i = 0; $i < count($headers); $i++){
		$ps = explode(".",$headers[$i]);
		$h = strtolower(array_pop($ps));
		if (in_array($h,$dbcols)) {
			if ($h == "type") $typeFound = true;
			$cols[$h] = $i;
		}
		if ($typeFound){
			$cols[$h] = $i;
		}
	}
	$db->query('PRAGMA JOURNAL_MODE(MEMORY);');
	$query = "CREATE TABLE cells(";
	$cmds = array();
	$cutcmd = "cut -f ";
	$cutcmds = array();
	foreach($cols as $col => $idx){
		$type = 'TEXT';
		if (+$idx < 5) $type = 'INTEGER';
		if ($col != 'type') $type = 'NUMERIC';
		$cmds[] = "`".$col."` ".$type;
		$cutcmds[] = $idx+1;
	}
	$query .= implode(", ",$cmds).")";
	$db->query($query);
	$cmd = "cut -f ".implode(",",$cutcmds)." ".$file." | tail -n +2 > cells.tsv";
	exec($cmd);
	$dbscript = ".mode tabs".PHP_EOL;
	$dbscript .= ".import cells.tsv cells".PHP_EOL;
	if (file_exists("script.sqlite")) unlink("script.sqlite");
	file_put_contents("script.sqlite",$dbscript);
	$cmd = 'sqlite3 '.$memFile.' < script.sqlite';
	exec($cmd);
	unlink("script.sqlite");
	unlink("cells.tsv");	
	$nb = $db->querySingle("SELECT count(*) from cells");
	$r = $db->query('PRAGMA table_info(cells);');
	while ($s = $r->fetchArray()) {
		$field = $s['name'];
		if (in_array($field,$ignores)) continue;
		$db->exec("create index `".$field."_idx` on cells(`".$field."`)" );
	}

	// create thesholds
	$file = $dir."/data/analysis/metadata_channel_thresholding.txt";
	$header = exec("head -1 ".$file);
	
	$headers = explode("\t",$header);
	// print_r($headers);
	$dbcols = array("channel","name","threshold");
	$cols = array();
	for($i = 0; $i < count($headers); $i++){
		$h = $headers[$i];
		if (in_array($h,$dbcols)) {
			$cols[$h] = $i;
		}
	}
	$query = "CREATE TABLE thresholds(";
	$cmds = array();
	$cutcmd = "cut -f ";
	$cutcmds = array();
	foreach($cols as $col => $idx){
		$type = 'TEXT';
		if ($col == 'channel') $type = 'INTEGER';
		if ($col == 'threshold') $type = 'NUMERIC';
		$cmds[] = $col." ".$type;
		$cutcmds[] = $idx+1;
	}
	$query .= implode(", ",$cmds).")";
	$db->query($query);
	$cmd = "cut -f ".implode(",",$cutcmds)." ".$file." | tail -n +2 > thresholds.tsv";
	exec($cmd);
	$dbscript = ".mode tabs".PHP_EOL;
	$dbscript .= ".import thresholds.tsv thresholds".PHP_EOL;
	if (file_exists("script.sqlite")) unlink("script.sqlite");
	file_put_contents("script.sqlite",$dbscript);
	$cmd = 'sqlite3 '.$memFile.' < script.sqlite';
	exec($cmd);
	$db->query("alter table cells add column phenotype TEXT");
	unlink("script.sqlite");
	unlink("thresholds.tsv");	
	$channels = array();
	$results = $db->query("SELECT channel, name from thresholds");
	while ($row = $results->fetchArray()) {
		$channels[$row['channel']] = $row['name'];
	}
	$db->query("update thresholds set name = lower(name)");
	// create phenotypes
	$file = $dir."/data/phenotypes.txt";
	$header = exec("head -1 ".$file);
	
	$headers = explode("\t",$header);
	$dbcols = array("label","channel_1","channel_2","channel_3","channel_4","channel_5","channel_6");
	$cols = array();
	for($i = 0; $i < count($headers); $i++){
		$h = $headers[$i];
		$title = $h;
		if (strpos($h,'channel_') !== FALSE) {
			$channel_nb = str_replace("channel_","",$h);
			$title = (isset($channels[$channel_nb])) ? strtolower($channels[$channel_nb]) : $h;
		}
		if (in_array($h,$dbcols)) {
			$cols[$title] = $i;
		}
	}	
	$query = "CREATE TABLE phenotypes(";
	$cmds = array();
	$cutcmd = "cut -f ";
	$cutcmds = array();
	foreach($cols as $col => $idx){
		$type = 'TEXT';
		$cmds[] = "`".$col."` ".$type;
		$cutcmds[] = $idx+1;
	}
	$query .= implode(", ",$cmds).")";
	$db->query($query);
	$db->close();
	$cmd = "cut -f ".implode(",",$cutcmds)." ".$file." | tail -n +2 > phenotypes.tsv";
	exec($cmd);
	$dbscript = ".mode tabs".PHP_EOL;
	$dbscript .= ".import phenotypes.tsv phenotypes".PHP_EOL;
	if (file_exists("script.sqlite")) unlink("script.sqlite");
	file_put_contents("script.sqlite",$dbscript);
	$cmd = 'sqlite3 '.$memFile.' < script.sqlite';
	exec($cmd);
	unlink("script.sqlite");
	unlink("phenotypes.tsv");	

	if($verbose) fwrite(STDOUT,$dir."/cells.db created with ".$nb." cells".PHP_EOL);
	rename($memFile,$dir.'/cells.db');
	chmod($dir."/cells.db",0777);
	return 'CREATE';
}

function cellPhenotypes($file,$verbose,$force){
	$dir = dirname($file);
	chdir($dir);
	if (!file_exists('cells.db')){
		if($verbose) fwrite(STDOUT," ".basename($dir)." does not exist. SKIPPING.".PHP_EOL);
		return false;
	}
	// $memFile = tempnam("/dev/shm","IFQcells");
	$memFile = tempnam(sys_get_temp_dir(),"IFQcells");
	copy('cells.db',$memFile);
	$db = new SQLite3($memFile);
	
	$phenotypes = array();
	$thresholds = array();
	$r = $db->query("SELECT * from thresholds")	;
	while($row = $r->fetchArray()){
		$thresholds[$row['name']] = $row['threshold'];
	}
	$db->query("update cells set phenotype = null");
	$r = $db->query("SELECT * from phenotypes")	;
	while($row = $r->fetchArray()){
		$cmd = "update cells set phenotype = '".$row['label']."' where ";
		$cmds = array();
		foreach($thresholds as $name => $threshold){
			if ($row[$name] == '+') $cmds[] = "`".$name."` >= ".$threshold;
			elseif ($row[$name] == '-') $cmds[] = "`".$name."` < ".$threshold;
		}
		$cmd .= implode(" and ",$cmds);
		$db->query($cmd);
	}
	$other_phenotypes = array();
	// $r = $db->query("SELECT * from cells where phenotype is null");
	// $c = 0;
	// $other_phenotypes = array();
	// while($row = $r->fetchArray()){
	// 	$cellphenotype = "";
	// 	foreach($thresholds as $name => $threshold){
	// 		$cellphenotype .= strtoupper($name).((+$row[$name] < +$threshold) ? "-" : "+");
	// 	}
	// 	if (!isset($other_phenotypes[$cellphenotype])) $other_phenotypes[$cellphenotype] = 0;
	// 	$other_phenotypes[$cellphenotype]++;
	// 	// $db->query("update cells set phenotype ='".$cellphenotype."' where id = ".$row['id']);
	// }
	$db->close();
	rename($memFile,$dir.'/cells.db');
	chmod($dir."/cells.db",0777);	
	arsort($other_phenotypes);
	return $other_phenotypes;
}

function print_usage () {
	fwrite(STDOUT,"php ".basename(__FILE__)." -s <samples> (-h) (-v) (-f)".PHP_EOL);
	fwrite(STDOUT,"  -s <samples>: Name of the samples. If empty, process all samples".PHP_EOL);
	fwrite(STDOUT,"  -f          : Force. Overwrite existing sqlite DB".PHP_EOL);
	fwrite(STDOUT,"  -v          : Verbose".PHP_EOL);
	fwrite(STDOUT,"  -h          : Print this help and exit".PHP_EOL);
}


$options = getopt("s:hfv");

$sample = (isset($options['s'])) ? $options['s'] : NULL;
$help = isset($options['h']);
$force = isset($options['f']);
$verbose = isset($options['v']);
if ($help){
	print_usage();
	exit(0);
}

try {
	$samples = ($sample) ? explode(",",$sample) : array('*');
	foreach($samples as $sample){
		$files = glob(DATA_PATH."/analyses/".$sample."/cells_properties_pixels.txt");
		foreach($files as $file){
			$dir = dirname($file);
			if (file_exists($dir."/DB_RUNNING")){
				if (filemtime($dir."/DB_RUNNING") < (time()-3600)){
					unlink($dir."/DB_RUNNING");
				}
				else{
					continue;
				}
			}
			touch($dir."/DB_RUNNING");
		}
	}
	foreach($samples as $sample){
		$files = glob(DATA_PATH."/analyses/".$sample."/cells_properties_pixels.txt");
		foreach($files as $file){
			$dir = dirname($file);
			$action = createDB($file,$verbose,$force);
			if ($action == 'CREATE'){
				cellPhenotypes($file,$verbose,$force);	
			}
			if (file_exists($dir."/DB_RUNNING")){
				unlink($dir."/DB_RUNNING");	
			}
		}		
	}
	exit(0);
} catch (Exception $e) {
	fwrite(STDERR,$e->getMessage().PHP_EOL);
	exit(1);
}

?>