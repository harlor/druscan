#!/bin/bash
# Analyze security updates with context of enabled/disabled modules
# This provides actionable information for new dev team taking over the project

DOCROOT=${DOCROOT:-web}

# Get composer audit results (accept both exit codes - 0 = no issues, 1 = issues found)
# Save to file inside container to avoid ddev output contamination
doc exec bash -c 'composer audit --format=json > /tmp/audit.json 2>&1 || true' > /dev/null 2>&1
AUDIT_JSON=$(doc exec cat /tmp/audit.json 2>/dev/null || echo '{"advisories":{}}')

# Get list of enabled modules
ENABLED_JSON=$(doc drush pm:list --status=enabled --format=json 2>/dev/null || echo '{}')

# Get list of disabled modules for cleanup recommendations
DISABLED_JSON=$(doc drush pm:list --status=disabled --format=json 2>/dev/null || echo '{}')

# Process with jq
echo "$AUDIT_JSON" | jq --argjson enabled "$ENABLED_JSON" --argjson disabled "$DISABLED_JSON" '
{
  summary: {
    total_vulnerabilities: (if .advisories then (.advisories | length) else 0 end),
    total_enabled_modules: ($enabled | length),
    total_disabled_modules: ($disabled | length),
    vulnerable_packages: (if .advisories then (.advisories | keys) else [] end)
  },
  critical_enabled: (
    if .advisories then
      (.advisories | to_entries | map(
        select((.key | type) == "string") |
        select(.key | startswith("drupal/")) |
        .key as $pkg |
        select($enabled | has($pkg | ltrimstr("drupal/"))) |
        {package: $pkg, module: ($pkg | ltrimstr("drupal/")), advisories: [.value[]]}
      ))
    else [] end
  ),
  info_disabled: (
    if .advisories then
      (.advisories | to_entries | map(
        select((.key | type) == "string") |
        select(.key | startswith("drupal/")) |
        .key as $pkg |
        select($enabled | has($pkg | ltrimstr("drupal/")) | not) |
        {package: $pkg, module: ($pkg | ltrimstr("drupal/")), advisories: [.value[]], is_enabled: false}
      ))
    else [] end
  ),
  non_drupal_vulnerabilities: (
    if .advisories then
      (.advisories | to_entries | map(
        select((.key | type) == "string") |
        select(.key | startswith("drupal/") | not)
      ) | map({
        package: .key,
        advisories: [.value[]]
      }))
    else [] end
  ),
  recommendation: (
    if .advisories and ((.advisories | to_entries | map(select((.key | type) == "string") | select(.key | startswith("drupal/")) | .key as $pkg | select($enabled | has($pkg | ltrimstr("drupal/")))) | length) > 0) then
      "URGENT: Update enabled modules with security vulnerabilities immediately"
    elif .advisories and ((.advisories | length) > 0) then
      "No critical issues in enabled modules. Review disabled modules and non-Drupal dependencies."
    else
      "No security vulnerabilities found"
    end
  ),
  disabled_modules_candidates: (
    $disabled | to_entries | map({
      module: .key,
      name: .value.name,
      package: .value.package
    }) | .[0:20]
  )
}'
