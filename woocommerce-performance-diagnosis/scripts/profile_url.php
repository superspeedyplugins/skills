<?php
/**
 * Measure one URL of this site with Super Speedy Performance Analysis and print a short summary.
 *
 *   wp eval-file - <url> [anon|admin] --user=<administrator> < profile_url.php > profile.json
 *
 * For pages a normal `wp sspa run` does not measure: a filtered category, a real search term, a
 * busy product. It calls the plugin's own `sspa/profile-url` ability (what the admin bar's
 * "Analyse this page" does), drives the run to the end with `sspa/advance-run`, then reads the
 * measurement with `sspa/get-page-profile`. GET requests to this site only; nothing else changes
 * apart from the plugin saving its measurement.
 *
 * The summary leaves out the full SQL text and the raw capture, which can hold search terms and
 * other literals. Read the full profile in wp-admin (Performance Analysis) if you need it.
 *
 * Part of the woocommerce-performance-diagnosis skill, https://github.com/superspeedyplugins/skills
 * Licence: GPL-3.0.
 */

if (!defined('ABSPATH')) {
    fwrite(STDERR, "Run this with: wp eval-file - <url> [anon|admin] --user=<administrator> < profile_url.php\n");
    exit(1);
}

$url = isset($args[0]) ? (string) $args[0] : '';
$as = isset($args[1]) ? (string) $args[1] : 'anon';
if ('' === $url) {
    WP_CLI::error('Pass the URL to measure: wp eval-file - <url> [anon|admin] --user=<administrator> < profile_url.php');
}
if (!function_exists('wp_get_ability') || !wp_get_ability('sspa/profile-url')) {
    WP_CLI::error('The sspa/profile-url ability is not registered. Performance Analysis must be active, on WordPress 6.9 or later.');
}
if (!get_current_user_id()) {
    WP_CLI::error('Run it as an administrator: add --user=<login>.');
}

$start = wp_get_ability('sspa/profile-url')->execute(array('url' => $url, 'as' => $as));
if (is_wp_error($start)) {
    WP_CLI::error('profile-url: ' . $start->get_error_message());
}
$run_id = (int) $start['run_id'];
$page_key = (string) $start['page_key'];

// Each advance-run call processes up to about 15 seconds of work; one URL needs very few.
$deadline = time() + 600;
do {
    $status = wp_get_ability('sspa/advance-run')->execute(array('run_id' => $run_id));
    if (is_wp_error($status)) {
        WP_CLI::error('advance-run: ' . $status->get_error_message());
    }
    $state = isset($status['run']['status']) ? $status['run']['status'] : '';
} while (!empty($status['active']) && in_array($state, array('queued', 'crawling', 'analysing'), true) && time() < $deadline);

if ('done' !== $state) {
    WP_CLI::error(sprintf('Run %d ended with status "%s"%s', $run_id, $state, empty($status['run']['reason']) ? '' : ': ' . $status['run']['reason']));
}

$profile = wp_get_ability('sspa/get-page-profile')->execute(array('page_key' => $page_key));
if (is_wp_error($profile)) {
    WP_CLI::error('get-page-profile: ' . $profile->get_error_message());
}

$p = $profile['profile'];
$capture = isset($profile['capture']) && is_array($profile['capture']) ? $profile['capture'] : array();
$components = array();
foreach ((array) ($capture['components'] ?? array()) as $slug => $c) {
    $components[] = array(
        'component' => $slug,
        'type' => $c['type'] ?? null,
        'sql_ms' => isset($c['sql_ms']) ? round((float) $c['sql_ms'], 1) : null,
        'queries' => $c['query_count'] ?? null,
        'rows' => $c['rows'] ?? null,
        'slowest_query_ms' => isset($c['slowest_ms']) ? round((float) $c['slowest_ms'], 1) : null,
        'http_ms' => $c['http_ms'] ?? null,
    );
}
usort($components, function ($a, $b) {
    return ($b['sql_ms'] ?? 0) <=> ($a['sql_ms'] ?? 0);
});

$findings = array();
foreach ((array) ($profile['findings'] ?? array()) as $f) {
    $ev = (array) ($f['evidence'] ?? array());
    $findings[] = array(
        'type' => $f['type'] ?? null,
        'severity' => $f['severity'] ?? null,
        'component' => $f['component'] ?? null,
        'confidence' => $f['confidence'] ?? null,
        'headline' => $f['headline'] ?? null,
        'ms' => $ev['ms'] ?? null,
        'rows' => $ev['rows'] ?? ($ev['est_rows'] ?? null),
        'shape' => $ev['shape'] ?? null,
        'recommendation' => isset($f['recommendation']['title']) ? $f['recommendation']['title'] : null,
    );
}

$samples = array();
foreach ((array) ($p['samples'] ?? array()) as $s) {
    $samples[] = array('gen_ms' => $s['gen_ms'] ?? null, 'wall_ms' => $s['wall_ms'] ?? null, 'code' => $s['code'] ?? null, 'blocked_by' => $s['blocked_by'] ?? null);
}

echo wp_json_encode(array(
    'schema' => 'woocommerce-performance-diagnosis/url-profile@1',
    'url' => $p['url'],
    'as' => $p['variant'],
    'run_id' => $run_id,
    'page_key' => $page_key,
    'response_code' => isset($p['response_code']) ? (int) $p['response_code'] : null,
    'blocked_by' => $p['blocked_by'] ?: null,
    'generation_ms' => isset($p['page_gen_ms']) ? (float) $p['page_gen_ms'] : null,
    'ttfb_ms' => isset($p['ttfb_ms']) ? (float) $p['ttfb_ms'] : null,
    'sql_ms' => isset($p['sql_ms']) ? (float) $p['sql_ms'] : null,
    'sql_count' => isset($p['sql_count']) ? (int) $p['sql_count'] : null,
    'rows_fetched' => isset($p['rows_returned_total']) ? (int) $p['rows_returned_total'] : null,
    'duplicate_queries' => isset($p['dupe_query_count']) ? (int) $p['dupe_query_count'] : null,
    'http_ms' => isset($p['http_ms']) ? (float) $p['http_ms'] : null,
    'peak_mem_bytes' => isset($p['peak_mem_bytes']) ? (int) $p['peak_mem_bytes'] : null,
    'samples' => $samples,
    'components' => $components,
    'findings' => $findings,
), JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
