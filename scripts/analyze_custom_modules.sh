#!/bin/bash
# Script: Analyze Custom Modules
# Purpose: Generate detailed JSON data for all custom modules
# Returns: JSON array with module details (name, description, routing, lines_of_code)

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo "[]"
    exit 0
fi

# Check if custom modules directory exists
if [ ! -d "${DOCROOT}/modules/custom" ]; then
    echo "[]"
    exit 0
fi

# Initialize JSON array
MODULES_JSON="[]"

cd "${DOCROOT}/modules/custom" || exit 1

for dir in */; do
    if [ -d "$dir" ] && [ "$dir" != "./" ] && [ "$dir" != "../" ]; then
        module_name=$(basename "$dir")

        # Get description from .info.yml
        description=""
        if [ -f "$dir$module_name.info.yml" ]; then
            description=$(grep "^description:" "$dir$module_name.info.yml" 2>/dev/null | sed 's/description: *//g' | sed "s/['\"]//g" | tr -d '\n\r')
        fi

        # Get routing paths
        routing="[]"
        if [ -f "$dir$module_name.routing.yml" ]; then
            routing=$(grep "^  path:" "$dir$module_name.routing.yml" 2>/dev/null | sed 's/^  path: *//g' | sed "s/['\"]//g" | jq -R -s 'split("\n") | map(select(length > 0))' || echo "[]")
        fi

        # Count total lines of code
        lines_of_code=$(find "$dir" -type f \( -name "*.php" -o -name "*.module" -o -name "*.inc" -o -name "*.install" \) 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
        lines_of_code=${lines_of_code:-0}

        # Count lines in .module file
        module_file_lines=0
        if [ -f "$dir$module_name.module" ]; then
            module_file_lines=$(wc -l < "$dir$module_name.module" 2>/dev/null | tr -d ' ' || echo "0")
        fi

        # Extract function names from .module file
        module_functions="[]"
        if [ -f "$dir$module_name.module" ]; then
            module_functions=$(grep "^function " "$dir$module_name.module" 2>/dev/null | sed 's/function \([a-zA-Z0-9_]*\).*/\1/' | jq -R -s 'split("\n") | map(select(length > 0))' || echo "[]")
        fi

        # Check for custom entities
        has_custom_entities=false
        custom_entities_list="[]"
        if [ -d "$dir/src/Entity" ]; then
            # Check for entity annotations
            entity_files=$(find "$dir/src/Entity" -name "*.php" -type f 2>/dev/null)
            if [ -n "$entity_files" ]; then
                for entity_file in $entity_files; do
                    if grep -q "@ContentEntityType\|@ConfigEntityType" "$entity_file" 2>/dev/null; then
                        has_custom_entities=true
                        entity_name=$(basename "$entity_file" .php)
                        custom_entities_list=$(echo "$custom_entities_list" | jq --arg name "$entity_name" '. + [$name]')
                    fi
                done
            fi
        fi

        # Build module object
        MODULE_OBJ=$(jq -n \
            --arg name "$module_name" \
            --arg desc "$description" \
            --argjson routes "$routing" \
            --arg lines "$lines_of_code" \
            --arg mod_lines "$module_file_lines" \
            --argjson functions "$module_functions" \
            --argjson has_entities "$has_custom_entities" \
            --argjson entities "$custom_entities_list" \
            '{
                name: $name,
                description: $desc,
                routing: $routes,
                lines_of_code: ($lines | tonumber),
                module_file_lines: ($mod_lines | tonumber),
                module_functions: $functions,
                has_custom_entities: $has_entities,
                custom_entities: $entities
            }')

        # Add to array
        MODULES_JSON=$(echo "$MODULES_JSON" | jq --argjson module "$MODULE_OBJ" '. + [$module]')
    fi
done

# Output final JSON
echo "$MODULES_JSON"
