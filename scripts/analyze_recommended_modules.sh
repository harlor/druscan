#!/bin/bash
# Analyzes which recommended modules are installed/enabled in the Drupal site
# Usage: ./analyze_recommended_modules.sh [set_name]
# set_name: seo, security, performance, or "all" (default)

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load module registry as JSON
MODULE_REGISTRY=$(bash "${SCRIPT_DIR}/recommended_modules_registry.sh")

# Get ALL module statuses once at the beginning (avoid multiple drush calls)
ALL_MODULES_STATUS=$(ddev drush pm:list --format=json 2>/dev/null || echo '{}')

# Get list of composer packages (to check if module is added to composer.json)
COMPOSER_PACKAGES=$(ddev composer show --direct --format=json 2>/dev/null | jq -r '.installed[].name' | grep '^drupal/' || echo "")

# Analyze specific module set
analyze_module_set() {
    local set_name="$1"

    # Extract module set from registry
    local module_set=$(echo "$MODULE_REGISTRY" | jq -c ".${set_name}")

    if [ "$module_set" == "null" ]; then
        echo "{\"error\": \"Module set '${set_name}' not found in registry\"}"
        return 1
    fi

    # Convert composer packages list to JSON array
    local composer_packages_json=$(echo "$COMPOSER_PACKAGES" | jq -R -s -c 'split("\n") | map(select(length > 0))')

    # Process entirely in jq - merge registry with actual module statuses
    echo "$module_set" | jq \
        --arg set_name "$set_name" \
        --argjson all_modules "$ALL_MODULES_STATUS" \
        --argjson composer_packages "$composer_packages_json" \
        '
        # Build modules array with status
        [
            to_entries[] |
            .key as $module_key |
            .value as $module_data |

            # Check if added to composer
            ("drupal/" + $module_key) as $composer_name |
            ($composer_packages | index($composer_name) != null) as $is_in_composer |

            # Get Drupal status (or "Enabled" if is_core)
            (if ($module_data.is_core // false) then
                "Enabled"
            else
                ($all_modules[$module_key].status // "not_found")
            end) as $drupal_status |

            # Build module object
            {
                machine_name: $module_key,
                display_name: $module_data.name,
                purpose: $module_data.purpose,
                is_added_to_composer: $is_in_composer,
                is_enabled_in_drupal: ($drupal_status == "Enabled")
            } +
            (if ($module_data.is_core // false) then {is_core: true} else {} end)
        ] as $modules |

        # Calculate statistics
        ($modules | length) as $total_count |
        ($modules | map(select(.is_added_to_composer)) | length) as $added_to_composer_count |
        ($modules | map(select(.is_enabled_in_drupal)) | length) as $enabled_in_drupal_count |
        ($modules | map(select(.is_added_to_composer and .is_enabled_in_drupal)) | length) as $added_and_enabled_count |

        # Build final result
        {
            set_name: $set_name,
            total_count: $total_count,
            modules: $modules,
            statistics: {
                added_to_composer_count: $added_to_composer_count,
                enabled_in_drupal_count: $enabled_in_drupal_count,
                added_and_enabled_count: $added_and_enabled_count,
                not_added_count: ($total_count - $added_to_composer_count)
            }
        }
        '
}

# Main execution
SET_NAME="${1:-all}"

if [[ "$SET_NAME" == "all" ]]; then
    # Analyze all sets and combine with jq
    SEO_RESULT=$(analyze_module_set "seo")
    SECURITY_RESULT=$(analyze_module_set "security")
    PERFORMANCE_RESULT=$(analyze_module_set "performance")

    jq -n \
        --argjson seo "$SEO_RESULT" \
        --argjson security "$SECURITY_RESULT" \
        --argjson performance "$PERFORMANCE_RESULT" \
        '{
            seo: $seo,
            security: $security,
            performance: $performance
        }'

elif [[ "$SET_NAME" == "seo" ]] || [[ "$SET_NAME" == "security" ]] || [[ "$SET_NAME" == "performance" ]]; then
    analyze_module_set "$SET_NAME"

else
    echo "{\"error\": \"Unknown module set: $SET_NAME. Use: seo, security, performance, or all\"}"
    exit 1
fi
