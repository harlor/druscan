#!/bin/bash
# DRUSCAN: Configuration Management Analysis Script
# Analyzes Drupal configuration sync, config management modules, and sync status

set -euo pipefail

# Get the mode parameter (default: full_analysis)
MODE="${1:-full_analysis}"

# Function to safely execute drush commands
safe_drush() {
    doc drush "$@" 2>/dev/null || echo "{}"
}

# Function to get config directory path (resolved from settings.php via drush)
get_config_directory() {
    # Try to get from drush status first (most reliable - reads from settings.php)
    local config_dir=$(safe_drush status --format=json 2>/dev/null | jq -r '.["config-sync"] // empty')

    if [ -z "$config_dir" ]; then
        # Try to get from system.file config
        config_dir=$(safe_drush config:get system.file --format=json 2>/dev/null | jq -r '.sync // empty')
    fi

    if [ -z "$config_dir" ]; then
        # Fallback: check common locations
        if [ -d "config/sync" ]; then
            echo "config/sync"
        elif [ -d "../config/sync" ]; then
            echo "../config/sync"
        else
            echo "config/sync"
        fi
    else
        # Config dir from drush is relative to DOCROOT (e.g., "../config/sync")
        # DOCROOT is exported by audit.sh (e.g., "web" or "docroot")
        if [[ "$config_dir" = /* ]]; then
            # Absolute path - use as is
            echo "$config_dir"
        elif [ -n "$DOCROOT" ]; then
            # Relative path from DOCROOT - resolve it
            # web/../config/sync -> config/sync
            echo "$(cd "$DOCROOT" 2>/dev/null && cd "$config_dir" 2>/dev/null && pwd)" || echo "$config_dir"
        else
            # No DOCROOT available, use path as-is
            echo "$config_dir"
        fi
    fi
}

# Function to check if config directory exists
check_config_directory() {
    local config_dir="$1"
    if [ -d "$config_dir" ]; then
        local file_count=$(find "$config_dir" -name "*.yml" -type f 2>/dev/null | wc -l | tr -d ' ')
        echo "{\"exists\": true, \"path\": \"$config_dir\", \"yml_files_count\": $file_count}"
    else
        echo "{\"exists\": false, \"path\": \"$config_dir\", \"yml_files_count\": 0}"
    fi
}

# Function to check config sync status (differences)
check_config_sync_status() {
    local status_output=$(doc drush config:status --format=json 2>/dev/null || echo '{}')

    # Clean and validate the JSON output (remove trailing commas if any)
    status_output=$(echo "$status_output" | sed 's/,\s*}/}/g' | sed 's/,\s*]/]/g')

    # Convert to array format for better handling
    local diffs_array=$(echo "$status_output" | jq -c 'to_entries | map({name: .key, state: .value.state // .value})' 2>/dev/null || echo '[]')

    # Count differences
    local total_diffs=$(echo "$diffs_array" | jq 'length' 2>/dev/null || echo "0")

    if [ "$total_diffs" -eq 0 ]; then
        echo "{\"in_sync\": true, \"differences_count\": 0, \"differences\": []}"
    else
        echo "{\"in_sync\": false, \"differences_count\": $total_diffs, \"differences\": $diffs_array}"
    fi
}

# Function to analyze Config Split module
analyze_config_split() {
    local module_status=$(safe_drush pm:list --format=json | jq -r '.config_split.status // "not_installed"')

    if [ "$module_status" != "Enabled" ]; then
        echo "{\"installed\": false, \"status\": \"$module_status\", \"splits\": []}"
        return
    fi

    # Get all config split configurations
    local splits=$(doc drush config:get --format=json config_split.config_split 2>/dev/null | jq -c '.' || echo '{}')

    # Get list of split entities
    local split_list=$(doc drush eval "if (\Drupal::moduleHandler()->moduleExists('config_split')) { \$splits = \Drupal::entityTypeManager()->getStorage('config_split_entity')->loadMultiple(); \$result = []; foreach (\$splits as \$split) { \$result[] = ['id' => \$split->id(), 'label' => \$split->label(), 'status' => \$split->get('status'), 'folder' => \$split->get('folder')]; } echo json_encode(\$result); } else { echo '[]'; }" 2>/dev/null || echo '[]')

    echo "{\"installed\": true, \"status\": \"enabled\", \"splits\": $split_list}"
}

# Function to analyze Config Ignore module
analyze_config_ignore() {
    local module_status=$(safe_drush pm:list --format=json | jq -r '.config_ignore.status // "not_installed"')

    if [ "$module_status" != "Enabled" ]; then
        echo "{\"installed\": false, \"status\": \"$module_status\", \"ignored_configs\": []}"
        return
    fi

    # Get ignored configuration patterns
    local ignored_configs=$(doc drush config:get config_ignore.settings ignored_config_entities --format=json 2>/dev/null | jq -c '.ignored_config_entities // []' || echo '[]')

    echo "{\"installed\": true, \"status\": \"enabled\", \"ignored_configs\": $ignored_configs}"
}

# Note: analyze_config_filter simplified - was returning unused dependent_modules data

# Function to analyze Config Readonly module
analyze_config_readonly() {
    local module_status=$(safe_drush pm:list --format=json | jq -r '.config_readonly.status // "not_installed"')

    if [ "$module_status" != "Enabled" ]; then
        echo "{\"installed\": false, \"status\": \"$module_status\", \"locked\": false}"
        return
    fi

    # Check if config is locked
    local is_locked=$(doc drush eval "echo \Drupal::config('config_readonly.settings')->get('enabled') ? '1' : '0';" 2>/dev/null || echo "0")

    echo "{\"installed\": true, \"status\": \"enabled\", \"locked\": $([ "$is_locked" = "1" ] && echo "true" || echo "false")}"
}

# Function to check Config Devel module (should NOT be in production)
check_config_devel() {
    local module_status=$(safe_drush pm:list --format=json | jq -r '.config_devel.status // "not_installed"')

    local warning=false
    if [ "$module_status" = "Enabled" ]; then
        warning=true
    fi

    echo "{\"installed\": $([ "$module_status" != "not_installed" ] && echo "true" || echo "false"), \"status\": \"$module_status\", \"warning\": $warning}"
}

# Function to check Features module (not recommended for config deployment in D8+)
check_features() {
    local module_status=$(safe_drush pm:list --format=json | jq -r '.features.status // "not_installed"')

    local warning=false
    local message=""
    if [ "$module_status" = "Enabled" ]; then
        warning=true
        message="Features is installed and enabled. In Drupal 8+, Features should only be used for packaging reusable functionality, NOT for config deployment. Use core config management instead."
    fi

    # Get count of features if module is enabled
    local features_count=0
    if [ "$module_status" = "Enabled" ]; then
        features_count=$(doc drush features:list --format=json 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    fi

    echo "{\"installed\": $([ "$module_status" != "not_installed" ] && echo "true" || echo "false"), \"status\": \"$module_status\", \"warning\": $warning, \"message\": \"$message\", \"features_count\": $features_count}"
}

# Universal function to check simple module status
# Usage: check_simple_module <module_machine_name> [include_version]
check_simple_module() {
    local module_name="$1"
    local include_version="${2:-false}"

    local module_status=$(safe_drush pm:list --format=json | jq -r ".$module_name.status // \"not_installed\"")
    local installed=$([ "$module_status" != "not_installed" ] && echo "true" || echo "false")

    if [ "$include_version" = "true" ]; then
        local version=$(safe_drush pm:list --format=json | jq -r ".$module_name.version // \"unknown\"")
        echo "{\"installed\": $installed, \"status\": \"$module_status\", \"version\": \"$version\"}"
    else
        echo "{\"installed\": $installed, \"status\": \"$module_status\"}"
    fi
}

# Function to get config system statistics
get_config_statistics() {
    local config_dir=$(get_config_directory)
    local yml_count=$(find "$config_dir" -name "*.yml" -type f 2>/dev/null | wc -l | tr -d ' ')

    # Get active config count from database
    local db_config_count=$(doc drush sql-query "SELECT COUNT(*) FROM config" 2>/dev/null | grep -E '^[0-9]+$' | head -1 | tr -d ' ')
    if [ -z "$db_config_count" ]; then
        db_config_count="0"
    fi

    # Get config status differences count
    local status_output=$(doc drush config:status --format=json 2>/dev/null || echo '{}')
    status_output=$(echo "$status_output" | sed 's/,\s*}/}/g' | sed 's/,\s*]/]/g')
    local diffs=$(echo "$status_output" | jq 'length' 2>/dev/null || echo "0")

    echo "{\"filesystem_configs\": $yml_count, \"database_configs\": $db_config_count, \"differences\": $diffs}"
}

# Main execution based on mode
case "$MODE" in
    full_analysis)
        CONFIG_DIR=$(get_config_directory)

        # Build modules JSON dynamically
        MODULES_JSON="{"

        # Simple modules with version
        for module in "config" "config_translation" "config_update" "config_update_ui"; do
            MODULES_JSON+="\"$module\": $(check_simple_module "$module" true),"
        done

        # Simple module without version
        MODULES_JSON+="\"config_sync\": $(check_simple_module "config_sync" false),"

        # Complex modules with special handling
        MODULES_JSON+="\"config_split\": $(analyze_config_split),"
        MODULES_JSON+="\"config_ignore\": $(analyze_config_ignore),"
        MODULES_JSON+="\"config_filter\": $(check_simple_module "config_filter" false),"
        MODULES_JSON+="\"config_readonly\": $(analyze_config_readonly),"
        MODULES_JSON+="\"config_devel\": $(check_config_devel),"
        MODULES_JSON+="\"features\": $(check_features)"

        MODULES_JSON+="}"

        cat <<EOF
{
    "config_directory": $(check_config_directory "$CONFIG_DIR"),
    "sync_status": $(check_config_sync_status),
    "modules": $MODULES_JSON,
    "statistics": $(get_config_statistics)
}
EOF
        ;;

    config_directory)
        CONFIG_DIR=$(get_config_directory)
        check_config_directory "$CONFIG_DIR"
        ;;

    sync_status)
        check_config_sync_status
        ;;

    statistics)
        get_config_statistics
        ;;

    *)
        echo "{\"error\": \"Unknown mode: $MODE\"}"
        exit 1
        ;;
esac

