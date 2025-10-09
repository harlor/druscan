#!/bin/bash

# analyze_accessibility.sh
# Analyzes website accessibility using Pa11y (WCAG 2.1 testing)
# Requires: pa11y (npm install -g pa11y)

# Check if BASE_URL is provided
if [ -z "$1" ]; then
    echo '{"error": "BASE_URL not provided", "homepage": null, "summary": null}'
    exit 0
fi

BASE_URL="$1"

# Check if pa11y is installed
if ! command -v pa11y &> /dev/null; then
    echo '{"error": "Pa11y CLI not installed. Install with: npm install -g pa11y", "homepage": null, "summary": null}'
    exit 0
fi

# Temporary file for pa11y results
TEMP_REPORT="/tmp/pa11y_results_$$.json"

# Function to run pa11y and get results
run_pa11y() {
    local url="$1"
    local standard="WCAG2AA"  # WCAG 2.1 Level AA

    # Run pa11y with JSON reporter
    # Note: pa11y returns exit code 2 when errors are found (this is expected)
    pa11y "$url" \
        --standard "$standard" \
        --reporter json \
        --timeout 30000 \
        > "$TEMP_REPORT" 2>/dev/null

    local exit_code=$?

    # Pa11y exit codes: 0 = no issues, 2 = issues found, other = error
    # We only fail if file doesn't exist or exit code is not 0 or 2
    if [ ! -f "$TEMP_REPORT" ] || [ $exit_code -ne 0 ] && [ $exit_code -ne 2 ]; then
        echo "null"
        return 1
    fi

    # Parse pa11y results
    jq '{
        url: "'$url'",
        standard: "'$standard'",
        timestamp: (now | strftime("%Y-%m-%d %H:%M:%S")),
        total_issues: (. | length),
        errors: [.[] | select(.type == "error") | {
            code: .code,
            message: .message,
            context: .context,
            selector: .selector,
            type: .type,
            typeCode: .typeCode
        }],
        errors_count: ([.[] | select(.type == "error")] | length),
        warnings: [.[] | select(.type == "warning") | {
            code: .code,
            message: .message,
            context: .context,
            selector: .selector,
            type: .type,
            typeCode: .typeCode
        }],
        warnings_count: ([.[] | select(.type == "warning")] | length),
        issues_by_code: ([.[] | .code] | group_by(.) | map({
            code: .[0],
            count: length
        }) | sort_by(-.count)),
        wcag_principles: {
            perceivable: ([.[] | select(.code | contains("WCAG2AA.Principle1"))] | length),
            operable: ([.[] | select(.code | contains("WCAG2AA.Principle2"))] | length),
            understandable: ([.[] | select(.code | contains("WCAG2AA.Principle3"))] | length),
            robust: ([.[] | select(.code | contains("WCAG2AA.Principle4"))] | length)
        }
    }' "$TEMP_REPORT"
}

# Run accessibility analysis on homepage
echo -n '{"url":"'$BASE_URL'","homepage":'
homepage_result=$(run_pa11y "$BASE_URL")
echo -n "$homepage_result"

# Generate summary
if [ "$homepage_result" != "null" ]; then
    echo -n ',"summary":{'

    # Calculate accessibility score (basic calculation)
    total_errors=$(echo "$homepage_result" | jq -r '.errors_count // 0')
    total_warnings=$(echo "$homepage_result" | jq -r '.warnings_count // 0')

    # Simple scoring: 100 - (errors * 5) - (warnings * 2)
    # Cap at 0 minimum
    score=$((100 - (total_errors * 5) - (total_warnings * 2)))
    if [ $score -lt 0 ]; then
        score=0
    fi

    # Determine compliance level
    if [ $total_errors -eq 0 ]; then
        compliance="WCAG 2.1 AA Compliant"
        compliance_status="pass"
    elif [ $total_errors -le 5 ]; then
        compliance="Minor Issues (Near Compliant)"
        compliance_status="warning"
    elif [ $total_errors -le 15 ]; then
        compliance="Multiple Issues (Non-Compliant)"
        compliance_status="fail"
    else
        compliance="Critical Issues (Non-Compliant)"
        compliance_status="critical"
    fi

    echo -n '"accessibility_score":'$score','
    echo -n '"compliance_level":"'$compliance'",'
    echo -n '"compliance_status":"'$compliance_status'",'
    echo -n '"tested_url":"'$BASE_URL'",'
    echo -n '"test_standard":"WCAG 2.1 AA",'
    echo -n '"test_tool":"Pa11y",'
    echo -n '"test_date":"'$(date '+%Y-%m-%d %H:%M:%S')'"'

    echo '}'
else
    echo -n ',"summary":null'
fi

echo '}'

# Cleanup
rm -f "$TEMP_REPORT"

