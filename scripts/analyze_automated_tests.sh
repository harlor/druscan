#!/bin/bash
# Script: Analyze Automated Tests
# Purpose: Generate comprehensive JSON data about automated tests in Drupal 8+
# Returns: JSON object with test statistics, coverage, and framework configuration

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo '{"error": "DOCROOT not set", "statistics": {}, "frameworks": {}, "phpunit": {}, "behat": {}, "codeception": {}, "coverage": {}, "composer": {}}'
    exit 0
fi

# Initialize result object
RESULT='{
    "statistics": {
        "total_test_files": 0,
        "phpunit_tests": 0,
        "behat_features": 0,
        "codeception_tests": 0,
        "modules_with_tests": 0,
        "total_custom_modules": 0,
        "coverage_percent": 0
    },
    "frameworks": {
        "phpunit_configured": false,
        "behat_configured": false,
        "codeception_configured": false
    },
    "phpunit": {
        "unit_tests": 0,
        "kernel_tests": 0,
        "functional_tests": 0,
        "functional_js_tests": 0,
        "tests_in_custom_modules": [],
        "tests_in_custom_themes": []
    },
    "behat": {
        "feature_files": [],
        "total_features": 0
    },
    "codeception": {
        "cept_files": 0,
        "cest_files": 0,
        "test_files": []
    },
    "coverage": {
        "modules_with_tests": [],
        "modules_without_tests": []
    },
    "composer": {
        "testing_packages": [],
        "test_scripts": []
    }
}'

echo "Checking test framework configurations..." >&2

# Check for PHPUnit configuration
PHPUNIT_CONFIGURED=false
if [ -f "phpunit.xml" ] || [ -f "phpunit.xml.dist" ]; then
    PHPUNIT_CONFIGURED=true
fi

# Check for Behat configuration
BEHAT_CONFIGURED=false
if [ -f "behat.yml" ] || [ -f "behat.yml.dist" ]; then
    BEHAT_CONFIGURED=true
fi

# Check for Codeception configuration
CODECEPTION_CONFIGURED=false
if [ -f "codeception.yml" ] || [ -f "codeception.dist.yml" ]; then
    CODECEPTION_CONFIGURED=true
fi

# Update framework configuration
RESULT=$(echo "$RESULT" | jq \
    --argjson phpunit "$PHPUNIT_CONFIGURED" \
    --argjson behat "$BEHAT_CONFIGURED" \
    --argjson codeception "$CODECEPTION_CONFIGURED" \
    '.frameworks.phpunit_configured = $phpunit |
    .frameworks.behat_configured = $behat |
    .frameworks.codeception_configured = $codeception')

echo "Analyzing PHPUnit tests in custom modules..." >&2

# Count PHPUnit tests by type
CUSTOM_MODULES_PATH="${DOCROOT}/modules/custom"

if [ -d "$CUSTOM_MODULES_PATH" ]; then
    UNIT_COUNT=$(find "$CUSTOM_MODULES_PATH" -path "*/tests/src/Unit/*Test.php" 2>/dev/null | wc -l | tr -d ' ')
    KERNEL_COUNT=$(find "$CUSTOM_MODULES_PATH" -path "*/tests/src/Kernel/*Test.php" 2>/dev/null | wc -l | tr -d ' ')
    FUNCTIONAL_COUNT=$(find "$CUSTOM_MODULES_PATH" -path "*/tests/src/Functional/*Test.php" 2>/dev/null | wc -l | tr -d ' ')
    FUNCTIONAL_JS_COUNT=$(find "$CUSTOM_MODULES_PATH" -path "*/tests/src/FunctionalJavascript/*Test.php" 2>/dev/null | wc -l | tr -d ' ')

    # Collect tests by module
    TESTS_BY_MODULE="[]"
    for module_dir in "$CUSTOM_MODULES_PATH"/*; do
        if [ -d "$module_dir" ]; then
            module_name=$(basename "$module_dir")
            test_count=$(find "$module_dir" -name "*Test.php" 2>/dev/null | wc -l | tr -d ' ')

            if [ "$test_count" -gt 0 ]; then
                unit=$(find "$module_dir" -path "*/tests/src/Unit/*Test.php" 2>/dev/null | wc -l | tr -d ' ')
                kernel=$(find "$module_dir" -path "*/tests/src/Kernel/*Test.php" 2>/dev/null | wc -l | tr -d ' ')
                functional=$(find "$module_dir" -path "*/tests/src/Functional/*Test.php" 2>/dev/null | wc -l | tr -d ' ')
                functional_js=$(find "$module_dir" -path "*/tests/src/FunctionalJavascript/*Test.php" 2>/dev/null | wc -l | tr -d ' ')

                MODULE_TEST=$(jq -n \
                    --arg module "$module_name" \
                    --arg total "$test_count" \
                    --arg unit "$unit" \
                    --arg kernel "$kernel" \
                    --arg functional "$functional" \
                    --arg functional_js "$functional_js" \
                    '{
                        module: $module,
                        total_tests: ($total | tonumber),
                        unit: ($unit | tonumber),
                        kernel: ($kernel | tonumber),
                        functional: ($functional | tonumber),
                        functional_js: ($functional_js | tonumber)
                    }')

                TESTS_BY_MODULE=$(echo "$TESTS_BY_MODULE" | jq --argjson test "$MODULE_TEST" '. + [$test]')
            fi
        fi
    done

    # Update PHPUnit data
    RESULT=$(echo "$RESULT" | jq \
        --arg unit "$UNIT_COUNT" \
        --arg kernel "$KERNEL_COUNT" \
        --arg functional "$FUNCTIONAL_COUNT" \
        --arg functional_js "$FUNCTIONAL_JS_COUNT" \
        --argjson tests_by_module "$TESTS_BY_MODULE" \
        '.phpunit.unit_tests = ($unit | tonumber) |
        .phpunit.kernel_tests = ($kernel | tonumber) |
        .phpunit.functional_tests = ($functional | tonumber) |
        .phpunit.functional_js_tests = ($functional_js | tonumber) |
        .phpunit.tests_in_custom_modules = $tests_by_module')
fi

echo "Analyzing PHPUnit tests in custom themes..." >&2

# Check custom themes for tests
CUSTOM_THEMES_PATH="${DOCROOT}/themes/custom"
THEME_TESTS="[]"

if [ -d "$CUSTOM_THEMES_PATH" ]; then
    for theme_dir in "$CUSTOM_THEMES_PATH"/*; do
        if [ -d "$theme_dir" ]; then
            theme_name=$(basename "$theme_dir")
            test_count=$(find "$theme_dir" -name "*Test.php" 2>/dev/null | wc -l | tr -d ' ')

            if [ "$test_count" -gt 0 ]; then
                THEME_TEST=$(jq -n \
                    --arg theme "$theme_name" \
                    --arg count "$test_count" \
                    '{
                        theme: $theme,
                        test_count: ($count | tonumber)
                    }')

                THEME_TESTS=$(echo "$THEME_TESTS" | jq --argjson test "$THEME_TEST" '. + [$test]')
            fi
        fi
    done

    RESULT=$(echo "$RESULT" | jq --argjson theme_tests "$THEME_TESTS" '.phpunit.tests_in_custom_themes = $theme_tests')
fi

echo "Analyzing Behat feature files..." >&2

# Search for Behat feature files
BEHAT_FEATURES="[]"
BEHAT_COUNT=0

if command -v find >/dev/null 2>&1; then
    while IFS= read -r feature_file; do
        if [ -n "$feature_file" ]; then
            BEHAT_COUNT=$((BEHAT_COUNT + 1))
            rel_path="${feature_file#./}"
            BEHAT_FEATURES=$(echo "$BEHAT_FEATURES" | jq --arg path "$rel_path" '. + [$path]')
        fi
    done < <(find . -name "*.feature" -type f 2>/dev/null | head -50)
fi

RESULT=$(echo "$RESULT" | jq \
    --arg count "$BEHAT_COUNT" \
    --argjson features "$BEHAT_FEATURES" \
    '.behat.total_features = ($count | tonumber) |
    .behat.feature_files = $features')

echo "Analyzing Codeception tests..." >&2

# Search for Codeception test files
CODECEPTION_FILES="[]"
CEPT_COUNT=$(find . -name "*Cept.php" -type f 2>/dev/null | wc -l | tr -d ' ')
CEST_COUNT=$(find . -name "*Cest.php" -type f 2>/dev/null | wc -l | tr -d ' ')

while IFS= read -r test_file; do
    if [ -n "$test_file" ]; then
        rel_path="${test_file#./}"
        CODECEPTION_FILES=$(echo "$CODECEPTION_FILES" | jq --arg path "$rel_path" '. + [$path]')
    fi
done < <(find . \( -name "*Cept.php" -o -name "*Cest.php" \) -type f 2>/dev/null | head -30)

RESULT=$(echo "$RESULT" | jq \
    --arg cept "$CEPT_COUNT" \
    --arg cest "$CEST_COUNT" \
    --argjson files "$CODECEPTION_FILES" \
    '.codeception.cept_files = ($cept | tonumber) |
    .codeception.cest_files = ($cest | tonumber) |
    .codeception.test_files = $files')

echo "Calculating test coverage..." >&2

# Calculate test coverage for custom modules
MODULES_WITH_TESTS="[]"
MODULES_WITHOUT_TESTS="[]"
TOTAL_MODULES=0
MODULES_WITH_TEST_COUNT=0

if [ -d "$CUSTOM_MODULES_PATH" ]; then
    for module_dir in "$CUSTOM_MODULES_PATH"/*; do
        if [ -d "$module_dir" ] && [ "$(basename "$module_dir")" != ".gitkeep" ]; then
            module_name=$(basename "$module_dir")
            TOTAL_MODULES=$((TOTAL_MODULES + 1))
            test_count=$(find "$module_dir" -name "*Test.php" 2>/dev/null | wc -l | tr -d ' ')

            if [ "$test_count" -gt 0 ]; then
                MODULES_WITH_TEST_COUNT=$((MODULES_WITH_TEST_COUNT + 1))
                MODULES_WITH_TESTS=$(echo "$MODULES_WITH_TESTS" | jq --arg mod "$module_name" '. + [$mod]')
            else
                MODULES_WITHOUT_TESTS=$(echo "$MODULES_WITHOUT_TESTS" | jq --arg mod "$module_name" '. + [$mod]')
            fi
        fi
    done
fi

# Calculate coverage percentage
COVERAGE_PERCENT=0
if [ "$TOTAL_MODULES" -gt 0 ]; then
    COVERAGE_PERCENT=$((MODULES_WITH_TEST_COUNT * 100 / TOTAL_MODULES))
fi

RESULT=$(echo "$RESULT" | jq \
    --argjson with_tests "$MODULES_WITH_TESTS" \
    --argjson without_tests "$MODULES_WITHOUT_TESTS" \
    --arg coverage "$COVERAGE_PERCENT" \
    '.coverage.modules_with_tests = $with_tests |
    .coverage.modules_without_tests = $without_tests |
    .statistics.modules_with_tests = ($with_tests | length) |
    .statistics.total_custom_modules = (($with_tests | length) + ($without_tests | length)) |
    .statistics.coverage_percent = ($coverage | tonumber)')

echo "Analyzing composer testing packages..." >&2

# Get testing packages from composer.json
TESTING_PACKAGES="[]"
TEST_SCRIPTS="[]"

if [ -f "composer.json" ]; then
    # Extract testing packages from require-dev
    TESTING_PACKAGES=$(cat composer.json | jq -r '
        .["require-dev"] // {} |
        to_entries |
        map(select(.key | test("phpunit|behat|codeception|phpspec|mockery|browser-kit|css-selector"))) |
        map({package: .key, version: .value})
    ' 2>/dev/null || echo "[]")

    # Extract test scripts
    TEST_SCRIPTS=$(cat composer.json | jq -r '
        .scripts // {} |
        to_entries |
        map(select(.key | test("test|phpunit|behat|codeception"))) |
        map({name: .key, command: .value})
    ' 2>/dev/null || echo "[]")
fi

RESULT=$(echo "$RESULT" | jq \
    --argjson packages "$TESTING_PACKAGES" \
    --argjson scripts "$TEST_SCRIPTS" \
    '.composer.testing_packages = $packages |
    .composer.test_scripts = $scripts')

echo "Calculating final statistics..." >&2

# Calculate total test files
TOTAL_PHPUNIT=0
if [ -d "$CUSTOM_MODULES_PATH" ]; then
    TOTAL_PHPUNIT=$(find "$CUSTOM_MODULES_PATH" -name "*Test.php" 2>/dev/null | wc -l | tr -d ' ')
fi

TOTAL_TESTS=$((TOTAL_PHPUNIT + BEHAT_COUNT + CEPT_COUNT + CEST_COUNT))

RESULT=$(echo "$RESULT" | jq \
    --arg total "$TOTAL_TESTS" \
    --arg phpunit "$TOTAL_PHPUNIT" \
    '.statistics.total_test_files = ($total | tonumber) |
    .statistics.phpunit_tests = ($phpunit | tonumber) |
    .statistics.behat_features = .behat.total_features |
    .statistics.codeception_tests = (.codeception.cept_files + .codeception.cest_files)')

# Output final JSON
echo "$RESULT"
