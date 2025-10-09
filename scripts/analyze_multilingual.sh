#!/bin/bash
# Script: Analyze Multilingual Support
# Purpose: Generate comprehensive JSON data about multilingual configuration in Drupal 8+
# Returns: JSON object with language configuration, translation modules, and content statistics

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo '{"error": "DOCROOT not set", "multilingual_enabled": false, "languages": [], "modules": {}, "content_statistics": {}}'
    exit 0
fi

# Initialize result object
RESULT='{
    "multilingual_enabled": false,
    "languages": {
        "installed": [],
        "default_language": null,
        "total_count": 0
    },
    "modules": {
        "language": false,
        "content_translation": false,
        "interface_translation": false,
        "config_translation": false
    },
    "content_statistics": {
        "translatable_content_types": [],
        "translated_nodes_count": 0,
        "languages_with_content": []
    },
    "contrib_modules": []
}'

echo "Checking if Language module is enabled..." >&2

# Check if Language module is enabled (foundation for multilingual)
LANGUAGE_ENABLED=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "language") | select(.value.status == "Enabled") | .key' || echo "")

if [ -n "$LANGUAGE_ENABLED" ]; then
    RESULT=$(echo "$RESULT" | jq '.multilingual_enabled = true | .modules.language = true')
    echo "Language module is enabled. Checking other translation modules..." >&2

    # Check Content Translation module
    CONTENT_TRANSLATION=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "content_translation") | select(.value.status == "Enabled") | .key' || echo "")
    if [ -n "$CONTENT_TRANSLATION" ]; then
        RESULT=$(echo "$RESULT" | jq '.modules.content_translation = true')
    fi

    # Check Interface Translation module
    INTERFACE_TRANSLATION=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "locale") | select(.value.status == "Enabled") | .key' || echo "")
    if [ -n "$INTERFACE_TRANSLATION" ]; then
        RESULT=$(echo "$RESULT" | jq '.modules.interface_translation = true')
    fi

    # Check Config Translation module
    CONFIG_TRANSLATION=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "config_translation") | select(.value.status == "Enabled") | .key' || echo "")
    if [ -n "$CONFIG_TRANSLATION" ]; then
        RESULT=$(echo "$RESULT" | jq '.modules.config_translation = true')
    fi

    echo "Fetching installed languages..." >&2

    # Get list of installed languages
    LANGUAGES_DATA=$(ddev drush php-eval "
\$language_manager = \Drupal::languageManager();
\$languages = \$language_manager->getLanguages();
\$default_language = \$language_manager->getDefaultLanguage();
\$language_list = [];

foreach (\$languages as \$langcode => \$language) {
  \$language_list[] = [
    'langcode' => \$langcode,
    'name' => \$language->getName(),
    'direction' => \$language->getDirection(),
    'weight' => \$language->getWeight(),
    'is_default' => (\$langcode === \$default_language->getId())
  ];
}

echo json_encode([
  'languages' => \$language_list,
  'default' => \$default_language->getId(),
  'count' => count(\$language_list)
]);
" 2>/dev/null || echo '{"languages":[],"default":null,"count":0}')

    # Update languages data
    RESULT=$(echo "$RESULT" | jq \
        --argjson langs "$LANGUAGES_DATA" \
        '.languages.installed = $langs.languages |
        .languages.default_language = $langs.default |
        .languages.total_count = $langs.count')

    echo "Analyzing translatable content types..." >&2

    # Get translatable content types and their translation settings
    TRANSLATABLE_TYPES=$(ddev drush php-eval "
\$node_types = \Drupal::entityTypeManager()->getStorage('node_type')->loadMultiple();
\$translatable_types = [];

foreach (\$node_types as \$type_id => \$type) {
  \$is_translatable = \Drupal::service('content_translation.manager')->isEnabled('node', \$type_id);

  if (\$is_translatable) {
    // Count nodes by language for this type
    \$db = \Drupal::database();
    \$query = \$db->query(\"
      SELECT langcode, COUNT(*) as count
      FROM node_field_data
      WHERE type = :type
      GROUP BY langcode
    \", [':type' => \$type_id]);

    \$lang_counts = [];
    foreach (\$query as \$row) {
      \$lang_counts[\$row->langcode] = (int)\$row->count;
    }

    \$translatable_types[] = [
      'type' => \$type_id,
      'label' => \$type->label(),
      'node_counts_by_language' => \$lang_counts
    ];
  }
}

echo json_encode(\$translatable_types);
" 2>/dev/null || echo "[]")

    # Get total count of translated nodes (excluding default language)
    TRANSLATED_NODES=$(ddev drush php-eval "
\$db = \Drupal::database();
\$default_langcode = \Drupal::languageManager()->getDefaultLanguage()->getId();
\$query = \$db->query(\"
  SELECT COUNT(DISTINCT nid) as count
  FROM node_field_data
  WHERE langcode != :default_langcode
\", [':default_langcode' => \$default_langcode]);
\$row = \$query->fetchObject();
echo \$row ? (int)\$row->count : 0;
" 2>/dev/null)

# Ensure it's a valid number
if ! [[ "$TRANSLATED_NODES" =~ ^[0-9]+$ ]]; then
    TRANSLATED_NODES="0"
fi

    # Get languages that have content
    LANGS_WITH_CONTENT=$(ddev drush php-eval "
\$db = \Drupal::database();
\$query = \$db->query(\"
  SELECT langcode, COUNT(*) as count
  FROM node_field_data
  GROUP BY langcode
\");

\$results = [];
foreach (\$query as \$row) {
  \$results[] = [
    'langcode' => \$row->langcode,
    'node_count' => (int)\$row->count
  ];
}

echo json_encode(\$results);
" 2>/dev/null || echo "[]")

    # Update content statistics
    RESULT=$(echo "$RESULT" | jq \
        --argjson types "$TRANSLATABLE_TYPES" \
        --arg translated "$TRANSLATED_NODES" \
        --argjson langs_content "$LANGS_WITH_CONTENT" \
        '.content_statistics.translatable_content_types = $types |
        .content_statistics.translated_nodes_count = ($translated | tonumber) |
        .content_statistics.languages_with_content = $langs_content')

    echo "Checking for contrib multilingual modules..." >&2

    # Check for popular contrib multilingual modules
    CONTRIB_MODULES=$(ddev drush pm:list --status=enabled --format=json 2>/dev/null | jq '[
        to_entries[] |
        select(
            .key == "lingotek" or
            .key == "tmgmt" or
            .key == "entity_translation" or
            .key == "i18n" or
            .key == "translation_views" or
            .key == "language_switcher" or
            .key == "language_cookie" or
            .key == "language_hierarchy"
        ) |
        {
            module: .key,
            name: .value.name,
            version: .value.version,
            package: .value.package
        }
    ]' || echo "[]")

    RESULT=$(echo "$RESULT" | jq --argjson contrib "$CONTRIB_MODULES" '.contrib_modules = $contrib')

else
    echo "Language module is NOT enabled. Multilingual support is disabled." >&2
fi

echo "Analysis complete." >&2

# Output final JSON
echo "$RESULT"
