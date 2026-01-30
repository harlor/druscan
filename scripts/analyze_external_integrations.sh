#!/bin/bash
# Script: Analyze External Integrations
# Purpose: Generate comprehensive JSON data about external system integrations
# Returns: JSON object with modules, REST, JSON:API, OAuth, webhooks, queues, HTTP clients, and third-party services

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo '{"error": "DOCROOT not set", "modules": {}, "statistics": {}, "rest": {}, "jsonapi": {}, "oauth": {}, "webhooks": {}, "queue_workers": [], "http_clients": {}, "third_party": {}, "payment_gateways": {}, "email_services": {}, "social_media": {}, "analytics": {}, "search_services": {}, "external_storage": {}}'
    exit 0
fi

# Initialize result object
RESULT='{
    "modules": {
        "integration_related": [],
        "rest_enabled": false,
        "jsonapi_enabled": false,
        "oauth_modules": [],
        "webhook_modules": []
    },
    "statistics": {
        "integration_modules": 0,
        "rest_resources": 0,
        "jsonapi_endpoints": 0,
        "queue_workers": 0,
        "http_client_files": 0,
        "third_party_libraries": 0
    },
    "rest": {
        "enabled": false,
        "resources": [],
        "settings": {}
    },
    "jsonapi": {
        "enabled": false,
        "endpoints": [],
        "settings": {}
    },
    "oauth": {
        "modules": [],
        "configurations": []
    },
    "webhooks": {
        "modules": [],
        "routes": []
    },
    "queue_workers": [],
    "http_clients": {
        "guzzle_files": [],
        "curl_files": [],
        "file_get_contents_files": []
    },
    "third_party": {
        "libraries": []
    },
    "payment_gateways": {
        "modules": [],
        "configurations": []
    },
    "email_services": {
        "modules": [],
        "configurations": []
    },
    "social_media": {
        "modules": []
    },
    "analytics": {
        "modules": [],
        "google_analytics_config": {}
    },
    "search_services": {
        "modules": [],
        "servers": []
    },
    "external_storage": {
        "modules": []
    }
}'

echo "Collecting integration-related modules..." >&2

# Get modules with API/REST/Integration keywords
INTEGRATION_MODULES=$(doc drush eval "
\$module_list = \Drupal::service('extension.list.module');
\$keywords = ['api', 'rest', 'json', 'oauth', 'soap', 'webservice', 'webhook', 'integration', 'external', 'http'];

\$result = [];
\$modules = \$module_list->getAllAvailableInfo();
foreach (\$modules as \$machine_name => \$info) {
  \$name_lower = strtolower(\$machine_name);
  \$desc_lower = strtolower(\$info['description'] ?? '');

  foreach (\$keywords as \$keyword) {
    if (strpos(\$name_lower, \$keyword) !== false || strpos(\$desc_lower, \$keyword) !== false) {
      \$result[] = [
        'machine_name' => \$machine_name,
        'name' => \$info['name'] ?? \$machine_name,
        'description' => substr(\$info['description'] ?? '', 0, 100),
        'package' => \$info['package'] ?? 'Other',
        'enabled' => \Drupal::moduleHandler()->moduleExists(\$machine_name),
      ];
      break;
    }
  }
}

echo json_encode(\$result);
" 2>/dev/null)

if [ -z "$INTEGRATION_MODULES" ] || [ "$INTEGRATION_MODULES" = "null" ]; then
    INTEGRATION_MODULES="[]"
fi

RESULT=$(echo "$RESULT" | jq \
    --argjson modules "$INTEGRATION_MODULES" \
    '.modules.integration_related = $modules | .statistics.integration_modules = ($modules | length)')

echo "Checking REST module..." >&2

# Check if REST module is enabled
REST_ENABLED=$(doc drush eval "echo \Drupal::moduleHandler()->moduleExists('rest') ? '1' : '0';" 2>/dev/null)

RESULT=$(echo "$RESULT" | jq \
    --argjson rest "$REST_ENABLED" \
    '.modules.rest_enabled = ($rest == 1) | .rest.enabled = ($rest == 1)')

# Get REST resources if enabled
if [ "$REST_ENABLED" = "1" ]; then
    echo "Collecting REST resources..." >&2

    REST_RESOURCES=$(doc drush eval "
    \$config_factory = \Drupal::configFactory();
    \$config_names = \$config_factory->listAll('rest.resource.');
    \$resources = [];

    foreach (\$config_names as \$config_name) {
      \$config = \$config_factory->get(\$config_name);
      \$resource_id = str_replace('rest.resource.', '', \$config_name);

      \$resources[] = [
        'id' => \$resource_id,
        'plugin_id' => \$config->get('plugin_id'),
        'granularity' => \$config->get('granularity'),
        'configuration' => \$config->get('configuration'),
      ];
    }

    echo json_encode(\$resources);
    " 2>/dev/null || echo "[]")

    if [ -z "$REST_RESOURCES" ] || [ "$REST_RESOURCES" = "null" ]; then
        REST_RESOURCES="[]"
    fi

    RESULT=$(echo "$RESULT" | jq \
        --argjson resources "$REST_RESOURCES" \
        '.rest.resources = $resources | .statistics.rest_resources = ($resources | length)')
fi

echo "Checking JSON:API module..." >&2

# Check if JSON:API module is enabled
JSONAPI_ENABLED=$(doc drush eval "echo \Drupal::moduleHandler()->moduleExists('jsonapi') ? '1' : '0';" 2>/dev/null)

RESULT=$(echo "$RESULT" | jq \
    --argjson jsonapi "$JSONAPI_ENABLED" \
    '.modules.jsonapi_enabled = ($jsonapi == 1) | .jsonapi.enabled = ($jsonapi == 1)')

# Get JSON:API endpoints if enabled
if [ "$JSONAPI_ENABLED" = "1" ]; then
    echo "Collecting JSON:API endpoints..." >&2

    JSONAPI_ENDPOINTS=$(doc drush eval "
    \$endpoints = [];

    // Get content types
    \$node_types = \Drupal::entityTypeManager()->getStorage('node_type')->loadMultiple();
    foreach (\$node_types as \$type) {
      \$endpoints[] = [
        'entity_type' => 'node',
        'bundle' => \$type->id(),
        'bundle_label' => \$type->label(),
        'path' => '/jsonapi/node/' . \$type->id(),
      ];
    }

    // Get media bundles
    if (\Drupal::moduleHandler()->moduleExists('media')) {
      \$media_types = \Drupal::entityTypeManager()->getStorage('media_type')->loadMultiple();
      foreach (\$media_types as \$type) {
        \$endpoints[] = [
          'entity_type' => 'media',
          'bundle' => \$type->id(),
          'bundle_label' => \$type->label(),
          'path' => '/jsonapi/media/' . \$type->id(),
        ];
      }
    }

    // Get taxonomy vocabularies
    \$vocabularies = \Drupal::entityTypeManager()->getStorage('taxonomy_vocabulary')->loadMultiple();
    foreach (\$vocabularies as \$vocab) {
      \$endpoints[] = [
        'entity_type' => 'taxonomy_term',
        'bundle' => \$vocab->id(),
        'bundle_label' => \$vocab->label(),
        'path' => '/jsonapi/taxonomy_term/' . \$vocab->id(),
      ];
    }

    // User endpoint
    \$endpoints[] = [
      'entity_type' => 'user',
      'bundle' => 'user',
      'bundle_label' => 'User',
      'path' => '/jsonapi/user/user',
    ];

    echo json_encode(\$endpoints);
    " 2>/dev/null || echo "[]")

    if [ -z "$JSONAPI_ENDPOINTS" ] || [ "$JSONAPI_ENDPOINTS" = "null" ]; then
        JSONAPI_ENDPOINTS="[]"
    fi

    RESULT=$(echo "$RESULT" | jq \
        --argjson endpoints "$JSONAPI_ENDPOINTS" \
        '.jsonapi.endpoints = $endpoints | .statistics.jsonapi_endpoints = ($endpoints | length)')
fi

echo "Collecting OAuth/Authentication modules..." >&2

# Get OAuth/Auth modules
OAUTH_MODULES=$(doc drush pm:list --status=enabled --format=json 2>/dev/null | jq '[to_entries[] | select(.key | test("oauth|saml|ldap|openid|sso"; "i")) | {machine_name: .key, name: .value.name, status: .value.status}]' || echo "[]")

if [ -z "$OAUTH_MODULES" ] || [ "$OAUTH_MODULES" = "null" ]; then
    OAUTH_MODULES="[]"
fi

RESULT=$(echo "$RESULT" | jq \
    --argjson oauth "$OAUTH_MODULES" \
    '.modules.oauth_modules = $oauth | .oauth.modules = $oauth')

echo "Collecting webhook modules..." >&2

# Get webhook modules
WEBHOOK_MODULES=$(doc drush pm:list --status=enabled --format=json 2>/dev/null | jq '[to_entries[] | select(.key | test("webhook"; "i")) | {machine_name: .key, name: .value.name, status: .value.status}]' || echo "[]")

if [ -z "$WEBHOOK_MODULES" ] || [ "$WEBHOOK_MODULES" = "null" ]; then
    WEBHOOK_MODULES="[]"
fi

RESULT=$(echo "$RESULT" | jq \
    --argjson webhooks "$WEBHOOK_MODULES" \
    '.modules.webhook_modules = $webhooks | .webhooks.modules = $webhooks')

# Search for webhook routes in custom modules
echo "Searching webhook routes in custom modules..." >&2

WEBHOOK_ROUTES="[]"
if [ -d "${DOCROOT}/modules/custom" ]; then
    cd "${DOCROOT}/modules/custom" || exit 1
    WEBHOOK_ROUTES=$(find . -name "*.routing.yml" -type f 2>/dev/null | while IFS= read -r file; do
        if grep -q "webhook" "$file" 2>/dev/null; then
            module=$(basename "$(dirname "$file")")
            routes=$(grep -A 3 "webhook" "$file" 2>/dev/null | grep -E "^[a-z_]+:" | sed 's/:$//')
            for route in $routes; do
                jq -n --arg mod "$module" --arg r "$route" --arg f "$file" '{module: $mod, route: $r, file: $f}'
            done
        fi
    done | jq -s '.' 2>/dev/null || echo "[]")
fi

if [ -z "$WEBHOOK_ROUTES" ] || [ "$WEBHOOK_ROUTES" = "null" ]; then
    WEBHOOK_ROUTES="[]"
fi

RESULT=$(echo "$RESULT" | jq --argjson routes "$WEBHOOK_ROUTES" '.webhooks.routes = $routes')

echo "Collecting queue workers..." >&2

# Get all queue workers (integration points)
QUEUE_WORKERS=$(doc drush eval "
\$queue_manager = \Drupal::service('plugin.manager.queue_worker');
\$workers = \$queue_manager->getDefinitions();
\$result = [];

foreach (\$workers as \$id => \$worker) {
  \$result[] = [
    'id' => \$id,
    'title' => isset(\$worker['title']) ? (string)\$worker['title'] : 'N/A',
    'provider' => isset(\$worker['provider']) ? \$worker['provider'] : 'N/A',
    'runs_on_cron' => isset(\$worker['cron']) && \$worker['cron'] ? true : false,
  ];
}

echo json_encode(\$result);
" 2>/dev/null)

if [ -z "$QUEUE_WORKERS" ] || [ "$QUEUE_WORKERS" = "null" ]; then
    QUEUE_WORKERS="[]"
fi

RESULT=$(echo "$RESULT" | jq \
    --argjson workers "$QUEUE_WORKERS" \
    '.queue_workers = $workers | .statistics.queue_workers = ($workers | length)')

echo "Searching HTTP client usage in custom code..." >&2

# Search for Guzzle HTTP client usage
GUZZLE_FILES="[]"
if [ -d "${DOCROOT}/modules/custom" ]; then
    cd "${DOCROOT}/modules/custom" || exit 1
    GUZZLE_FILES=$(grep -r "GuzzleHttp\|->request(\|use.*HttpClient" . --include="*.php" --include="*.module" -l 2>/dev/null | head -20 | jq -R -s 'split("\n") | map(select(length > 0)) | map({file: .})' || echo "[]")
fi

if [ -z "$GUZZLE_FILES" ] || [ "$GUZZLE_FILES" = "null" ]; then
    GUZZLE_FILES="[]"
fi

# Search for cURL usage
CURL_FILES="[]"
if [ -d "${DOCROOT}/modules/custom" ]; then
    cd "${DOCROOT}/modules/custom" || exit 1
    CURL_FILES=$(grep -r "curl_init\|curl_exec\|curl_setopt" . --include="*.php" --include="*.module" -l 2>/dev/null | head -20 | jq -R -s 'split("\n") | map(select(length > 0)) | map({file: .})' || echo "[]")
fi

if [ -z "$CURL_FILES" ] || [ "$CURL_FILES" = "null" ]; then
    CURL_FILES="[]"
fi

# Search for file_get_contents with URLs
FILE_GET_CONTENTS_FILES="[]"
if [ -d "${DOCROOT}/modules/custom" ]; then
    cd "${DOCROOT}/modules/custom" || exit 1
    FILE_GET_CONTENTS_FILES=$(grep -r "file_get_contents.*http" . --include="*.php" --include="*.module" -l 2>/dev/null | head -20 | jq -R -s 'split("\n") | map(select(length > 0)) | map({file: .})' || echo "[]")
fi

if [ -z "$FILE_GET_CONTENTS_FILES" ] || [ "$FILE_GET_CONTENTS_FILES" = "null" ]; then
    FILE_GET_CONTENTS_FILES="[]"
fi

HTTP_CLIENT_COUNT=$(echo "$GUZZLE_FILES" "$CURL_FILES" "$FILE_GET_CONTENTS_FILES" | jq -s 'add | unique | length' 2>/dev/null || echo "0")

RESULT=$(echo "$RESULT" | jq \
    --argjson guzzle "$GUZZLE_FILES" \
    --argjson curl "$CURL_FILES" \
    --argjson file_get "$FILE_GET_CONTENTS_FILES" \
    --argjson count "$HTTP_CLIENT_COUNT" \
    '.http_clients.guzzle_files = $guzzle |
    .http_clients.curl_files = $curl |
    .http_clients.file_get_contents_files = $file_get |
    .statistics.http_client_files = $count')

echo "Collecting third-party libraries..." >&2

# Get third-party libraries from composer.json
THIRD_PARTY_LIBS="[]"
if [ -f "composer.json" ]; then
    THIRD_PARTY_LIBS=$(cat composer.json | jq '[.require // {} | to_entries[] | select(.key | test("^drupal/|^php$|^composer/") | not) | {name: .key, version: .value}]' 2>/dev/null || echo "[]")
fi

if [ -z "$THIRD_PARTY_LIBS" ] || [ "$THIRD_PARTY_LIBS" = "null" ]; then
    THIRD_PARTY_LIBS="[]"
fi

RESULT=$(echo "$RESULT" | jq \
    --argjson libs "$THIRD_PARTY_LIBS" \
    '.third_party.libraries = $libs | .statistics.third_party_libraries = ($libs | length)')

echo "Collecting payment gateway modules..." >&2

# Get payment/commerce modules
PAYMENT_MODULES=$(doc drush pm:list --status=enabled --format=json 2>/dev/null | jq '[to_entries[] | select(.key | test("commerce|payment|stripe|paypal|authorize"; "i")) | {machine_name: .key, name: .value.name, package: .value.package}]' || echo "[]")

if [ -z "$PAYMENT_MODULES" ] || [ "$PAYMENT_MODULES" = "null" ]; then
    PAYMENT_MODULES="[]"
fi

RESULT=$(echo "$RESULT" | jq --argjson payment "$PAYMENT_MODULES" '.payment_gateways.modules = $payment')

echo "Collecting email service modules..." >&2

# Get email-related modules
EMAIL_MODULES=$(doc drush pm:list --status=enabled --format=json 2>/dev/null | jq '[to_entries[] | select(.key | test("smtp|mail|sendgrid|mailchimp|postmark"; "i")) | {machine_name: .key, name: .value.name, package: .value.package}]' || echo "[]")

if [ -z "$EMAIL_MODULES" ] || [ "$EMAIL_MODULES" = "null" ]; then
    EMAIL_MODULES="[]"
fi

RESULT=$(echo "$RESULT" | jq --argjson email "$EMAIL_MODULES" '.email_services.modules = $email')

echo "Collecting social media modules..." >&2

# Get social media modules
SOCIAL_MODULES=$(doc drush pm:list --status=enabled --format=json 2>/dev/null | jq '[to_entries[] | select(.key | test("social|facebook|twitter|linkedin|instagram"; "i")) | {machine_name: .key, name: .value.name, package: .value.package}]' || echo "[]")

if [ -z "$SOCIAL_MODULES" ] || [ "$SOCIAL_MODULES" = "null" ]; then
    SOCIAL_MODULES="[]"
fi

RESULT=$(echo "$RESULT" | jq --argjson social "$SOCIAL_MODULES" '.social_media.modules = $social')

echo "Collecting analytics modules..." >&2

# Get analytics modules
ANALYTICS_MODULES=$(doc drush pm:list --status=enabled --format=json 2>/dev/null | jq '[to_entries[] | select(.key | test("google.*analytics|gtm|matomo|piwik|tracking"; "i")) | {machine_name: .key, name: .value.name, package: .value.package}]' || echo "[]")

if [ -z "$ANALYTICS_MODULES" ] || [ "$ANALYTICS_MODULES" = "null" ]; then
    ANALYTICS_MODULES="[]"
fi

RESULT=$(echo "$RESULT" | jq --argjson analytics "$ANALYTICS_MODULES" '.analytics.modules = $analytics')

echo "Collecting search service modules..." >&2

# Get search-related modules
SEARCH_MODULES=$(doc drush pm:list --status=enabled --format=json 2>/dev/null | jq '[to_entries[] | select(.key | test("search.*api|solr|elasticsearch|algolia"; "i")) | {machine_name: .key, name: .value.name, package: .value.package}]' || echo "[]")

if [ -z "$SEARCH_MODULES" ] || [ "$SEARCH_MODULES" = "null" ]; then
    SEARCH_MODULES="[]"
fi

RESULT=$(echo "$RESULT" | jq --argjson search "$SEARCH_MODULES" '.search_services.modules = $search')

echo "Collecting external storage modules..." >&2

# Get external storage modules
STORAGE_MODULES=$(doc drush pm:list --status=enabled --format=json 2>/dev/null | jq '[to_entries[] | select(.key | test("s3|azure|cdn|cloudflare|akamai"; "i")) | {machine_name: .key, name: .value.name, package: .value.package}]' || echo "[]")

if [ -z "$STORAGE_MODULES" ] || [ "$STORAGE_MODULES" = "null" ]; then
    STORAGE_MODULES="[]"
fi

RESULT=$(echo "$RESULT" | jq --argjson storage "$STORAGE_MODULES" '.external_storage.modules = $storage')

# Output final JSON
echo "$RESULT"
