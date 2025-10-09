#!/bin/bash
# Script: Analyze Multisite and Multi-Domain Configuration
# Purpose: Detect Domain module, Domain Access, and multisite setups
# Returns: JSON object with comprehensive multi-domain and multisite analysis

# Initialize result object
RESULT='{}'

# ============================================
# DOMAIN MODULE DETECTION
# ============================================

# Check if Domain module is installed and enabled
DOMAIN_MODULE_STATUS=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "domain") | .value.status' || echo "not_installed")

# Check for Domain Access module
DOMAIN_ACCESS_STATUS=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "domain_access") | .value.status' || echo "not_installed")

# Check for other Domain-related modules
DOMAIN_RELATED_MODULES=$(ddev drush pm:list --format=json 2>/dev/null | jq '[to_entries[] | select(.key | startswith("domain")) | {module: .key, name: .value.name, status: .value.status, version: .value.version}]' || echo "[]")

# Count domain records in database (if Domain module is active)
if [ "$DOMAIN_MODULE_STATUS" = "enabled" ]; then
    DOMAIN_COUNT=$(ddev drush sql-query "SELECT COUNT(*) FROM domain;" 2>/dev/null | grep -E '^[0-9]+$' | head -1 | tr -d ' ' || echo "0")

    # Get domain records
    DOMAIN_RECORDS=$(ddev drush php-eval "
if (\\Drupal::moduleHandler()->moduleExists('domain')) {
  \$domains = \\Drupal::entityTypeManager()->getStorage('domain')->loadMultiple();
  \$domain_data = [];
  foreach (\$domains as \$domain) {
    \$domain_data[] = [
      'id' => \$domain->id(),
      'hostname' => \$domain->getHostname(),
      'name' => \$domain->label(),
      'scheme' => \$domain->getScheme(),
      'status' => \$domain->status(),
      'is_default' => \$domain->isDefault(),
      'weight' => \$domain->getWeight()
    ];
  }
  echo json_encode(\$domain_data);
} else {
  echo '[]';
}
" 2>/dev/null || echo "[]")
else
    DOMAIN_COUNT="0"
    DOMAIN_RECORDS="[]"
fi

# Build domain module analysis
DOMAIN_ANALYSIS=$(jq -n \
  --arg status "$DOMAIN_MODULE_STATUS" \
  --arg access_status "$DOMAIN_ACCESS_STATUS" \
  --arg count "$DOMAIN_COUNT" \
  --argjson modules "$DOMAIN_RELATED_MODULES" \
  --argjson records "$DOMAIN_RECORDS" \
  '{
    domain_module_installed: (if $status == "enabled" then true elif $status == "disabled" then true else false end),
    domain_module_status: $status,
    domain_access_installed: (if $access_status == "enabled" then true elif $access_status == "disabled" then true else false end),
    domain_access_status: $access_status,
    domain_count: ($count | tonumber),
    domain_records: $records,
    domain_related_modules: $modules
  }')

RESULT=$(echo "$RESULT" | jq --argjson domain "$DOMAIN_ANALYSIS" '. + {domain_module: $domain}')

# ============================================
# MULTISITE DETECTION
# ============================================

# Detect document root
if [ -d "web" ]; then
    DOCROOT="web"
elif [ -d "docroot" ]; then
    DOCROOT="docroot"
else
    DOCROOT="."
fi

# Check if sites directory exists
if [ -d "${DOCROOT}/sites" ]; then
    SITES_DIR_EXISTS=true

    # Count site-specific directories (exclude default, all, and hidden files)
    SITE_DIRS=$(find "${DOCROOT}/sites/" -maxdepth 1 -type d ! -name "sites" ! -name "default" ! -name "all" ! -name ".*" 2>/dev/null | wc -l | tr -d ' ')

    # List site directories with details
    SITE_DIRECTORIES=$(find "${DOCROOT}/sites/" -maxdepth 1 -type d ! -name "sites" ! -name "default" ! -name "all" ! -name ".*" 2>/dev/null | while read -r dir; do
        if [ -n "$dir" ]; then
            DIR_NAME=$(basename "$dir")
            HAS_SETTINGS=$( [ -f "$dir/settings.php" ] && echo "true" || echo "false" )
            HAS_FILES=$( [ -d "$dir/files" ] && echo "true" || echo "false" )
            echo "{\"directory\":\"$DIR_NAME\",\"has_settings\":$HAS_SETTINGS,\"has_files\":$HAS_FILES}"
        fi
    done | jq -s '.' 2>/dev/null || echo "[]")

    # Count settings.php files
    SETTINGS_COUNT=$(find "${DOCROOT}/sites/" -name "settings.php" -type f 2>/dev/null | wc -l | tr -d ' ')

    # Check for sites.php configuration file
    if [ -f "${DOCROOT}/sites/sites.php" ]; then
        SITES_PHP_EXISTS=true

        # Extract non-comment, non-empty lines from sites.php
        SITES_PHP_CONTENT=$(grep -v "^#\|^/\*\|^ \*\|^$" "${DOCROOT}/sites/sites.php" 2>/dev/null | grep -v "^\s*$" | head -20 || echo "")
    else
        SITES_PHP_EXISTS=false
        SITES_PHP_CONTENT=""
    fi

else
    SITES_DIR_EXISTS=false
    SITE_DIRS="0"
    SITE_DIRECTORIES="[]"
    SETTINGS_COUNT="0"
    SITES_PHP_EXISTS=false
    SITES_PHP_CONTENT=""
fi

# Determine multisite status
if [ "$SITE_DIRS" -gt 0 ] || [ "$SITES_PHP_EXISTS" = true ]; then
    MULTISITE_DETECTED=true
    if [ "$SITE_DIRS" -gt 0 ]; then
        MULTISITE_TYPE="directory_based"
    else
        MULTISITE_TYPE="sites_php_only"
    fi
else
    MULTISITE_DETECTED=false
    MULTISITE_TYPE="single_site"
fi

# Build multisite analysis
MULTISITE_ANALYSIS=$(jq -n \
  --argjson exists "$SITES_DIR_EXISTS" \
  --argjson detected "$MULTISITE_DETECTED" \
  --arg type "$MULTISITE_TYPE" \
  --arg site_count "$SITE_DIRS" \
  --argjson directories "$SITE_DIRECTORIES" \
  --arg settings_count "$SETTINGS_COUNT" \
  --argjson sites_php "$SITES_PHP_EXISTS" \
  --arg sites_php_content "$SITES_PHP_CONTENT" \
  '{
    sites_directory_exists: $exists,
    multisite_detected: $detected,
    multisite_type: $type,
    site_directories_count: ($site_count | tonumber),
    site_directories: $directories,
    settings_files_count: ($settings_count | tonumber),
    sites_php_exists: $sites_php,
    sites_php_configuration: (if $sites_php_content != "" then $sites_php_content else null end)
  }')

RESULT=$(echo "$RESULT" | jq --argjson multisite "$MULTISITE_ANALYSIS" '. + {multisite: $multisite}')

# ============================================
# SUMMARY
# ============================================

SUMMARY=$(jq -n \
  --argjson domain_detected "$(echo "$DOMAIN_ANALYSIS" | jq '.domain_module_installed')" \
  --argjson multisite_detected "$MULTISITE_DETECTED" \
  --arg domain_count "$DOMAIN_COUNT" \
  --arg site_count "$SITE_DIRS" \
  '{
    has_multi_domain: $domain_detected,
    has_multisite: $multisite_detected,
    total_domains: ($domain_count | tonumber),
    total_sites: ($site_count | tonumber),
    configuration_type: (
      if $domain_detected and $multisite_detected then "both_domain_and_multisite"
      elif $domain_detected then "domain_module_only"
      elif $multisite_detected then "multisite_only"
      else "single_site_single_domain"
      end
    )
  }')

RESULT=$(echo "$RESULT" | jq --argjson summary "$SUMMARY" '. + {summary: $summary}')

# ============================================
# OUTPUT FINAL JSON
# ============================================

echo "$RESULT"
