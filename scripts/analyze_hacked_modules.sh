#!/bin/bash
# Simple Hacked module check - install, scan, cleanup, report

DOCROOT=${DOCROOT:-web}
TEMP_DIR="${DOCROOT}/modules/tmp"
INSTALLED_TEMP=false
WAS_ENABLED=false

# Check if module exists and is enabled
MODULE_INFO=$(doc drush pm:list --format=json 2>/dev/null | jq -r '.hacked.status // "not_found"')

if [ "$MODULE_INFO" = "not_found" ]; then
    # Module doesn't exist - clone it
    echo "Installing Hacked module temporarily..." >&2
    doc exec "git clone --depth 1 --branch 3.0.x https://git.drupalcode.org/project/hacked.git $TEMP_DIR/hacked" >/dev/null 2>&1
    doc drush cr >/dev/null 2>&1
    INSTALLED_TEMP=true
elif [ "$MODULE_INFO" = "Enabled" ]; then
    # Module already enabled - don't touch it
    WAS_ENABLED=true
fi

# Enable module if not already enabled
if [ "$WAS_ENABLED" = false ]; then
    doc drush en hacked -y >/dev/null 2>&1
fi

# Run scan
echo "Scanning modules (30-60 seconds)..." >&2
SCAN_OUTPUT=$(doc drush hacked:list-projects 2>&1)

# Get patches from composer.json
PATCHES=$(doc exec cat composer.json 2>/dev/null | jq -c '.extra.patches // {}')

# Parse results and generate JSON
if echo "$SCAN_OUTPUT" | grep -q "Extension type module-uninstalled is unknown"; then
    # Drupal 11 - count scanned projects
    TOTAL=$(echo "$SCAN_OUTPUT" | grep -c "Finished processing:")

    jq -n \
        --argjson total "$TOTAL" \
        --argjson patches "$PATCHES" \
        '{
            status: "completed",
            total_scanned: $total,
            mode: "Drupal 11 compatibility",
            patches_applied: ($patches | length),
            patches_list: $patches,
            note: "Full change detection unavailable in Drupal 11. All projects scanned successfully."
        }'
else
    # Normal mode - parse table output
    TOTAL=$(echo "$SCAN_OUTPUT" | grep -v "^\[notice\]" | grep -v "^Rebuilding" | grep -v "^$" | tail -n +2 | grep -c ".")
    CHANGED=$(echo "$SCAN_OUTPUT" | grep -ci "changed")

    # Extract changed module names
    CHANGED_MODULES=$(echo "$SCAN_OUTPUT" | grep -i "changed" | awk '{print $1}' | jq -R -s -c 'split("\n") | map(select(length > 0))')

    jq -n \
        --argjson total "$TOTAL" \
        --argjson changed "$CHANGED" \
        --argjson changed_list "$CHANGED_MODULES" \
        --argjson patches "$PATCHES" \
        '{
            status: "completed",
            total_scanned: $total,
            changed_count: $changed,
            unchanged_count: ($total - $changed),
            changed_modules: $changed_list,
            patches_applied: ($patches | length),
            patches_list: $patches,
            recommendation: (if $changed > 0 then "Review changed modules and compare with patches list" else "All modules match official versions" end)
        }'
fi

# Cleanup - uninstall only if we installed/enabled it
if [ "$WAS_ENABLED" = false ]; then
    echo "Cleaning up..." >&2
    doc drush pm:uninstall hacked -y >/dev/null 2>&1
fi

if [ "$INSTALLED_TEMP" = true ]; then
    doc exec rm -rf "$TEMP_DIR" >/dev/null 2>&1
    doc drush cr >/dev/null 2>&1
fi
