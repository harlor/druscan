#!/bin/bash

# DRUSCAN - Drupal Backup Strategy Analysis
# Analyzes backup configuration, modules, scripts, and practices
# Supports Drupal 8, 9, 10, 11

set -euo pipefail

# DOCROOT variable is provided by audit.sh (already detected and exported)
# No need to detect it again here

# Initialize result object
RESULT='{}'

# ============================================
# 1. Backup and Migrate Module Analysis
# ============================================

# Check if backup_migrate module is installed
BACKUP_MIGRATE_STATUS=$(ddev drush pm:list --format=json 2>/dev/null | jq -r '.backup_migrate.status // "not_installed"')

BACKUP_MIGRATE_INFO='{}'
if [ "$BACKUP_MIGRATE_STATUS" != "not_installed" ]; then
    # Module is installed, get detailed information
    MODULE_INFO=$(ddev drush pm:list --format=json 2>/dev/null | jq '.backup_migrate // {}')

    # Get version
    VERSION=$(echo "$MODULE_INFO" | jq -r '.version // "unknown"')

    # Get configuration if module is enabled
    if [ "$BACKUP_MIGRATE_STATUS" == "enabled" ]; then
        # List all backup_migrate config objects
        CONFIG_LIST=$(ddev drush config-list 2>/dev/null | grep "backup_migrate" || echo "")

        # Try to get main settings
        MAIN_CONFIG=$(ddev drush config:get backup_migrate.settings --format=json 2>/dev/null || echo '{}')

        # Get backup sources configuration
        SOURCES_CONFIG=$(ddev drush config-list 2>/dev/null | grep "backup_migrate.backup_migrate_source" || echo "")

        # Get backup destinations configuration
        DESTINATIONS_CONFIG=$(ddev drush config-list 2>/dev/null | grep "backup_migrate.backup_migrate_destination" || echo "")

        # Get backup schedules if any
        SCHEDULES_CONFIG=$(ddev drush config-list 2>/dev/null | grep "backup_migrate.backup_migrate_schedule" || echo "")

        # Count configured destinations
        DESTINATIONS_COUNT=$(echo "$DESTINATIONS_CONFIG" | grep -c "backup_migrate.backup_migrate_destination" || echo "0")

        # Count configured schedules
        SCHEDULES_COUNT=$(echo "$SCHEDULES_CONFIG" | grep -c "backup_migrate.backup_migrate_schedule" || echo "0")

        BACKUP_MIGRATE_INFO=$(jq -n \
            --arg status "$BACKUP_MIGRATE_STATUS" \
            --arg version "$VERSION" \
            --argjson main_config "$MAIN_CONFIG" \
            --arg config_list "$CONFIG_LIST" \
            --arg destinations_count "$DESTINATIONS_COUNT" \
            --arg schedules_count "$SCHEDULES_COUNT" \
            '{
                status: $status,
                version: $version,
                main_config: $main_config,
                destinations_count: ($destinations_count | tonumber),
                schedules_count: ($schedules_count | tonumber),
                config_objects: ($config_list | split("\n") | map(select(length > 0)))
            }')
    else
        BACKUP_MIGRATE_INFO=$(jq -n \
            --arg status "$BACKUP_MIGRATE_STATUS" \
            --arg version "$VERSION" \
            '{
                status: $status,
                version: $version,
                note: "Module is installed but not enabled"
            }')
    fi
else
    BACKUP_MIGRATE_INFO=$(jq -n '{status: "not_installed"}')
fi

RESULT=$(echo "$RESULT" | jq --argjson info "$BACKUP_MIGRATE_INFO" '. + {backup_migrate_module: $info}')

# ============================================
# 2. Custom Backup Scripts Detection
# ============================================

BACKUP_SCRIPTS=()

# Search in project root
while IFS= read -r file; do
    if [ -n "$file" ]; then
        BACKUP_SCRIPTS+=("$file")
    fi
done < <(find . -maxdepth 1 -type f \( -name "*backup*.sh" -o -name "*backup*.bash" -o -name "*backup*.py" -o -name "*backup*.pl" \) 2>/dev/null || true)

# Search in /scripts directory
while IFS= read -r file; do
    if [ -n "$file" ]; then
        BACKUP_SCRIPTS+=("$file")
    fi
done < <(find ./scripts -type f \( -name "*backup*.sh" -o -name "*backup*.bash" -o -name "*backup*.py" -o -name "*backup*.pl" \) 2>/dev/null || true)

# Search in .ddev directory
while IFS= read -r file; do
    if [ -n "$file" ]; then
        BACKUP_SCRIPTS+=("$file")
    fi
done < <(find ./.ddev -type f \( -name "*backup*.sh" -o -name "*backup*.bash" -o -name "*snapshot*" -o -name "*backup*.yaml" \) 2>/dev/null || true)

# Convert array to JSON (handle empty array)
if [ ${#BACKUP_SCRIPTS[@]} -eq 0 ]; then
    SCRIPTS_JSON='[]'
else
    SCRIPTS_JSON=$(printf '%s\n' "${BACKUP_SCRIPTS[@]}" | jq -R . | jq -s .)
fi
RESULT=$(echo "$RESULT" | jq --argjson scripts "$SCRIPTS_JSON" '. + {custom_backup_scripts: $scripts}')

# ============================================
# 3. DDEV Snapshots Configuration
# ============================================

DDEV_SNAPSHOTS='{}'
if [ -d ".ddev" ]; then
    # Check if snapshots directory exists
    SNAPSHOTS_DIR_EXISTS="false"
    SNAPSHOTS_COUNT=0

    if [ -d ".ddev/snapshots" ]; then
        SNAPSHOTS_DIR_EXISTS="true"
        SNAPSHOTS_COUNT=$(find .ddev/snapshots -type f 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Check DDEV config for backup-related settings
    DDEV_CONFIG=""
    if [ -f ".ddev/config.yaml" ]; then
        DDEV_CONFIG=$(cat .ddev/config.yaml 2>/dev/null || echo "")
    fi

    DDEV_SNAPSHOTS=$(jq -n \
        --arg exists "$SNAPSHOTS_DIR_EXISTS" \
        --arg count "$SNAPSHOTS_COUNT" \
        --arg config "$DDEV_CONFIG" \
        '{
            snapshots_directory_exists: ($exists == "true"),
            snapshots_count: ($count | tonumber),
            ddev_commands: ["ddev snapshot", "ddev restore-snapshot", "ddev export-db", "ddev import-db"],
            note: "DDEV provides built-in snapshot functionality for local backups"
        }')
fi

RESULT=$(echo "$RESULT" | jq --argjson ddev "$DDEV_SNAPSHOTS" '. + {ddev_snapshots: $ddev}')

# ============================================
# 4. Private Files Path (for backup storage)
# ============================================

PRIVATE_PATH=$(ddev drush php-eval "echo \Drupal::service('file_system')->realpath('private://') ?: 'not_configured';" 2>/dev/null || echo "not_configured")

PRIVATE_PATH_INFO=$(jq -n \
    --arg path "$PRIVATE_PATH" \
    '{
        private_file_path: $path,
        configured: ($path != "not_configured"),
        note: "Private file path is recommended for secure backup storage"
    }')

RESULT=$(echo "$RESULT" | jq --argjson info "$PRIVATE_PATH_INFO" '. + {private_file_path: $info}')

# ============================================
# 5. Composer Scripts for Backup
# ============================================

COMPOSER_BACKUP_SCRIPTS='{}'
if [ -f "composer.json" ]; then
    # Extract scripts section and look for backup-related commands
    BACKUP_RELATED=$(cat composer.json | jq -r '.scripts // {} | to_entries[] | select(.key | test("backup|snapshot|dump|export"; "i")) | "\(.key): \(.value)"' 2>/dev/null || echo "")

    if [ -n "$BACKUP_RELATED" ]; then
        SCRIPTS_ARRAY=$(echo "$BACKUP_RELATED" | jq -R . | jq -s .)
        COMPOSER_BACKUP_SCRIPTS=$(jq -n --argjson scripts "$SCRIPTS_ARRAY" '{backup_scripts: $scripts}')
    else
        COMPOSER_BACKUP_SCRIPTS=$(jq -n '{backup_scripts: [], note: "No backup-related scripts found in composer.json"}')
    fi
fi

RESULT=$(echo "$RESULT" | jq --argjson composer "$COMPOSER_BACKUP_SCRIPTS" '. + {composer_scripts: $composer}')

# ============================================
# 6. Documentation Files Mentioning Backup
# ============================================

BACKUP_DOCS=()

# Search in README files
while IFS= read -r file; do
    if [ -n "$file" ]; then
        # Check if file contains backup-related keywords
        if grep -iq "backup\|restore\|snapshot" "$file" 2>/dev/null; then
            BACKUP_DOCS+=("$file")
        fi
    fi
done < <(find . -maxdepth 2 -type f \( -name "README*" -o -name "DEPLOYMENT*" -o -name "MAINTENANCE*" \) 2>/dev/null || true)

# Convert array to JSON (handle empty array)
if [ ${#BACKUP_DOCS[@]} -eq 0 ]; then
    DOCS_JSON='[]'
else
    DOCS_JSON=$(printf '%s\n' "${BACKUP_DOCS[@]}" | jq -R . | jq -s .)
fi
RESULT=$(echo "$RESULT" | jq --argjson docs "$DOCS_JSON" '. + {documentation_with_backup_info: $docs}')

# ============================================
# 7. Other Backup-Related Modules
# ============================================

# List of other backup-related modules to check
BACKUP_MODULES=(
    "backup_db"
    "backup_files"
    "ultimate_cron"
)

OTHER_MODULES='{}'
for module in "${BACKUP_MODULES[@]}"; do
    STATUS=$(ddev drush pm:list --format=json 2>/dev/null | jq -r ".[\"$module\"].status // \"not_installed\"")
    OTHER_MODULES=$(echo "$OTHER_MODULES" | jq --arg mod "$module" --arg status "$STATUS" '. + {($mod): $status}')
done

RESULT=$(echo "$RESULT" | jq --argjson modules "$OTHER_MODULES" '. + {other_backup_modules: $modules}')

# ============================================
# 8. Database Backup Command Test
# ============================================

# Test if drush sql-dump works (don't actually create backup, just test)
SQL_DUMP_AVAILABLE=$(ddev drush help sql-dump 2>/dev/null && echo "available" || echo "not_available")

DB_BACKUP_INFO=$(jq -n \
    --arg available "$SQL_DUMP_AVAILABLE" \
    '{
        drush_sql_dump: $available,
        note: "Drush sql-dump is the standard command for database backups"
    }')

RESULT=$(echo "$RESULT" | jq --argjson info "$DB_BACKUP_INFO" '. + {database_backup_command: $info}')

# ============================================
# 9. Cron Jobs Detection (Limited in DDEV)
# ============================================

CRON_INFO=$(jq -n '{
    note: "Cron job detection is limited in DDEV environment. Production server analysis needed.",
    recommendation: "Check server crontab with: crontab -l | grep backup"
}')

RESULT=$(echo "$RESULT" | jq --argjson info "$CRON_INFO" '. + {cron_jobs: $info}')

# ============================================
# 10. Summary and Recommendations
# ============================================

# Count findings
SCRIPTS_COUNT=${#BACKUP_SCRIPTS[@]}
DOCS_COUNT=${#BACKUP_DOCS[@]}

# Determine backup strategy level
STRATEGY_LEVEL="none"
if [ "$BACKUP_MIGRATE_STATUS" == "enabled" ] || [ "$SCRIPTS_COUNT" -gt 0 ]; then
    STRATEGY_LEVEL="basic"
fi

if [ "$BACKUP_MIGRATE_STATUS" == "enabled" ] && [ "$SCRIPTS_COUNT" -gt 0 ]; then
    STRATEGY_LEVEL="advanced"
fi

RECOMMENDATIONS=()

if [ "$BACKUP_MIGRATE_STATUS" == "not_installed" ]; then
    RECOMMENDATIONS+=("Consider installing backup_migrate module for automated backups")
fi

if [ "$PRIVATE_PATH" == "not_configured" ]; then
    RECOMMENDATIONS+=("Configure private file path for secure backup storage")
fi

if [ "$SCRIPTS_COUNT" -eq 0 ]; then
    RECOMMENDATIONS+=("Create custom backup scripts for automated backups")
fi

if [ "$DOCS_COUNT" -eq 0 ]; then
    RECOMMENDATIONS+=("Document backup and restore procedures in README or DEPLOYMENT.md")
fi

RECOMMENDATIONS+=("IMPORTANT: Check production server for cron jobs and server-side backup scripts")
RECOMMENDATIONS+=("Verify backup retention policy and offsite storage")
RECOMMENDATIONS+=("Test backup restoration procedure regularly")

RECOMMENDATIONS_JSON=$(printf '%s\n' "${RECOMMENDATIONS[@]}" | jq -R . | jq -s .)

SUMMARY=$(jq -n \
    --arg level "$STRATEGY_LEVEL" \
    --arg scripts_count "$SCRIPTS_COUNT" \
    --arg docs_count "$DOCS_COUNT" \
    --argjson recommendations "$RECOMMENDATIONS_JSON" \
    '{
        backup_strategy_level: $level,
        custom_scripts_found: ($scripts_count | tonumber),
        documentation_found: ($docs_count | tonumber),
        recommendations: $recommendations
    }')

RESULT=$(echo "$RESULT" | jq --argjson summary "$SUMMARY" '. + {summary: $summary}')

# Output final JSON
echo "$RESULT" | jq .

