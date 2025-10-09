#!/bin/bash

# Script: Database Logs (dblog) Analysis
# Purpose: Analyze errors and warnings from Drupal's database log (watchdog table)
# Note: This script is designed for Drupal 8, 9, 10, 11 ONLY (uses 'watchdog' table)
# Note: Drupal 7 is NOT supported
# Note: DOCROOT variable is passed from audit.sh

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo "{\"error\": \"DOCROOT variable not set\"}" >&2
    exit 1
fi

# Function to export logs to file and analyze
export_and_analyze_logs() {
    # Get site name from DDEV project
    SITE_NAME=$(ddev exec printenv DDEV_SITENAME 2>/dev/null || echo "unknown")
    TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
    LOG_FILE="./tmp/${SITE_NAME}_${TIMESTAMP}_dblog.txt"

    # Create tmp directory if it doesn't exist
    mkdir -p ./tmp

    # Export last 5000 error logs with decoded variables
    ddev drush php-eval "
\$database = \Drupal::database();
\$query = \$database->select('watchdog', 'w')
  ->fields('w', ['wid', 'message', 'variables', 'type', 'severity', 'timestamp', 'hostname', 'location'])
  ->condition('severity', 3, '<=')
  ->orderBy('wid', 'DESC')
  ->range(0, 5000);
\$results = \$query->execute();

\$sev_names = ['Emergency', 'Alert', 'Critical', 'Error'];

foreach (\$results as \$row) {
  \$vars = !empty(\$row->variables) ? @unserialize(\$row->variables) : [];
  if (\$vars === false) \$vars = [];

  // Replace placeholders in message with actual values
  \$decoded_msg = is_array(\$vars) ? strtr(\$row->message, \$vars) : \$row->message;
  // Clean up newlines and special chars
  \$decoded_msg = str_replace([\"\\n\", \"\\r\", \"\\t\", \"|\"], [' ', ' ', ' ', '\\|'], \$decoded_msg);

  \$severity_name = \$sev_names[\$row->severity] ?? 'Severity ' . \$row->severity;
  \$date_time = date('Y-m-d H:i:s', \$row->timestamp);

  // Output format: wid|datetime|type|severity|hostname|location|decoded_message
  echo \$row->wid . '|' . \$date_time . '|' . \$row->type . '|' . \$severity_name . '|' . \$row->hostname . '|' . \$row->location . '|' . \$decoded_msg . PHP_EOL;
}
" > "$LOG_FILE" 2>/dev/null

    echo "$LOG_FILE"
}

# Function to get top frequent errors from exported file
get_top_frequent_errors() {
    local log_file="$1"
    local limit="${2:-50}"

    if [ ! -f "$log_file" ]; then
        echo "[]"
        return
    fi

    # Analyze the exported file
    # Format: wid|datetime|type|severity|hostname|location|message
    # Group by: type|severity|message and count occurrences
    awk -F'|' -v limit="$limit" '
    {
        key = $3 "|" $4 "|" substr($7, 1, 100)
        count[key]++
        if (!(key in last_seen) || $2 > last_seen[key]) {
            last_seen[key] = $2
            type[key] = $3
            severity[key] = $4
            message[key] = substr($7, 1, 200)
        }
    }
    END {
        printf "["
        first = 1
        for (key in count) {
            if (!first) printf ","
            first = 0
            # Escape special characters for JSON
            gsub(/\\/, "\\\\", message[key])
            gsub(/"/, "\\\"", message[key])
            gsub(/\n/, "\\n", message[key])
            gsub(/\r/, "\\r", message[key])
            gsub(/\t/, "\\t", message[key])
            printf "{\"count\":%d,\"type\":\"%s\",\"severity\":\"%s\",\"last_seen\":\"%s\",\"message\":\"%s\"}",
                count[key], type[key], severity[key], last_seen[key], message[key]
        }
        printf "]"
    }' "$log_file" | jq 'sort_by(-.count) | .[0:'"$limit"']'
}

# Function to get errors grouped by type
get_errors_by_type() {
    local log_file="$1"

    if [ ! -f "$log_file" ]; then
        echo "{}"
        return
    fi

    awk -F'|' '
    {
        count[$3]++
    }
    END {
        printf "{"
        first = 1
        for (type in count) {
            if (!first) printf ","
            first = 0
            gsub(/"/, "\\\"", type)
            printf "\"%s\":%d", type, count[type]
        }
        printf "}"
    }' "$log_file"
}

# Function to get errors grouped by severity
get_errors_by_severity() {
    local log_file="$1"

    if [ ! -f "$log_file" ]; then
        echo "{}"
        return
    fi

    awk -F'|' '
    {
        count[$4]++
    }
    END {
        printf "{"
        first = 1
        for (sev in count) {
            if (!first) printf ","
            first = 0
            gsub(/"/, "\\\"", sev)
            printf "\"%s\":%d", sev, count[sev]
        }
        printf "}"
    }' "$log_file"
}

# Function to get recent errors
get_recent_errors() {
    local log_file="$1"
    local limit="${2:-50}"

    if [ ! -f "$log_file" ]; then
        echo "[]"
        return
    fi

    head -"$limit" "$log_file" | awk -F'|' '
    {
        msg = substr($7, 1, 200)
        # Escape special characters for JSON
        gsub(/\\/, "\\\\", msg)
        gsub(/"/, "\\\"", msg)
        gsub(/\n/, "\\n", msg)
        gsub(/\r/, "\\r", msg)
        gsub(/\t/, "\\t", msg)
        printf "{\"datetime\":\"%s\",\"type\":\"%s\",\"severity\":\"%s\",\"message\":\"%s\"},", $2, $3, $4, msg
    }' | sed 's/,$//' | awk 'BEGIN {print "["} {print} END {print "]"}' | jq '.'
}

# Main execution based on argument
case "$1" in
    "full_analysis")
        # Export logs and perform full analysis
        LOG_FILE=$(export_and_analyze_logs)

        if [ -f "$LOG_FILE" ]; then
            LINE_COUNT=$(wc -l < "$LOG_FILE" | tr -d ' ')
            FILE_SIZE=$(du -h "$LOG_FILE" | cut -f1)

            TOP_ERRORS=$(get_top_frequent_errors "$LOG_FILE" 50)
            ERRORS_BY_TYPE=$(get_errors_by_type "$LOG_FILE")
            ERRORS_BY_SEVERITY=$(get_errors_by_severity "$LOG_FILE")
            RECENT_ERRORS=$(get_recent_errors "$LOG_FILE" 50)

            jq -n \
                --arg log_file "$LOG_FILE" \
                --argjson line_count "$LINE_COUNT" \
                --arg file_size "$FILE_SIZE" \
                --argjson top_errors "$TOP_ERRORS" \
                --argjson errors_by_type "$ERRORS_BY_TYPE" \
                --argjson errors_by_severity "$ERRORS_BY_SEVERITY" \
                --argjson recent_errors "$RECENT_ERRORS" \
                '{
                    exported_log_file: $log_file,
                    exported_entries_count: $line_count,
                    exported_file_size: $file_size,
                    top_frequent_errors: $top_errors,
                    errors_grouped_by_type: $errors_by_type,
                    errors_grouped_by_severity: $errors_by_severity,
                    recent_errors: $recent_errors
                }'
        else
            echo "{\"error\": \"Failed to export logs\"}"
        fi
        ;;

    *)
        echo "{\"error\": \"Unknown command: $1\"}" >&2
        exit 1
        ;;
esac
