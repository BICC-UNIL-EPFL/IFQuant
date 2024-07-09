<?php
if (!defined("TEMPLATE_PATH")) define("TEMPLATE_PATH","/var/www/templates"); // full path to template of parameter files. Used to check the format validity of user defined files
if (!defined("DATA_PATH")) define("DATA_PATH","/var/www/data"); 
if (!defined("TOOLS_PATH")) define("TOOLS_PATH","/var/www/tools");
if (!defined("IIP_SERVER")) define("IIP_SERVER","http://localhost:8089/fcgi-bin/iipsrv.fcgi?");
if (!defined("NPROCESSES")) define("NPROCESSES",2); //default --nprocesses parameter value
if (!defined("TMPDIR")) define("TMPDIR",""); //default --tmpdir parameter value. If left empty, the process will create the directory  DATA_PATH/analyses/SAMPLE_NAME/tmp
?>