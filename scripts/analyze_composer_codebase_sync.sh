#!/bin/bash
# Analyzes synchronization between composer.json/composer.lock and actual codebase
# Detects manually added modules/themes that bypass Composer
# Takes into account transitive dependencies (e.g., from installation profiles like Droopler, Open Intranet)

set -euo pipefail

# Detect document root
if [ -d "web" ]; then
    DOCROOT="web"
elif [ -d "docroot" ]; then
    DOCROOT="docroot"
else
    echo '{"error": "Document root not found"}'
    exit 1
fi

# Initialize result object
result='{
  "summary": {
    "modules_in_filesystem_not_in_composer": 0,
    "themes_in_filesystem_not_in_composer": 0,
    "total_composer_drupal_packages": 0,
    "total_composer_lock_packages": 0,
    "total_contrib_modules": 0,
    "total_contrib_themes": 0,
    "sync_status": "unknown"
  },
  "modules_not_in_composer": [],
  "themes_not_in_composer": [],
  "recommendations": []
}'

# Get list of Drupal packages from composer.json (direct dependencies)
composer_json_packages=$(ddev exec cat composer.json 2>/dev/null | jq -r '.require // {} | to_entries[] | select(.key | startswith("drupal/")) | .key' 2>/dev/null || echo "")

if [ -z "$composer_json_packages" ]; then
    echo '{"error": "Could not read composer.json or no Drupal packages found"}'
    exit 1
fi

# Convert to array for easier processing
composer_json_array=()
while IFS= read -r line; do
    composer_json_array+=("$line")
done <<< "$composer_json_packages"

total_composer_json=$(echo "$composer_json_packages" | wc -l | tr -d ' ')
result=$(echo "$result" | jq --arg total "$total_composer_json" '.summary.total_composer_drupal_packages = ($total | tonumber)')

# Get ALL packages from composer.lock (including transitive dependencies)
# This includes packages installed as dependencies of profiles like Droopler, Open Intranet, etc.
composer_lock_packages=""
if [ -f "composer.lock" ]; then
    composer_lock_packages=$(ddev exec cat composer.lock 2>/dev/null | jq -r '.packages[]? | select(.name | startswith("drupal/")) | .name' 2>/dev/null || echo "")

    if [ -n "$composer_lock_packages" ]; then
        total_lock=$(echo "$composer_lock_packages" | wc -l | tr -d ' ')
        result=$(echo "$result" | jq --arg total "$total_lock" '.summary.total_composer_lock_packages = ($total | tonumber)')
    fi
fi

# Merge composer.json and composer.lock packages (use lock if available, otherwise json)
if [ -n "$composer_lock_packages" ]; then
    all_composer_packages="$composer_lock_packages"
else
    all_composer_packages="$composer_json_packages"
fi

# Convert to array
composer_array=()
while IFS= read -r line; do
    if [ -n "$line" ]; then
        composer_array+=("$line")
    fi
done <<< "$all_composer_packages"

# Check modules/contrib directory
modules_not_in_composer='[]'
if [ -d "${DOCROOT}/modules/contrib" ]; then
    total_modules=$(find "${DOCROOT}/modules/contrib" -maxdepth 1 -type d ! -path "${DOCROOT}/modules/contrib" 2>/dev/null | wc -l | tr -d ' ')
    result=$(echo "$result" | jq --arg total "$total_modules" '.summary.total_contrib_modules = ($total | tonumber)')

    for module_dir in ${DOCROOT}/modules/contrib/*/; do
        if [ -d "$module_dir" ]; then
            module_name=$(basename "$module_dir")
            composer_name="drupal/${module_name}"

            # Check if module is in composer.lock (includes transitive dependencies)
            if ! echo "$all_composer_packages" | grep -q "^${composer_name}$"; then
                # Get module version from .info.yml if available
                info_file=$(find "$module_dir" -maxdepth 1 -name "*.info.yml" | head -1)
                version="unknown"
                if [ -n "$info_file" ]; then
                    version=$(grep -E "^version:" "$info_file" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "unknown")
                fi

                # Check if it's in composer.json (direct) or not at all
                is_direct="false"
                if echo "$composer_json_packages" | grep -q "^${composer_name}$"; then
                    is_direct="true"
                fi

                modules_not_in_composer=$(echo "$modules_not_in_composer" | jq --arg name "$module_name" --arg ver "$version" --arg direct "$is_direct" '. += [{"name": $name, "version": $ver, "path": "modules/contrib", "is_direct_dependency": ($direct == "true")}]')
            fi
        fi
    done
fi

count_modules=$(echo "$modules_not_in_composer" | jq 'length')
result=$(echo "$result" | jq --argjson modules "$modules_not_in_composer" --argjson count "$count_modules" '.modules_not_in_composer = $modules | .summary.modules_in_filesystem_not_in_composer = $count')

# Check themes/contrib directory
themes_not_in_composer='[]'
if [ -d "${DOCROOT}/themes/contrib" ]; then
    total_themes=$(find "${DOCROOT}/themes/contrib" -maxdepth 1 -type d ! -path "${DOCROOT}/themes/contrib" 2>/dev/null | wc -l | tr -d ' ')
    result=$(echo "$result" | jq --arg total "$total_themes" '.summary.total_contrib_themes = ($total | tonumber)')

    for theme_dir in ${DOCROOT}/themes/contrib/*/; do
        if [ -d "$theme_dir" ]; then
            theme_name=$(basename "$theme_dir")
            composer_name="drupal/${theme_name}"

            # Check if theme is in composer.lock (includes transitive dependencies)
            if ! echo "$all_composer_packages" | grep -q "^${composer_name}$"; then
                # Get theme version from .info.yml if available
                info_file=$(find "$theme_dir" -maxdepth 1 -name "*.info.yml" | head -1)
                version="unknown"
                if [ -n "$info_file" ]; then
                    version=$(grep -E "^version:" "$info_file" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "unknown")
                fi

                # Check if it's in composer.json (direct) or not at all
                is_direct="false"
                if echo "$composer_json_packages" | grep -q "^${composer_name}$"; then
                    is_direct="true"
                fi

                themes_not_in_composer=$(echo "$themes_not_in_composer" | jq --arg name "$theme_name" --arg ver "$version" --arg direct "$is_direct" '. += [{"name": $name, "version": $ver, "path": "themes/contrib", "is_direct_dependency": ($direct == "true")}]')
            fi
        fi
    done
fi

count_themes=$(echo "$themes_not_in_composer" | jq 'length')
result=$(echo "$result" | jq --argjson themes "$themes_not_in_composer" --argjson count "$count_themes" '.themes_not_in_composer = $themes | .summary.themes_in_filesystem_not_in_composer = $count')

# Determine sync status
total_issues=$(($count_modules + $count_themes))
if [ $total_issues -eq 0 ]; then
    result=$(echo "$result" | jq '.summary.sync_status = "synced"')
elif [ $total_issues -le 3 ]; then
    result=$(echo "$result" | jq '.summary.sync_status = "minor_issues"')
else
    result=$(echo "$result" | jq '.summary.sync_status = "major_issues"')
fi

# Generate recommendations
recommendations='[]'

# Add info about composer.lock usage
if [ -f "composer.lock" ]; then
    recommendations=$(echo "$recommendations" | jq '. += [{"severity": "info", "title": "Using composer.lock for validation", "description": "Analysis includes ALL packages from composer.lock, including transitive dependencies (e.g., from installation profiles like Droopler, Open Intranet). This ensures accurate detection of manually added modules.", "action": "Keep composer.lock in version control and use composer install (not update) for deployments."}]')
fi

if [ $count_modules -gt 0 ]; then
    recommendations=$(echo "$recommendations" | jq '. += [{"severity": "high", "title": "Manual modules detected", "description": "Found modules in contrib directory not managed by Composer (not in composer.lock). This can cause deployment issues and version conflicts.", "action": "Review modules_not_in_composer list and add them to composer.json using: composer require drupal/MODULE_NAME"}]')
fi

if [ $count_themes -gt 0 ]; then
    recommendations=$(echo "$recommendations" | jq '. += [{"severity": "high", "title": "Manual themes detected", "description": "Found themes in contrib directory not managed by Composer (not in composer.lock). This can cause deployment issues and version conflicts.", "action": "Review themes_not_in_composer list and add them to composer.json using: composer require drupal/THEME_NAME"}]')
fi

if [ $total_issues -eq 0 ]; then
    recommendations=$(echo "$recommendations" | jq '. += [{"severity": "success", "title": "Composer and codebase are synchronized", "description": "All contrib modules and themes are properly managed by Composer. All packages from composer.lock (including transitive dependencies) are accounted for.", "action": "No action needed. Continue using Composer for all package management."}]')
fi

result=$(echo "$result" | jq --argjson recs "$recommendations" '.recommendations = $recs')

# Output final JSON
echo "$result" | jq -c '.'

