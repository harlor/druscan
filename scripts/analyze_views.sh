#!/bin/bash
# Script: Analyze Views
# Purpose: Generate comprehensive JSON data about Drupal Views system
# Returns: JSON object with views statistics and detailed configuration

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo "{}"
    exit 0
fi

# ============================================
# Function: Get all views with detailed information
# ============================================
get_all_views() {
    ddev drush eval "
        \$view_storage = \\Drupal::entityTypeManager()->getStorage('view');
        \$views = \$view_storage->loadMultiple();

        \$result = [
            'statistics' => [
                'total' => 0,
                'enabled' => 0,
                'custom' => 0,
                'with_relationships' => 0
            ],
            'views' => []
        ];

        foreach (\$views as \$view_id => \$view) {
            \$result['statistics']['total']++;

            // Check if view is enabled
            \$is_enabled = \$view->status();
            if (\$is_enabled) {
                \$result['statistics']['enabled']++;
            }

            // Check if custom (not in core/contrib modules)
            \$dependencies = \$view->getDependencies();
            \$is_custom = true;
            if (isset(\$dependencies['enforced']['module'])) {
                foreach (\$dependencies['enforced']['module'] as \$module) {
                    if (\$module !== 'views') {
                        \$is_custom = false;
                        break;
                    }
                }
            }
            if (\$is_custom) {
                \$result['statistics']['custom']++;
            }

            // Get executable view
            \$executable = \$view->getExecutable();
            \$executable->initDisplay();

            // Build view data
            \$view_data = [
                'id' => \$view_id,
                'label' => \$view->label(),
                'status' => \$is_enabled,
                'base_table' => \$view->get('base_table'),
                'base_field' => \$view->get('base_field'),
                'description' => \$view->get('description') ?: '',
                'displays' => [
                    'total' => 0,
                    'types' => [],
                    'routes' => [],
                    'blocks' => [],
                    'details' => []
                ],
                'has_relationships' => false,
                'exposed_filters' => false,
                'items_per_page' => []
            ];

            // Analyze displays
            \$displays = \$view->get('display');
            \$view_data['displays']['total'] = count(\$displays) - 1; // Exclude default display from count

            foreach (\$displays as \$display_id => \$display) {
                if (\$display_id === 'default') {
                    continue; // Skip default display in detailed analysis
                }

                \$display_plugin = \$display['display_plugin'];

                // Add display type
                if (!in_array(\$display_plugin, \$view_data['displays']['types'])) {
                    \$view_data['displays']['types'][] = \$display_plugin;
                }

                \$display_info = [
                    'id' => \$display_id,
                    'title' => \$display['display_title'],
                    'type' => \$display_plugin
                ];

                // Check for page displays (routes)
                if (\$display_plugin === 'page') {
                    if (isset(\$display['display_options']['path'])) {
                        \$path = \$display['display_options']['path'];
                        \$view_data['displays']['routes'][] = \$path;
                        \$display_info['path'] = \$path;
                    }
                }

                // Check for block displays
                if (\$display_plugin === 'block') {
                    \$block_id = 'views_block:' . \$view_id . '-' . \$display_id;
                    \$view_data['displays']['blocks'][] = \$block_id;
                    \$display_info['block_id'] = \$block_id;
                }

                // Check for exposed filters
                if (isset(\$display['display_options']['exposed_form'])) {
                    \$view_data['exposed_filters'] = true;
                }

                // Get items per page
                if (isset(\$display['display_options']['pager']['options']['items_per_page'])) {
                    \$items = \$display['display_options']['pager']['options']['items_per_page'];
                    if (!in_array(\$items, \$view_data['items_per_page'])) {
                        \$view_data['items_per_page'][] = \$items;
                    }
                    \$display_info['items_per_page'] = \$items;
                }

                \$view_data['displays']['details'][] = \$display_info;
            }

            // Check for relationships in default display
            if (isset(\$displays['default']['display_options']['relationships'])) {
                \$relationships = \$displays['default']['display_options']['relationships'];
                if (!empty(\$relationships)) {
                    \$view_data['has_relationships'] = true;
                    \$result['statistics']['with_relationships']++;
                }
            }

            \$result['views'][] = \$view_data;
        }

        echo json_encode(\$result, JSON_PRETTY_PRINT);
    " 2>/dev/null || echo '{"statistics": {"total": 0, "enabled": 0, "custom": 0, "with_relationships": 0}, "views": []}'
}

# ============================================
# Function: Get views statistics only
# ============================================
get_views_statistics() {
    ddev drush eval "
        \$view_storage = \\Drupal::entityTypeManager()->getStorage('view');
        \$views = \$view_storage->loadMultiple();

        \$stats = [
            'total' => count(\$views),
            'enabled' => 0,
            'disabled' => 0,
            'with_page_displays' => 0,
            'with_block_displays' => 0,
            'with_feed_displays' => 0
        ];

        foreach (\$views as \$view) {
            if (\$view->status()) {
                \$stats['enabled']++;
            } else {
                \$stats['disabled']++;
            }

            \$displays = \$view->get('display');
            foreach (\$displays as \$display_id => \$display) {
                if (\$display_id === 'default') continue;

                switch (\$display['display_plugin']) {
                    case 'page':
                        \$stats['with_page_displays']++;
                        break;
                    case 'block':
                        \$stats['with_block_displays']++;
                        break;
                    case 'feed':
                        \$stats['with_feed_displays']++;
                        break;
                }
            }
        }

        echo json_encode(\$stats, JSON_PRETTY_PRINT);
    " 2>/dev/null || echo '{"total": 0, "enabled": 0, "disabled": 0, "with_page_displays": 0, "with_block_displays": 0, "with_feed_displays": 0}'
}

# ============================================
# Function: Get list of views with routes only
# ============================================
get_views_with_routes() {
    ddev drush eval "
        \$view_storage = \\Drupal::entityTypeManager()->getStorage('view');
        \$views = \$view_storage->loadMultiple();

        \$result = [];

        foreach (\$views as \$view_id => \$view) {
            \$displays = \$view->get('display');
            \$routes = [];

            foreach (\$displays as \$display_id => \$display) {
                if (\$display['display_plugin'] === 'page' && isset(\$display['display_options']['path'])) {
                    \$routes[] = [
                        'display_id' => \$display_id,
                        'display_title' => \$display['display_title'],
                        'path' => \$display['display_options']['path']
                    ];
                }
            }

            if (!empty(\$routes)) {
                \$result[] = [
                    'view_id' => \$view_id,
                    'view_label' => \$view->label(),
                    'routes' => \$routes
                ];
            }
        }

        echo json_encode(\$result, JSON_PRETTY_PRINT);
    " 2>/dev/null || echo '[]'
}

# ============================================
# Function: Get list of views with blocks only
# ============================================
get_views_with_blocks() {
    ddev drush eval "
        \$view_storage = \\Drupal::entityTypeManager()->getStorage('view');
        \$views = \$view_storage->loadMultiple();

        \$result = [];

        foreach (\$views as \$view_id => \$view) {
            \$displays = \$view->get('display');
            \$blocks = [];

            foreach (\$displays as \$display_id => \$display) {
                if (\$display['display_plugin'] === 'block') {
                    \$blocks[] = [
                        'display_id' => \$display_id,
                        'display_title' => \$display['display_title'],
                        'block_id' => 'views_block:' . \$view_id . '-' . \$display_id
                    ];
                }
            }

            if (!empty(\$blocks)) {
                \$result[] = [
                    'view_id' => \$view_id,
                    'view_label' => \$view->label(),
                    'blocks' => \$blocks
                ];
            }
        }

        echo json_encode(\$result, JSON_PRETTY_PRINT);
    " 2>/dev/null || echo '[]'
}

# ============================================
# Main execution based on operation type
# ============================================
OPERATION="${1:-all}"

case "$OPERATION" in
    all)
        get_all_views
        ;;
    statistics)
        get_views_statistics
        ;;
    routes)
        get_views_with_routes
        ;;
    blocks)
        get_views_with_blocks
        ;;
    *)
        echo "{\"error\": \"Unknown operation: $OPERATION. Use: all, statistics, routes, or blocks\"}"
        exit 1
        ;;
esac
