<?php
/**
 * Read-only store facts for a WooCommerce performance diagnosis.
 *
 *   wp eval-file store_facts.php > store-facts.json
 *
 * Prints one JSON document. It runs SELECT queries and reads options only: it writes nothing,
 * changes no setting and prints no customer data (no names, emails, addresses or order details).
 * Row counts for the biggest tables come from information_schema estimates, so the script stays
 * quick on a store with tens of millions of postmeta rows.
 *
 * Part of the woocommerce-performance-diagnosis skill, https://github.com/superspeedyplugins/skills
 * Licence: GPL-3.0.
 */

if (!defined('ABSPATH')) {
    fwrite(STDERR, "Run this with: wp eval-file store_facts.php\n");
    exit(1);
}

global $wpdb;
$p = $wpdb->prefix;
$now = time();

function sfd_table_exists($table) {
    global $wpdb;
    return $wpdb->get_var($wpdb->prepare('SHOW TABLES LIKE %s', $wpdb->esc_like($table))) === $table;
}

function sfd_count($sql) {
    global $wpdb;
    $v = $wpdb->get_var($sql);
    return null === $v ? null : (int) $v;
}

$facts = array(
    'schema' => 'woocommerce-performance-diagnosis/store-facts@1',
    'generated_at_utc' => gmdate('c', $now),
);

// Environment.
$db_version = $wpdb->get_var('SELECT VERSION()');
$facts['environment'] = array(
    'site_url' => get_option('siteurl'),
    'wordpress' => get_bloginfo('version'),
    'woocommerce' => defined('WC_VERSION') ? WC_VERSION : null,
    'php' => PHP_VERSION,
    'php_note' => 'PHP version and limits are read by WP-CLI; the web server can run a different PHP. Performance Analysis reports the web PHP.',
    'database_server' => $db_version,
    'database_is_mariadb' => false !== stripos((string) $db_version, 'mariadb'),
    'multisite' => is_multisite(),
    'wp_memory_limit' => defined('WP_MEMORY_LIMIT') ? WP_MEMORY_LIMIT : null,
    'wp_max_memory_limit_admin' => defined('WP_MAX_MEMORY_LIMIT') ? WP_MAX_MEMORY_LIMIT : null,
    'cli_php_memory_limit' => ini_get('memory_limit'),
    'memory_note' => 'WP_MEMORY_LIMIT applies to the front end and WP_MAX_MEMORY_LIMIT to wp-admin; WP-CLI itself usually runs without a limit.',
    'wp_debug' => defined('WP_DEBUG') && WP_DEBUG,
    'savequeries' => defined('SAVEQUERIES') && SAVEQUERIES,
    'disable_wp_cron' => defined('DISABLE_WP_CRON') && DISABLE_WP_CRON,
    'theme' => wp_get_theme()->get_stylesheet(),
    'theme_parent' => wp_get_theme()->parent() ? wp_get_theme()->get_template() : null,
);

if (!defined('WC_VERSION')) {
    $facts['woocommerce_active'] = false;
    echo wp_json_encode($facts, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
    return;
}
$facts['woocommerce_active'] = true;

// Active plugins with versions.
if (!function_exists('get_plugins')) {
    require_once ABSPATH . 'wp-admin/includes/plugin.php';
}
$all = get_plugins();
$active = (array) get_option('active_plugins', array());
if (is_multisite()) {
    $active = array_merge($active, array_keys((array) get_site_option('active_sitewide_plugins', array())));
}
$plugins = array();
foreach (array_unique($active) as $file) {
    $plugins[] = array(
        'slug' => dirname($file) === '.' ? basename($file, '.php') : dirname($file),
        'name' => isset($all[$file]) ? $all[$file]['Name'] : $file,
        'version' => isset($all[$file]) ? $all[$file]['Version'] : null,
    );
}
$mu = array();
foreach (array_keys(get_mu_plugins()) as $file) {
    $mu[] = $file;
}
$dropins = array_keys(get_dropins());
$facts['plugins'] = array('active_count' => count($plugins), 'active' => $plugins, 'must_use' => $mu, 'dropins' => $dropins);

// HPOS.
$hpos_on = 'yes' === get_option('woocommerce_custom_orders_table_enabled');
$facts['orders_storage'] = array(
    'hpos_enabled' => $hpos_on,
    'compatibility_mode_sync' => 'yes' === get_option('woocommerce_custom_orders_table_data_sync_enabled'),
    'hpos_tables_exist' => sfd_table_exists($p . 'wc_orders'),
);

// Catalogue.
$counts = wp_count_posts('product');
$var_counts = wp_count_posts('product_variation');
$attr_tax = wc_get_attribute_taxonomies();
$attr = array();
foreach ($attr_tax as $a) {
    $tax = wc_attribute_taxonomy_name($a->attribute_name);
    $attr[] = array('taxonomy' => $tax, 'terms' => (int) wp_count_terms(array('taxonomy' => $tax, 'hide_empty' => false)));
}
$type_rows = $wpdb->get_results(
    "SELECT t.slug, COUNT(*) AS n FROM {$p}term_relationships tr
     JOIN {$p}term_taxonomy tt ON tt.term_taxonomy_id = tr.term_taxonomy_id AND tt.taxonomy = 'product_type'
     JOIN {$p}terms t ON t.term_id = tt.term_id GROUP BY t.slug"
);
$types = array();
foreach ((array) $type_rows as $r) {
    $types[$r->slug] = (int) $r->n;
}
$facts['catalogue'] = array(
    'products_published' => (int) $counts->publish,
    'products_all_statuses' => (int) array_sum((array) $counts),
    'product_types' => $types,
    'variations' => (int) array_sum((array) $var_counts),
    'product_categories' => (int) wp_count_terms(array('taxonomy' => 'product_cat', 'hide_empty' => false)),
    'product_tags' => (int) wp_count_terms(array('taxonomy' => 'product_tag', 'hide_empty' => false)),
    'global_attributes' => $attr,
    'product_meta_lookup_rows' => sfd_table_exists($p . 'wc_product_meta_lookup') ? sfd_count("SELECT COUNT(*) FROM {$p}wc_product_meta_lookup") : null,
    'attribute_lookup_table_in_use' => 'yes' === get_option('woocommerce_attribute_lookup_enabled'),
    'attribute_lookup_rows' => sfd_table_exists($p . 'wc_product_attributes_lookup') ? sfd_count("SELECT COUNT(*) FROM {$p}wc_product_attributes_lookup") : null,
    'hide_out_of_stock' => 'yes' === get_option('woocommerce_hide_out_of_stock_items'),
    'products_per_page_note' => 'Set by the theme; check the shop page itself.',
);

// Orders.
$orders = array();
if ($hpos_on && sfd_table_exists($p . 'wc_orders')) {
    $orders['total'] = sfd_count("SELECT COUNT(*) FROM {$p}wc_orders WHERE type = 'shop_order'");
    $orders['last_30_days'] = sfd_count($wpdb->prepare("SELECT COUNT(*) FROM {$p}wc_orders WHERE type = 'shop_order' AND date_created_gmt >= %s", gmdate('Y-m-d H:i:s', $now - 30 * DAY_IN_SECONDS)));
    $orders['source'] = 'wc_orders';
} else {
    $orders['total'] = (int) array_sum((array) wp_count_posts('shop_order'));
    $orders['last_30_days'] = sfd_count($wpdb->prepare("SELECT COUNT(*) FROM {$p}posts WHERE post_type = 'shop_order' AND post_date_gmt >= %s", gmdate('Y-m-d H:i:s', $now - 30 * DAY_IN_SECONDS)));
    $orders['source'] = 'posts';
}
$orders['legacy_order_posts'] = sfd_count("SELECT COUNT(*) FROM {$p}posts WHERE post_type = 'shop_order'");
$orders['customers'] = sfd_table_exists($p . 'wc_customer_lookup') ? sfd_count("SELECT COUNT(*) FROM {$p}wc_customer_lookup") : null;
$facts['orders'] = $orders;

// Biggest tables (estimates from information_schema).
$tables = $wpdb->get_results($wpdb->prepare(
    'SELECT TABLE_NAME AS name, ENGINE AS engine, TABLE_ROWS AS rows_estimate,
            ROUND((DATA_LENGTH + INDEX_LENGTH) / 1048576, 1) AS size_mb,
            ROUND(INDEX_LENGTH / 1048576, 1) AS index_mb
     FROM information_schema.TABLES WHERE TABLE_SCHEMA = %s AND TABLE_NAME LIKE %s
     ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC LIMIT 15',
    DB_NAME,
    $wpdb->esc_like($p) . '%'
), ARRAY_A);
foreach ((array) $tables as $i => $t) {
    $tables[$i]['rows_estimate'] = (int) $t['rows_estimate'];
    $tables[$i]['size_mb'] = (float) $t['size_mb'];
    $tables[$i]['index_mb'] = (float) $t['index_mb'];
}
$non_innodb = $wpdb->get_col($wpdb->prepare(
    "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = %s AND TABLE_NAME LIKE %s AND ENGINE <> 'InnoDB'",
    DB_NAME,
    $wpdb->esc_like($p) . '%'
));
$facts['database'] = array('largest_tables' => $tables, 'non_innodb_tables' => $non_innodb);

// Indexes on the tables that slow WooCommerce queries usually hit.
$indexes = array();
foreach (array('postmeta', 'posts', 'term_relationships', 'options', 'wc_product_meta_lookup', 'wc_orders_meta', 'woocommerce_sessions') as $t) {
    if (!sfd_table_exists($p . $t)) {
        continue;
    }
    $rows = $wpdb->get_results("SHOW INDEX FROM {$p}{$t}", ARRAY_A);
    $by = array();
    foreach ($rows as $r) {
        $by[$r['Key_name']][] = $r['Column_name'] . ($r['Sub_part'] ? '(' . $r['Sub_part'] . ')' : '');
    }
    foreach ($by as $k => $cols) {
        $by[$k] = implode(',', $cols);
    }
    $indexes[$t] = $by;
}
$facts['database']['indexes'] = $indexes;
$facts['database']['slow_query_log'] = array(
    'enabled' => $wpdb->get_var("SELECT @@GLOBAL.slow_query_log"),
    'long_query_time' => $wpdb->get_var("SELECT @@GLOBAL.long_query_time"),
);

// Autoload.
$autoload_values = "('yes','on','auto-on','auto')";
$facts['autoload'] = array(
    'bytes' => sfd_count("SELECT COALESCE(SUM(LENGTH(option_value)),0) FROM {$p}options WHERE autoload IN $autoload_values"),
    'rows' => sfd_count("SELECT COUNT(*) FROM {$p}options WHERE autoload IN $autoload_values"),
    'largest' => array_map(function ($r) {
        return array('option_name' => $r['option_name'], 'bytes' => (int) $r['bytes']);
    }, (array) $wpdb->get_results("SELECT option_name, LENGTH(option_value) AS bytes FROM {$p}options WHERE autoload IN $autoload_values ORDER BY bytes DESC LIMIT 10", ARRAY_A)),
    'transient_rows' => sfd_count("SELECT COUNT(*) FROM {$p}options WHERE option_name LIKE '\\_transient\\_%' OR option_name LIKE '\\_site\\_transient\\_%'"),
    'expired_transients' => sfd_count($wpdb->prepare("SELECT COUNT(*) FROM {$p}options WHERE (option_name LIKE '\\_transient\\_timeout\\_%%' OR option_name LIKE '\\_site\\_transient\\_timeout\\_%%') AND option_value < %d", $now)),
);

// Object cache and page cache signals.
$advanced_cache = WP_CONTENT_DIR . '/advanced-cache.php';
$facts['caching'] = array(
    'persistent_object_cache' => (bool) wp_using_ext_object_cache(),
    'object_cache_dropin' => file_exists(WP_CONTENT_DIR . '/object-cache.php'),
    'wp_cache_constant' => defined('WP_CACHE') && WP_CACHE,
    'advanced_cache_dropin' => file_exists($advanced_cache),
    'page_cache_note' => 'A page cache can also sit outside WordPress (host, Varnish, nginx, CDN). Check response headers with curl as the skill describes.',
);

// WP-Cron.
$cron = _get_cron_array();
$events = 0;
$overdue = 0;
$overdue_hooks = array();
foreach ((array) $cron as $ts => $hooks) {
    foreach ((array) $hooks as $hook => $instances) {
        $n = count((array) $instances);
        $events += $n;
        if ($ts < $now - 600) {
            $overdue += $n;
            $overdue_hooks[$hook] = ($overdue_hooks[$hook] ?? 0) + $n;
        }
    }
}
arsort($overdue_hooks);
$facts['cron'] = array(
    'events' => $events,
    'overdue_more_than_10_minutes' => $overdue,
    'overdue_hooks' => array_slice($overdue_hooks, 0, 10, true),
    'disable_wp_cron' => defined('DISABLE_WP_CRON') && DISABLE_WP_CRON,
);

// Action Scheduler.
if (sfd_table_exists($p . 'actionscheduler_actions')) {
    $facts['action_scheduler'] = array(
        'pending' => sfd_count("SELECT COUNT(*) FROM {$p}actionscheduler_actions WHERE status = 'pending'"),
        'pending_past_due_more_than_10_minutes' => sfd_count($wpdb->prepare("SELECT COUNT(*) FROM {$p}actionscheduler_actions WHERE status = 'pending' AND scheduled_date_gmt < %s", gmdate('Y-m-d H:i:s', $now - 600))),
        'failed' => sfd_count("SELECT COUNT(*) FROM {$p}actionscheduler_actions WHERE status = 'failed'"),
        'complete' => sfd_count("SELECT COUNT(*) FROM {$p}actionscheduler_actions WHERE status = 'complete'"),
        'log_rows' => sfd_table_exists($p . 'actionscheduler_logs') ? sfd_count("SELECT COUNT(*) FROM {$p}actionscheduler_logs") : null,
        'top_pending_hooks' => $wpdb->get_results("SELECT hook, COUNT(*) AS n FROM {$p}actionscheduler_actions WHERE status = 'pending' GROUP BY hook ORDER BY n DESC LIMIT 5", ARRAY_A),
        'top_failed_hooks' => $wpdb->get_results("SELECT hook, COUNT(*) AS n FROM {$p}actionscheduler_actions WHERE status = 'failed' GROUP BY hook ORDER BY n DESC LIMIT 5", ARRAY_A),
    );
}

// Other housekeeping.
$facts['housekeeping'] = array(
    'revisions' => sfd_count("SELECT COUNT(*) FROM {$p}posts WHERE post_type = 'revision'"),
    'trashed_posts' => sfd_count("SELECT COUNT(*) FROM {$p}posts WHERE post_status = 'trash'"),
    'auto_drafts' => sfd_count("SELECT COUNT(*) FROM {$p}posts WHERE post_status = 'auto-draft'"),
    'woocommerce_sessions' => sfd_table_exists($p . 'woocommerce_sessions') ? sfd_count("SELECT COUNT(*) FROM {$p}woocommerce_sessions") : null,
    'expired_woocommerce_sessions' => sfd_table_exists($p . 'woocommerce_sessions') ? sfd_count($wpdb->prepare("SELECT COUNT(*) FROM {$p}woocommerce_sessions WHERE session_expiry < %d", $now)) : null,
    'comments_order_notes' => sfd_count("SELECT COUNT(*) FROM {$p}comments WHERE comment_type = 'order_note'"),
);

echo wp_json_encode($facts, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
