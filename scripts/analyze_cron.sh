#!/bin/bash
# Script: Analyze Cron Jobs
# Purpose: Generate comprehensive JSON data about Drupal cron system
# Returns: JSON object with cron status, implementations, queue workers, and Ultimate Cron data

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo '{"error": "DOCROOT not set", "status": {}, "modules": {}, "statistics": {}, "hook_cron_implementations": {}, "queue_workers": {}, "ultimate_cron": {}}'
    exit 0
fi

# Initialize result object
RESULT='{
    "status": {
        "last_cron_run_timestamp": 0,
        "last_cron_run_date": "",
        "hours_ago": 0,
        "minutes_ago": 0,
        "seconds_ago": 0,
        "never_run": true
    },
    "modules": {
        "ultimate_cron_enabled": false
    },
    "statistics": {
        "hook_cron_core": 0,
        "hook_cron_contrib": 0,
        "hook_cron_custom": 0,
        "queue_workers_total": 0,
        "queue_workers_cron": 0,
        "ultimate_cron_jobs": 0
    },
    "hook_cron_implementations": {
        "core": [],
        "contrib": [],
        "custom": []
    },
    "queue_workers": {
        "all": [],
        "cron_based": []
    },
    "ultimate_cron": {
        "jobs": [],
        "last_runs": []
    },
    "errors": []
}'

echo "Collecting cron status..." >&2

# Get last cron run information
CRON_STATUS=$(doc drush eval "
\$cron_last = \Drupal::state()->get('system.cron_last');
if (\$cron_last) {
  \$seconds_ago = time() - \$cron_last;
  \$hours = floor(\$seconds_ago / 3600);
  \$minutes = floor((\$seconds_ago % 3600) / 60);

  echo json_encode([
    'last_cron_run_timestamp' => (int) \$cron_last,
    'last_cron_run_date' => date('Y-m-d H:i:s', \$cron_last),
    'hours_ago' => (int) \$hours,
    'minutes_ago' => (int) \$minutes,
    'seconds_ago' => (int) \$seconds_ago,
    'never_run' => false,
  ]);
} else {
  echo json_encode([
    'last_cron_run_timestamp' => 0,
    'last_cron_run_date' => '',
    'hours_ago' => 0,
    'minutes_ago' => 0,
    'seconds_ago' => 0,
    'never_run' => true,
  ]);
}
" 2>/dev/null)

if [ -z "$CRON_STATUS" ] || [ "$CRON_STATUS" = "null" ]; then
    CRON_STATUS='{}'
fi

# Update status in result
RESULT=$(echo "$RESULT" | jq --argjson status "$CRON_STATUS" '.status = $status')

echo "Checking Ultimate Cron module..." >&2

# Check if Ultimate Cron is enabled
ULTIMATE_CRON_ENABLED=$(doc drush eval "echo \Drupal::moduleHandler()->moduleExists('ultimate_cron') ? '1' : '0';" 2>/dev/null)

RESULT=$(echo "$RESULT" | jq --argjson uc_enabled "$ULTIMATE_CRON_ENABLED" '.modules.ultimate_cron_enabled = ($uc_enabled == 1)')

echo "Analyzing hook_cron implementations in core..." >&2

# Find hook_cron implementations in core modules
CORE_CRON_HOOKS="[]"
if [ -d "${DOCROOT}/core/modules" ]; then
    cd "${DOCROOT}/core/modules" || exit 1
    CORE_CRON_HOOKS=$(find . -maxdepth 2 -name "*.module" -type f 2>/dev/null | while IFS= read -r file; do
        if grep -q "function.*_cron(" "$file" 2>/dev/null; then
            module=$(basename "$(dirname "$file")")
            echo "$module"
        fi
    done | jq -R -s 'split("\n") | map(select(length > 0)) | map({module: .})' 2>/dev/null || echo "[]")
fi

echo "Analyzing hook_cron implementations in contrib..." >&2

# Find hook_cron implementations in contrib modules
CONTRIB_CRON_HOOKS="[]"
if [ -d "${DOCROOT}/modules/contrib" ]; then
    cd "${DOCROOT}/modules/contrib" || exit 1
    CONTRIB_CRON_HOOKS=$(find . -maxdepth 2 -name "*.module" -type f 2>/dev/null | while IFS= read -r file; do
        if grep -q "function.*_cron(" "$file" 2>/dev/null; then
            module=$(basename "$(dirname "$file")")
            info_file="$(dirname "$file")/$module.info.yml"
            desc=""
            if [ -f "$info_file" ]; then
                desc=$(grep "^description:" "$info_file" 2>/dev/null | sed 's/description: *//' | sed 's/^["\x27]//' | sed 's/["\x27]$//' | tr -d '\n\r')
            fi
            jq -n --arg mod "$module" --arg description "$desc" '{module: $mod, description: $description}'
        fi
    done | jq -s '.' 2>/dev/null || echo "[]")
fi

echo "Analyzing hook_cron implementations in custom..." >&2

# Find hook_cron implementations in custom modules
CUSTOM_CRON_HOOKS="[]"
if [ -d "${DOCROOT}/modules/custom" ]; then
    cd "${DOCROOT}/modules/custom" || exit 1
    CUSTOM_CRON_HOOKS=$(find . -name "*.module" -o -name "*.php" 2>/dev/null | while IFS= read -r file; do
        if grep -q "function.*_cron(" "$file" 2>/dev/null; then
            module=$(basename "$(dirname "$file")")
            rel_path="${file#./}"
            jq -n --arg mod "$module" --arg path "$rel_path" '{module: $mod, file: $path}'
        fi
    done | jq -s '.' 2>/dev/null || echo "[]")
fi

# Update hook_cron implementations
RESULT=$(echo "$RESULT" | jq \
    --argjson core "$CORE_CRON_HOOKS" \
    --argjson contrib "$CONTRIB_CRON_HOOKS" \
    --argjson custom "$CUSTOM_CRON_HOOKS" \
    '.hook_cron_implementations.core = $core |
    .hook_cron_implementations.contrib = $contrib |
    .hook_cron_implementations.custom = $custom |
    .statistics.hook_cron_core = ($core | length) |
    .statistics.hook_cron_contrib = ($contrib | length) |
    .statistics.hook_cron_custom = ($custom | length)')

echo "Analyzing queue workers..." >&2

# Get all queue workers
QUEUE_WORKERS=$(doc drush eval "
\$queue_manager = \Drupal::service('plugin.manager.queue_worker');
\$workers = \$queue_manager->getDefinitions();

\$all_workers = [];
\$cron_workers = [];

foreach (\$workers as \$id => \$worker) {
  \$worker_data = [
    'id' => \$id,
    'title' => isset(\$worker['title']) ? (string)\$worker['title'] : 'N/A',
    'provider' => isset(\$worker['provider']) ? \$worker['provider'] : 'N/A',
    'runs_on_cron' => isset(\$worker['cron']) && \$worker['cron'] ? true : false,
  ];

  if (isset(\$worker['cron']['time'])) {
    \$worker_data['cron_time_limit'] = \$worker['cron']['time'];
  }

  // Try to get current queue size
  try {
    \$queue = \Drupal::queue(\$id);
    \$worker_data['queue_items'] = \$queue->numberOfItems();
  } catch (Exception \$e) {
    \$worker_data['queue_items'] = null;
  }

  \$all_workers[] = \$worker_data;

  if (\$worker_data['runs_on_cron']) {
    \$cron_workers[] = \$worker_data;
  }
}

echo json_encode([
  'all' => \$all_workers,
  'cron_based' => \$cron_workers,
]);
" 2>/dev/null)

if [ -z "$QUEUE_WORKERS" ] || [ "$QUEUE_WORKERS" = "null" ]; then
    QUEUE_WORKERS='{"all": [], "cron_based": []}'
fi

# Update queue workers
RESULT=$(echo "$RESULT" | jq \
    --argjson workers "$QUEUE_WORKERS" \
    '.queue_workers = $workers |
    .statistics.queue_workers_total = ($workers.all | length) |
    .statistics.queue_workers_cron = ($workers.cron_based | length)')

# Get Ultimate Cron data if module is enabled
if [ "$ULTIMATE_CRON_ENABLED" = "1" ]; then
    echo "Collecting Ultimate Cron jobs..." >&2

    UC_JOBS=$(doc drush eval "
    if (\Drupal::moduleHandler()->moduleExists('ultimate_cron')) {
      \$jobs = \Drupal::entityTypeManager()->getStorage('ultimate_cron_job')->loadMultiple();
      \$jobs_data = [];

      foreach (\$jobs as \$job) {
        \$job_id = \$job->id();
        \$label = \$job->label();
        \$status = \$job->status() ? 'enabled' : 'disabled';

        \$config = \$job->get('configuration');
        \$scheduler_config = isset(\$config['scheduler']) ? \$config['scheduler'] : [];

        \$jobs_data[] = [
          'id' => \$job_id,
          'label' => \$label,
          'status' => \$status,
          'scheduler_config' => \$scheduler_config,
        ];
      }

      echo json_encode(\$jobs_data);
    } else {
      echo '[]';
    }
    " 2>/dev/null)

    if [ -z "$UC_JOBS" ] || [ "$UC_JOBS" = "null" ]; then
        UC_JOBS="[]"
    fi

    echo "Collecting Ultimate Cron last runs..." >&2

    # Get last runs from database
    UC_LAST_RUNS=$(doc drush sql-query "
    SELECT name, start_time, end_time, duration, status, msg
    FROM ultimate_cron_log
    WHERE start_time > 0
    ORDER BY start_time DESC
    LIMIT 20
    " --format=json 2>/dev/null || echo "[]")

    if [ -z "$UC_LAST_RUNS" ] || [ "$UC_LAST_RUNS" = "null" ]; then
        UC_LAST_RUNS="[]"
    fi

    # Update Ultimate Cron data
    RESULT=$(echo "$RESULT" | jq \
        --argjson jobs "$UC_JOBS" \
        --argjson runs "$UC_LAST_RUNS" \
        '.ultimate_cron.jobs = $jobs |
        .ultimate_cron.last_runs = $runs |
        .statistics.ultimate_cron_jobs = ($jobs | length)')
fi

echo "Collecting cron errors..." >&2

# Get recent cron errors from watchdog
CRON_ERRORS=$(doc drush watchdog:show --type=cron --count=10 --format=json 2>/dev/null || echo "[]")

if [ -z "$CRON_ERRORS" ] || [ "$CRON_ERRORS" = "null" ]; then
    CRON_ERRORS="[]"
fi

# Update errors
RESULT=$(echo "$RESULT" | jq --argjson errors "$CRON_ERRORS" '.errors = $errors')

# Output final JSON
echo "$RESULT"
