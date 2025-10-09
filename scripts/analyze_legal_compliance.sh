#!/bin/bash

# analyze_legal_compliance.sh
# Analyzes website legal compliance (cookie banners, privacy policy, GDPR)
# Works for Polish and English websites
# Requires: curl

# Check if BASE_URL is provided
if [ -z "$1" ]; then
    echo '{"error": "BASE_URL not provided", "summary": null}'
    exit 0
fi

BASE_URL="$1"

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo '{"error": "curl not installed", "summary": null}'
    exit 0
fi

# Temporary file for page content
TEMP_PAGE="/tmp/legal_compliance_page_$$.html"

# Download the page
curl -s -L --max-time 30 "$BASE_URL" > "$TEMP_PAGE" 2>/dev/null

if [ ! -f "$TEMP_PAGE" ] || [ ! -s "$TEMP_PAGE" ]; then
    echo '{"error": "Failed to download page from BASE_URL", "summary": null}'
    rm -f "$TEMP_PAGE"
    exit 0
fi

# Cookie banner patterns (PL + EN)
COOKIE_PATTERNS=(
    # Polish
    "ciasteczk"
    "cookie"
    "zgoda.*pliki cookie"
    "akceptuj.*cookie"
    "polityk.*cookie"
    "ustawienia.*prywatności"
    "zarządzanie cookie"
    "cookiebanner"
    "cookie-banner"
    "cookie_banner"
    "cookieconsent"
    "cookie-consent"
    # English
    "cookie banner"
    "cookie consent"
    "accept cookies"
    "cookie policy"
    "cookie settings"
    "we use cookies"
    "this site uses cookies"
    "cookies notice"
    "manage cookies"
    # Technical patterns
    "cookielaw"
    "cookie-law"
    "eu-cookie"
    "gdpr-cookie"
    "CookieConsent"
    "cookieNotice"
)

# Privacy policy patterns (PL + EN)
PRIVACY_PATTERNS=(
    # Polish - link text
    "polityka prywatności"
    "polityka prywatnosci"
    "ochrona.*danych"
    "ochrona.*prywatności"
    "polityka.*prywatności"
    "prywatność"
    "dane osobowe"
    # English - link text
    "privacy policy"
    "privacy statement"
    "data protection"
    "privacy notice"
    "personal data"
    # URL patterns
    "/privacy"
    "/privacy-policy"
    "/polityka-prywatnosci"
    "/ochrona-danych"
    "/prywatnosc"
)

# GDPR/RODO patterns
GDPR_PATTERNS=(
    "GDPR"
    "RODO"
    "General Data Protection Regulation"
    "Rozporządzenie.*ochronie.*danych"
)

# Function to check patterns in file
check_patterns() {
    local patterns=("$@")
    local matched=()

    for pattern in "${patterns[@]}"; do
        if grep -iq "$pattern" "$TEMP_PAGE" 2>/dev/null; then
            matched+=("$pattern")
        fi
    done

    echo "${matched[@]}"
}

# Function to extract privacy policy URLs
extract_privacy_urls() {
    # Look for common privacy policy URL patterns in href attributes
    grep -ioE 'href="[^"]*"' "$TEMP_PAGE" 2>/dev/null | \
        grep -iE '(privacy|prywatnosc|polityka-prywatnosci|ochrona-danych)' | \
        sed 's/href="//g' | sed 's/"//g' | \
        head -5 || echo ""
}

# Check cookie banner
cookie_matched=($(check_patterns "${COOKIE_PATTERNS[@]}"))
cookie_detected=false
cookie_confidence="none"

if [ ${#cookie_matched[@]} -gt 0 ]; then
    cookie_detected=true
    if [ ${#cookie_matched[@]} -ge 3 ]; then
        cookie_confidence="high"
    elif [ ${#cookie_matched[@]} -ge 2 ]; then
        cookie_confidence="medium"
    else
        cookie_confidence="low"
    fi
fi

# Check privacy policy
privacy_matched=($(check_patterns "${PRIVACY_PATTERNS[@]}"))
privacy_detected=false
privacy_confidence="none"

if [ ${#privacy_matched[@]} -gt 0 ]; then
    privacy_detected=true
    if [ ${#privacy_matched[@]} -ge 3 ]; then
        privacy_confidence="high"
    elif [ ${#privacy_matched[@]} -ge 2 ]; then
        privacy_confidence="medium"
    else
        privacy_confidence="low"
    fi
fi

# Extract privacy policy URLs
privacy_urls=$(extract_privacy_urls | tr '\n' ',' | sed 's/,$//')

# Check GDPR/RODO mentions
gdpr_matched=($(check_patterns "${GDPR_PATTERNS[@]}"))
gdpr_mentioned=false
if [ ${#gdpr_matched[@]} -gt 0 ]; then
    gdpr_mentioned=true
fi

# Check for common cookie consent libraries (JavaScript)
cookie_libraries=()
if grep -iq "cookiebot" "$TEMP_PAGE" 2>/dev/null; then
    cookie_libraries+=("Cookiebot")
fi
if grep -iq "onetrust" "$TEMP_PAGE" 2>/dev/null; then
    cookie_libraries+=("OneTrust")
fi
if grep -iq "cookie-consent.js\|cookieconsent.js" "$TEMP_PAGE" 2>/dev/null; then
    cookie_libraries+=("CookieConsent")
fi
if grep -iq "quantcast" "$TEMP_PAGE" 2>/dev/null; then
    cookie_libraries+=("Quantcast")
fi
if grep -iq "trustarc" "$TEMP_PAGE" 2>/dev/null; then
    cookie_libraries+=("TrustArc")
fi

# Build JSON array for cookie libraries
cookie_libs_json="[]"
if [ ${#cookie_libraries[@]} -gt 0 ]; then
    cookie_libs_json=$(printf '%s\n' "${cookie_libraries[@]}" | jq -R . | jq -s .)
fi

# Build JSON array for matched terms
cookie_terms_json=$(printf '%s\n' "${cookie_matched[@]}" | head -10 | jq -R . | jq -s . 2>/dev/null || echo '[]')
privacy_terms_json=$(printf '%s\n' "${privacy_matched[@]}" | head -10 | jq -R . | jq -s . 2>/dev/null || echo '[]')
gdpr_terms_json=$(printf '%s\n' "${gdpr_matched[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')

# Build privacy URLs JSON array
privacy_urls_json="[]"
if [ -n "$privacy_urls" ]; then
    privacy_urls_json=$(echo "$privacy_urls" | tr ',' '\n' | jq -R . | jq -s . 2>/dev/null || echo '[]')
fi

# Overall compliance score
compliance_score=0
checks_passed=0

if [ "$cookie_detected" = true ]; then
    compliance_score=$((compliance_score + 40))
    checks_passed=$((checks_passed + 1))
fi
if [ "$privacy_detected" = true ]; then
    compliance_score=$((compliance_score + 40))
    checks_passed=$((checks_passed + 1))
fi
if [ "$gdpr_mentioned" = true ]; then
    compliance_score=$((compliance_score + 20))
    checks_passed=$((checks_passed + 1))
fi

# Compliance status
if [ $compliance_score -ge 80 ]; then
    compliance_status="good"
elif [ $compliance_score -ge 60 ]; then
    compliance_status="fair"
elif [ $compliance_score -ge 40 ]; then
    compliance_status="poor"
else
    compliance_status="critical"
fi

# Build final JSON output
cat << EOF
{
    "url": "$BASE_URL",
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
    "cookie_banner": {
        "detected": $cookie_detected,
        "confidence": "$cookie_confidence",
        "matched_terms": $cookie_terms_json,
        "libraries_detected": $cookie_libs_json
    },
    "privacy_policy": {
        "detected": $privacy_detected,
        "confidence": "$privacy_confidence",
        "matched_terms": $privacy_terms_json,
        "urls_found": $privacy_urls_json
    },
    "gdpr_compliance": {
        "mentioned": $gdpr_mentioned,
        "matched_terms": $gdpr_terms_json
    },
    "summary": {
        "compliance_score": $compliance_score,
        "compliance_status": "$compliance_status",
        "checks_performed": 3,
        "checks_passed": $checks_passed
    }
}
EOF

# Cleanup
rm -f "$TEMP_PAGE"

