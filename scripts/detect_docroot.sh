#!/bin/bash

# Helper Script: Detect Document Root
# Purpose: Find the correct document root directory (web, htdocs, public, or root)
# Usage: source this file in other scripts, then use $DOCROOT variable
#
# Example usage in other scripts:
#   source ./scripts/detect_docroot.sh
#   ddev exec ls -la $DOCROOT/modules/custom

detect_docroot() {
    # Check common document root directories in order of preference
    # We verify by checking for index.php to ensure it's a valid Drupal root
    local possible_roots=("web" "docroot" "htdocs" "public")

    for root in "${possible_roots[@]}"; do
        # Check if directory exists and contains index.php
        if ddev exec test -f "$root/index.php" 2>/dev/null; then
            echo "$root"
            return 0
        fi
    done

    # Check if index.php is in the root directory (no subdirectory)
    if ddev exec test -f "index.php" 2>/dev/null; then
        echo "."
        return 0
    fi

    # Fallback to 'web' if nothing found (standard Drupal setup)
    echo "web"
    return 1
}

# Export DOCROOT variable for use in scripts
export DOCROOT=$(detect_docroot)

# Optional: Print detection result (comment out in production)
# echo "Detected document root: $DOCROOT" >&2

