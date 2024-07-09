<?php
/************************ LICENCE ***************************
*     This file is part of <ViKM Vital-IT Knowledge Management web application>
*     Copyright (C) <2016> SIB Swiss Institute of Bioinformatics
*
*     This program is free software: you can redistribute it and/or modify
*     it under the terms of the GNU Affero General Public License as
*     published by the Free Software Foundation, either version 3 of the
*     License, or (at your option) any later version.
*
*     This program is distributed in the hope that it will be useful,
*     but WITHOUT ANY WARRANTY; without even the implied warranty of
*     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*     GNU Affero General Public License for more details.
*
*     You should have received a copy of the GNU Affero General Public License
*    along with this program.  If not, see <http://www.gnu.org/licenses/>
*
*****************************************************************/
use \Psr\Http\Message\ServerRequestInterface as Request;
use \Psr\Http\Message\ResponseInterface as Response;
require '/var/www/vendor/autoload.php';
require '/var/www/conf/config.php';
use Slim\Http\Stream;
if (php_sapi_name() === 'cli') return;			
if (isset($_SERVER['HTTP_ORIGIN'])) {
	header("Access-Control-Allow-Credentials: true");
	header("Access-Control-Allow-Origin: *");
	header("Access-Control-Allow-Methods: GET, POST, PUT, DELETE, PATCH, OPTIONS");
	header("Access-Control-Allow-Headers: Origin, X-Requested-With, Content-Type, Accept, Authorization");
}
// Access-Control headers are received during OPTIONS requests
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
	if (isset($_SERVER['HTTP_ACCESS_CONTROL_REQUEST_HEADERS'])){
		header("Access-Control-Allow-Headers: {$_SERVER['HTTP_ACCESS_CONTROL_REQUEST_HEADERS']}");
	}
	header( "HTTP/1.1 200 OK" );
	exit();
}

// this should activate the debug mode
$app = new \Slim\App([
    'settings' => [
        'displayErrorDetails' => true,
    ]
]);

$c = $app->getContainer();
$c['errorHandler'] = function ($c) {
    return function ($request, $response, $exception) use ($c) {
				error_log("MESSAGE : ".$exception->getMessage());
				error_log("STATUS CODE : ".$exception->getCode());
        return $c['response']->withStatus($exception->getCode())
                             ->withHeader('Content-Type', 'application/json')
			 ->withJson(array("message" => $exception->getMessage()));
    };
};

// SAMPLES //

$app->get('/samples',function ($request,$response) {
	require_once 'samples.php';
	$samples = listSamples();
	return 	$response = $response->withJson($samples);
});

$app->get('/qptiffs',function ($request,$response) {
	require_once 'samples.php';
	$samples = listQptiffs();
	return 	$response = $response->withJson($samples);
});


// IFQUANT //


$app->get("/{sample}/sample", function($request, $response, $args){
	require 'samples.php';
	$sampleId = $args['sample'];
	$sample = getSample($sampleId);
	return $response->withJson($sample);
});


$app->get("/{sample}/annotations", function($request, $response, $args){
	require 'ifquant.php';
	$sampleId = $args['sample'];
	$annotations = getAnnotations($sampleId);
	return $response->write($annotations)->withHeader('Content-Type', 'text/plain');
});

$app->delete("/{sample}/annotations", function($request, $response, $args){
	require 'ifquant.php';
	$sampleId = $args['sample'];
	$status = deleteAnnotations($sampleId);
	return $response->withJson($status);
});

$app->get("/{sample}/notifications", function($request, $response, $args){
	require 'ifquant.php';
	$sampleId = $args['sample'];
	$params = array("marker" => '',"threshold" => '');
	foreach($params as $param => $value) {
		$params[$param] = is_numeric($request->getQueryParam($param)) ? +$request->getQueryParam($param) : $request->getQueryParam($param);
	}

	$notifications = getNotifications($sampleId,$params);
	return $response->withJson($notifications);
});

$app->post("/{sample}/annotations", function($request, $response, $args){
	require 'ifquant.php';
	$sampleId = $args['sample'];
	$json = $request->getBody();
	$sample = saveAnnotations($sampleId,$json);
	return $response->withJson($sample);
});

$app->get('/{sample}/cells', function($request, $response, $args){
	require 'ifquant.php';
	$sample = $args['sample'];
	$params = array("x" => '',"y" => '',"width" => '',"height" => '',"marker" => '',"threshold" => '');
	foreach($params as $param => $value) {
		$params[$param] = is_numeric($request->getQueryParam($param)) ? +$request->getQueryParam($param) : $request->getQueryParam($param);
	}
	$cells = getCells($sample,$params);
	return $response->withJson($cells);	
});

$app->post('/{sample}/cells', function($request, $response, $args){
	require 'ifquant.php';
	$sample = $args['sample'];
	$post = $request->getParsedBody();
	$postParams = $post['params'];
	$params = array("x" => '',"y" => '',"width" => '',"height" => '',"thresholds" => '','type' => 'Q','marker' => "",'threshold' => "");
	foreach($params as $param => $value) {
		if (!isset($postParams[$param])) $params[$param] = $value;
		else $params[$param] = is_numeric($postParams[$param]) ? +$postParams[$param] :  $postParams[$param];
	}
	$cells = getCells($sample,$params);
	return $response->withJson($cells);	
});


$app->get('/{sample}/stats', function($request, $response, $args){
	require 'ifquant.php';
	$sample = $args['sample'];
	$params = array("x" => '',"y" => '',"width" => '',"height" => '',"marker" => '',"threshold" => '','tissueDetails' => false);
	foreach($params as $param => $value) {
		if ($param == 'tissueDetails') {
			$params[$param] = $request->getQueryParam('tissue') == 'yes';
		}
		else $params[$param] = is_numeric($request->getQueryParam($param)) ? +$request->getQueryParam($param) : $request->getQueryParam($param);
	}
	$stats = getStats($sample,$params);
	return $response->withJson($stats);	
});

$app->patch('/{sample}/thresholds', function($request, $response, $args){
	require 'ifquant.php';
	$sample = $args['sample'];
	$params = $request->getParsedBody();
	$rep=patchTreshold($sample,$params);
	return $response->withJson($rep);	
});


$app->get('/{sample}/thresholds', function($request, $response, $args){
	require 'ifquant.php';
	$sample = $args['sample'];
	$maps =  getColorMapsAndThresholds($sample);
	return $response->withJson($maps);
});

$app->get('/{sample}/otherPhenotypes', function($request, $response, $args){
	require 'ifquant.php';
	$sample = $args['sample'];
	$phenotypes =  getOtherPhenotypes($sample);
	return $response->withJson($phenotypes);
});

$app->get('/{sample}/qcpdf', function($request, $response, $args){
	require 'ifquant.php';
	$sample = $args['sample'];
	$png =  getQCPDF($sample);
	$response->write($png);
	return $response->withHeader('Content-Type', 'image/png');
});

$app->put("/{sample}/report",function($request, $response, $args){
	require 'ifquant.php';
	$sample = $args['sample'];
	$report = submitReport($sample);
	return $response->withJson($report);
});

$app->get("/{sample}/report/status",function($request, $response, $args){
	require 'ifquant.php';
	$sample = $args['sample'];
	$report = getReportStatus($sample);
	return $response->withJson($report);
});


$app->delete("/{sample}/report",function($request, $response, $args){
	require 'ifquant.php';
	$sampleId = $args['sample'];
	$report = deleteReport($sampleId);
	return $response->withJson($report);
});

$app->get('/{sample}/report/{file}', function($request, $response, $args){
	require 'ifquant.php';
	$file = $args['file'];
	$sample_id = $args['sample'];
	$report =  getIFQuantReport($sample_id,$file);
	if ($report) {
		$response = $response->withHeader('Content-Description', 'File Transfer')
			->withHeader('Content-Type', 'application/octet-stream')
				->withHeader('Content-Disposition', 'attachment;filename="'.$report['filename'].'"')
					->withHeader('Expires', '0')
						->withHeader('Cache-Control', 'must-revalidate')
							->withHeader('Pragma', 'public')
								->withHeader('Content-Length', filesize($report['file']));

		ob_end_flush();
		readfile($report['file']);		
	}
});

$app->get("/{sample}/densities/{cell_type}",function($request,$response,$args){
	require 'ifquant.php';
	$cell_type = $args['cell_type'];
	$sample = $args['sample'];
	$data = getIfquantDensitiesChannels($sample,$cell_type);
	return $response = $response->withJson($data);
});

$app->get("/{sample}/density_data",function($request,$response,$args){
	require 'ifquant.php';
	$sample = $args['sample'];
	$channelY = $request->getQueryParam('channelX');
	$channelX = $request->getQueryParam('channelY');
	$data = getDensityData($sample,$channelX,$channelY);
	return $response = $response->withJson($data);
});

$app->get("/{sample}/density", function($request, $response,$args){
	require 'ifquant.php';
	$sample = $args['sample'];
	$channelY = $request->getQueryParam('channelX');
	$channelX = $request->getQueryParam('channelY');
	$png = getDensityPlot($sample,$channelX,$channelY);
	$response->write($png);
	return $response->withHeader('Content-Type', 'image/png');

});

$app->get("/{sample}/tissue_sementation_thumbnail",function($request,$response,$args){
	require 'samples.php';
	$FIF = $request->getQueryParam('FIF');
	$WID = $request->getQueryParam('WID');
	$CVT = $request->getQueryParam('CVT');
	$iipserverUrl = "iipserver"; // must be the same as service name in docker compose	
	$url = "http://".$iipserverUrl."/fcgi-bin/iipsrv.fcgi?"."FIF=".$FIF."&WID=".$WID."&CVT=".$CVT;
	if (strpos($url,'tissue_segmentation') !== false){
		$response = $response->withHeader('Content-Type', 'image/jpeg')
					->withHeader('Expires', '0')
					->withHeader('Cache-Control', 'must-revalidate')
					->withHeader('Pragma', 'public');
		ob_end_flush();
		// error_log($url);
		readfile($url);
	}	
});

$app->run();

?>