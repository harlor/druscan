#!/bin/bash
# Script: Analyze Custom Themes
# Purpose: Generate detailed JSON data for all custom themes
# Returns: JSON array with theme details (name, description, template files, scss, js, regions, etc.)

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo "[]"
    exit 0
fi

# Check if custom themes directory exists
if [ ! -d "${DOCROOT}/themes/custom" ]; then
    echo "[]"
    exit 0
fi

# Initialize JSON array
THEMES_JSON="[]"

cd "${DOCROOT}/themes/custom" || exit 1

for dir in */; do
    if [ -d "$dir" ] && [ "$dir" != "./" ] && [ "$dir" != "../" ]; then
        theme_name=$(basename "$dir")

        # Get theme info from .info.yml
        info_file="$dir$theme_name.info.yml"

        # Get basic theme info
        theme_label=""
        description=""
        base_theme=""
        core_version_requirement=""
        engine="twig"

        if [ -f "$info_file" ]; then
            theme_label=$(grep "^name:" "$info_file" 2>/dev/null | sed 's/name: *//g' | sed "s/['\"]//g" | tr -d '\n\r')
            description=$(grep "^description:" "$info_file" 2>/dev/null | sed 's/description: *//g' | sed "s/['\"]//g" | tr -d '\n\r')
            base_theme=$(grep "^base theme:" "$info_file" 2>/dev/null | sed 's/base theme: *//g' | sed "s/['\"]//g" | tr -d '\n\r')
            core_version_requirement=$(grep "^core_version_requirement:" "$info_file" 2>/dev/null | sed 's/core_version_requirement: *//g' | sed "s/['\"]//g" | tr -d '\n\r')
            engine=$(grep "^engine:" "$info_file" 2>/dev/null | sed 's/engine: *//g' | sed "s/['\"]//g" | tr -d '\n\r')
            [ -z "$engine" ] && engine="twig"
        fi

        # Count template files
        template_files_count=$(find "$dir" -name "*.html.twig" -type f 2>/dev/null | wc -l | tr -d ' ')
        template_files_count=${template_files_count:-0}

        # Count SCSS files (exclude node_modules, vendor)
        scss_files_count=$(find "$dir" -name "*.scss" -type f -not -path "*/node_modules/*" -not -path "*/vendor/*" 2>/dev/null | wc -l | tr -d ' ')
        scss_files_count=${scss_files_count:-0}

        # Count CSS files (exclude node_modules, vendor)
        css_files_count=$(find "$dir" -name "*.css" -type f -not -path "*/node_modules/*" -not -path "*/vendor/*" 2>/dev/null | wc -l | tr -d ' ')
        css_files_count=${css_files_count:-0}

        # Count JS files (exclude node_modules, vendor, dist, build directories)
        js_files_count=$(find "$dir" -name "*.js" -type f -not -path "*/node_modules/*" -not -path "*/vendor/*" -not -path "*/dist/*" -not -path "*/build/*" 2>/dev/null | wc -l | tr -d ' ')
        js_files_count=${js_files_count:-0}

        # Count translation files
        translation_files_count=$(find "$dir" -name "*.po" -type f 2>/dev/null | wc -l | tr -d ' ')
        translation_files_count=${translation_files_count:-0}

        # Get regions from .info.yml
        regions="[]"
        if [ -f "$info_file" ]; then
            # Extract regions section (lines between "regions:" and next top-level key)
            regions=$(awk '/^regions:/{flag=1;next}/^[a-z_]+:/{flag=0}flag{print}' "$info_file" 2>/dev/null | sed 's/^  //g' | sed 's/:.*//' | jq -R -s 'split("\n") | map(select(length > 0))' || echo "[]")
        fi

        # Get libraries from .info.yml
        libraries="[]"
        if [ -f "$info_file" ]; then
            # Extract libraries section
            libraries=$(awk '/^libraries:/{flag=1;next}/^[a-z_]+:/{flag=0}flag{print}' "$info_file" 2>/dev/null | sed 's/^  - //g' | jq -R -s 'split("\n") | map(select(length > 0))' || echo "[]")
        fi

        # Check for package.json (Node.js build system)
        has_package_json=false
        if [ -f "$dir/package.json" ]; then
            has_package_json=true
        fi

        # Check for Gulpfile/Gruntfile
        build_system="none"
        if [ -f "$dir/gulpfile.js" ] || [ -f "$dir/Gulpfile.js" ]; then
            build_system="gulp"
        elif [ -f "$dir/Gruntfile.js" ]; then
            build_system="grunt"
        elif [ -f "$dir/webpack.config.js" ]; then
            build_system="webpack"
        fi

        # Build theme object
        THEME_OBJ=$(jq -n \
            --arg name "$theme_name" \
            --arg label "$theme_label" \
            --arg desc "$description" \
            --arg base "$base_theme" \
            --arg core "$core_version_requirement" \
            --arg engine "$engine" \
            --arg templates "$template_files_count" \
            --arg scss "$scss_files_count" \
            --arg css "$css_files_count" \
            --arg js "$js_files_count" \
            --arg translations "$translation_files_count" \
            --argjson regions "$regions" \
            --argjson libraries "$libraries" \
            --argjson has_pkg "$has_package_json" \
            --arg build "$build_system" \
            '{
                name: $name,
                label: $label,
                description: $desc,
                base_theme: $base,
                core_version_requirement: $core,
                engine: $engine,
                template_files_count: ($templates | tonumber),
                scss_files_count: ($scss | tonumber),
                css_files_count: ($css | tonumber),
                js_files_count: ($js | tonumber),
                translation_files_count: ($translations | tonumber),
                regions: $regions,
                libraries: $libraries,
                has_package_json: $has_pkg,
                build_system: $build
            }')

        # Add to array
        THEMES_JSON=$(echo "$THEMES_JSON" | jq --argjson theme "$THEME_OBJ" '. + [$theme]')
    fi
done

# Output final JSON
echo "$THEMES_JSON"
