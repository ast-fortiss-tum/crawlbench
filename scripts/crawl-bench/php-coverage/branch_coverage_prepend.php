<?php
// Per-request line + branch coverage recorder for PHP 5.5 / Xdebug 2.5.5.
//
// Replaces PHP_CodeCoverage's "merge into one serialized aggregate on every request" with one small JSON file
// per request (no read-modify-write, no races, much cheaper); merge_xdebug_coverage.py merges them afterwards.
// Active only while the marker file exists (created/removed by the coverage start/stop utilities).
//
// Configuration (environment, optional):
//   COVERAGE_INCLUDE  colon-separated path prefixes to record   (default /var/www/html/)
//   COVERAGE_EXCLUDE  colon-separated path prefixes to ignore   (default /var/www/html/coverage/)
//   COVERAGE_DIR      output dir                                (default /var/www/html/coverage/coverage_data)
//   COVERAGE_PATHS    set to 1 to also keep path coverage        (default off: path data is huge)
$__cov_dir = getenv('COVERAGE_DIR') ?: '/var/www/html/coverage/coverage_data';
if (function_exists('xdebug_start_code_coverage') && file_exists($__cov_dir . '/is_recording.txt')) {
    xdebug_start_code_coverage(XDEBUG_CC_UNUSED | XDEBUG_CC_DEAD_CODE | XDEBUG_CC_BRANCH_CHECK);
    register_shutdown_function(function () use ($__cov_dir) {
        $data = xdebug_get_code_coverage();
        xdebug_stop_code_coverage(true);
        $include = explode(':', getenv('COVERAGE_INCLUDE') ?: '/var/www/html/');
        $exclude = explode(':', getenv('COVERAGE_EXCLUDE') ?: '/var/www/html/coverage/');
        $out = array();
        foreach ($data as $file => $info) {
            $keep = false;
            foreach ($include as $p) { if ($p !== '' && strpos($file, $p) === 0) { $keep = true; break; } }
            foreach ($exclude as $p) { if ($p !== '' && strpos($file, $p) === 0) { $keep = false; break; } }
            if ($keep) {
                if (!getenv('COVERAGE_PATHS') && isset($info['functions'])) {
                    // path enumeration explodes for large functions (huge files); branch/edge data is enough
                    foreach ($info['functions'] as $fn => $f) { unset($info['functions'][$fn]['paths']); }
                }
                $out[$file] = $info;
            }
        }
        if (!$out) { return; }
        $dir = $__cov_dir . '/requests';
        if (!is_dir($dir)) { @mkdir($dir, 0777, true); }
        $name = sprintf('%s/%014.4f-%d.json', $dir, microtime(true), getmypid());
        $uri = isset($_SERVER['REQUEST_URI']) ? $_SERVER['REQUEST_URI'] : (isset($_SERVER['argv'][0]) ? $_SERVER['argv'][0] : '');
        file_put_contents($name, json_encode(array('uri' => $uri, 'files' => $out)));
    });
}
