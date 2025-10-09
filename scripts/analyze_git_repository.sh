#!/bin/bash
# Git Repository Analysis Script
# Comprehensive analysis of git repository for project audit
# Author: DRUSCAN
# Date: 2025-10-08

set -euo pipefail

# Check if .git directory exists
if [ ! -d ".git" ]; then
    echo '{"git_enabled": false, "message": "No git repository found in project"}'
    exit 0
fi

# Initialize JSON structure
JSON_OUTPUT='{
  "git_enabled": true,
  "repository_info": {},
  "branches": {},
  "commits": {},
  "contributors": {},
  "workflow": {},
  "repository_health": {},
  "recommendations": []
}'

# Get repository root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

# ============================================
# Repository Basic Info
# ============================================
get_repo_info() {
    local remote_url=$(git remote get-url origin 2>/dev/null || echo "No remote configured")
    local repo_size=$(du -sh .git 2>/dev/null | cut -f1 || echo "unknown")
    local current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    local total_commits=$(git rev-list --all --count 2>/dev/null || echo "0")

    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --arg url "$remote_url" \
        --arg size "$repo_size" \
        --arg branch "$current_branch" \
        --arg commits "$total_commits" \
        '.repository_info = {
            "remote_url": $url,
            "repository_size": $size,
            "current_branch": $branch,
            "total_commits": ($commits | tonumber)
        }')
}

# ============================================
# Branches Analysis
# ============================================
get_branches() {
    # Get all branches
    local all_branches=$(git branch -a 2>/dev/null | sed 's/^\* //g' | sed 's/^  //g' | grep -v 'HEAD' || echo "")
    local local_branches=$(git branch 2>/dev/null | sed 's/^\* //g' | sed 's/^  //g' || echo "")
    local remote_branches=$(git branch -r 2>/dev/null | grep -v 'HEAD' | sed 's/^  //g' || echo "")

    # Count branches
    local local_count=$(echo "$local_branches" | grep -c . || echo "0")
    local remote_count=$(echo "$remote_branches" | grep -c . || echo "0")

    # Detect main branch
    local main_branch=""
    if git show-ref --verify --quiet refs/heads/main; then
        main_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        main_branch="master"
    elif git show-ref --verify --quiet refs/heads/develop; then
        main_branch="develop"
    else
        main_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    fi

    # Convert branches to JSON arrays
    local local_branches_json=$(echo "$local_branches" | jq -R -s -c 'split("\n") | map(select(length > 0))')
    local remote_branches_json=$(echo "$remote_branches" | jq -R -s -c 'split("\n") | map(select(length > 0))')

    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq \
        --argjson local "$local_branches_json" \
        --argjson remote "$remote_branches_json" \
        --arg main "$main_branch" \
        --arg local_count "$local_count" \
        --arg remote_count "$remote_count" \
        '.branches = {
            "main_branch": $main,
            "local_branches": $local,
            "remote_branches": $remote,
            "statistics": {
                "local_count": ($local_count | tonumber),
                "remote_count": ($remote_count | tonumber)
            }
        }')
}

# ============================================
# Workflow Detection (Git Flow, GitHub Flow, etc.)
# ============================================
detect_workflow() {
    local workflow_type="unknown"
    local workflow_description=""
    local has_develop=false
    local has_release=false
    local has_hotfix=false
    local has_feature=false

    # Check for develop branch
    if git show-ref --verify --quiet refs/heads/develop || git show-ref --quiet refs/remotes/origin/develop; then
        has_develop=true
    fi

    # Check for release branches
    if git branch -a 2>/dev/null | grep -q 'release/'; then
        has_release=true
    fi

    # Check for hotfix branches
    if git branch -a 2>/dev/null | grep -q 'hotfix/'; then
        has_hotfix=true
    fi

    # Check for feature branches
    if git branch -a 2>/dev/null | grep -q 'feature/'; then
        has_feature=true
    fi

    # Determine workflow type
    if [ "$has_develop" = true ] && [ "$has_release" = true ] && [ "$has_hotfix" = true ]; then
        workflow_type="Git Flow"
        workflow_description="Full Git Flow detected with develop, release, and hotfix branches"
    elif [ "$has_develop" = true ] && [ "$has_feature" = true ]; then
        workflow_type="Git Flow (partial)"
        workflow_description="Git Flow-like structure with develop and feature branches"
    elif [ "$has_feature" = true ]; then
        workflow_type="Feature Branch Workflow"
        workflow_description="Feature branches detected, likely using feature branch workflow"
    elif git branch -a 2>/dev/null | grep -qE '(staging|production|prod)'; then
        workflow_type="Environment Branch Workflow"
        workflow_description="Environment-based branches detected (staging/production)"
    else
        workflow_type="Trunk-based / Simple"
        workflow_description="Simple branching model or trunk-based development"
    fi

    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq \
        --arg type "$workflow_type" \
        --arg desc "$workflow_description" \
        --argjson develop "$has_develop" \
        --argjson release "$has_release" \
        --argjson hotfix "$has_hotfix" \
        --argjson feature "$has_feature" \
        '.workflow = {
            "type": $type,
            "description": $desc,
            "git_flow_indicators": {
                "has_develop_branch": $develop,
                "has_release_branches": $release,
                "has_hotfix_branches": $hotfix,
                "has_feature_branches": $feature
            }
        }')
}

# ============================================
# Commit History Analysis
# ============================================
analyze_commits() {
    # Recent commits (last 10)
    local recent_commits=$(git log -10 --pretty=format:'{"hash":"%h","author":"%an","date":"%ai","message":"%s"}' 2>/dev/null | jq -s '.' || echo "[]")

    # Last commit date
    local last_commit_date=$(git log -1 --format=%ai 2>/dev/null || echo "unknown")

    # First commit date
    local first_commit_date=$(git log --reverse --format=%ai | head -1 2>/dev/null || echo "unknown")

    # Commits in last 30 days
    local commits_last_30d=$(git log --since="30 days ago" --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "0")

    # Commits in last 90 days
    local commits_last_90d=$(git log --since="90 days ago" --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "0")

    # Average commits per month (last 6 months)
    local commits_last_6m=$(git log --since="6 months ago" --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    local avg_commits_per_month=$(echo "scale=1; $commits_last_6m / 6" | bc 2>/dev/null || echo "0")

    # Check for signed commits (last 100)
    local signed_commits=$(git log -100 --show-signature 2>/dev/null | grep -c "Good signature" || echo "0")
    local total_checked=100
    local signed_percentage=$(echo "scale=1; ($signed_commits * 100) / $total_checked" | bc 2>/dev/null || echo "0")

    # Check commit message quality (last 50)
    local commit_messages=$(git log -50 --pretty=format:'%s' 2>/dev/null || echo "")
    local conventional_commits=$(echo "$commit_messages" | grep -cE '^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)(\(.+\))?: ' || echo "0")
    local quality_percentage=$(echo "scale=1; ($conventional_commits * 100) / 50" | bc 2>/dev/null || echo "0")

    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq \
        --argjson recent "$recent_commits" \
        --arg last_date "$last_commit_date" \
        --arg first_date "$first_commit_date" \
        --arg commits_30d "$commits_last_30d" \
        --arg commits_90d "$commits_last_90d" \
        --arg avg_per_month "$avg_commits_per_month" \
        --arg signed "$signed_commits" \
        --arg signed_pct "$signed_percentage" \
        --arg quality_pct "$quality_percentage" \
        '.commits = {
            "recent_commits": $recent,
            "statistics": {
                "last_commit_date": $last_date,
                "first_commit_date": $first_date,
                "commits_last_30_days": ($commits_30d | tonumber),
                "commits_last_90_days": ($commits_90d | tonumber),
                "average_commits_per_month": ($avg_per_month | tonumber),
                "signed_commits_percentage": ($signed_pct | tonumber),
                "conventional_commits_percentage": ($quality_pct | tonumber)
            }
        }')
}

# ============================================
# Contributors Analysis
# ============================================
analyze_contributors() {
    # Total unique contributors
    local total_contributors=$(git log --format='%ae' | sort -u | wc -l | tr -d ' ' || echo "0")

    # Top 10 contributors by commit count
    local top_contributors=$(git shortlog -sne --all | head -10 | awk '{$1=""; print $0}' | sed 's/^ //' | jq -R -s -c 'split("\n") | map(select(length > 0)) | map({contributor: .})' || echo "[]")

    # Active contributors (last 90 days)
    local active_contributors=$(git log --since="90 days ago" --format='%ae' | sort -u | wc -l | tr -d ' ' || echo "0")

    # Contributors in last 30 days
    local recent_contributors=$(git log --since="30 days ago" --format='%ae' | sort -u | wc -l | tr -d ' ' || echo "0")

    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq \
        --arg total "$total_contributors" \
        --argjson top "$top_contributors" \
        --arg active "$active_contributors" \
        --arg recent "$recent_contributors" \
        '.contributors = {
            "total_contributors": ($total | tonumber),
            "active_last_90_days": ($active | tonumber),
            "active_last_30_days": ($recent | tonumber),
            "top_contributors": $top
        }')
}

# ============================================
# Repository Health Indicators
# ============================================
analyze_repository_health() {
    # Check for important files
    local has_gitignore=$([ -f ".gitignore" ] && echo "true" || echo "false")
    local has_gitattributes=$([ -f ".gitattributes" ] && echo "true" || echo "false")
    local has_readme=$([ -f "README.md" ] || [ -f "README.txt" ] && echo "true" || echo "false")
    local has_contributing=$([ -f "CONTRIBUTING.md" ] && echo "true" || echo "false")
    local has_codeowners=$([ -f ".github/CODEOWNERS" ] || [ -f "CODEOWNERS" ] && echo "true" || echo "false")

    # Check for CI/CD configurations
    local has_github_actions=$([ -d ".github/workflows" ] && echo "true" || echo "false")
    local has_gitlab_ci=$([ -f ".gitlab-ci.yml" ] && echo "true" || echo "false")
    local has_jenkins=$([ -f "Jenkinsfile" ] && echo "true" || echo "false")

    # Count tags (releases)
    local tags_count=$(git tag | wc -l | tr -d ' ' || echo "0")
    local latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")

    # Check repository activity
    local days_since_last_commit=$(git log -1 --format=%ct 2>/dev/null | awk -v now=$(date +%s) '{print int((now - $1) / 86400)}' || echo "999")

    # Activity status
    local activity_status="unknown"
    if [ "$days_since_last_commit" -lt 7 ]; then
        activity_status="highly_active"
    elif [ "$days_since_last_commit" -lt 30 ]; then
        activity_status="active"
    elif [ "$days_since_last_commit" -lt 90 ]; then
        activity_status="moderately_active"
    elif [ "$days_since_last_commit" -lt 180 ]; then
        activity_status="low_activity"
    else
        activity_status="inactive"
    fi

    # Check for large files (> 10MB) in git history
    local large_files_count=$(git rev-list --objects --all 2>/dev/null | \
        git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' 2>/dev/null | \
        awk '$1 == "blob" && $3 > 10485760 {print}' | wc -l | tr -d ' ' || echo "0")

    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq \
        --argjson gitignore "$has_gitignore" \
        --argjson gitattributes "$has_gitattributes" \
        --argjson readme "$has_readme" \
        --argjson contributing "$has_contributing" \
        --argjson codeowners "$has_codeowners" \
        --argjson github_actions "$has_github_actions" \
        --argjson gitlab_ci "$has_gitlab_ci" \
        --argjson jenkins "$has_jenkins" \
        --arg tags "$tags_count" \
        --arg latest_tag "$latest_tag" \
        --arg days_since "$days_since_last_commit" \
        --arg activity "$activity_status" \
        --arg large_files "$large_files_count" \
        '.repository_health = {
            "essential_files": {
                "has_gitignore": $gitignore,
                "has_gitattributes": $gitattributes,
                "has_readme": $readme,
                "has_contributing": $contributing,
                "has_codeowners": $codeowners
            },
            "ci_cd": {
                "has_github_actions": $github_actions,
                "has_gitlab_ci": $gitlab_ci,
                "has_jenkins": $jenkins
            },
            "releases": {
                "tags_count": ($tags | tonumber),
                "latest_tag": $latest_tag
            },
            "activity": {
                "days_since_last_commit": ($days_since | tonumber),
                "status": $activity
            },
            "issues": {
                "large_files_count": ($large_files | tonumber)
            }
        }')
}

# ============================================
# Generate Recommendations
# ============================================
generate_recommendations() {
    local recommendations=()

    # Check for .gitignore
    if [ ! -f ".gitignore" ]; then
        recommendations+=('{"priority":"high","category":"essential_files","message":"Missing .gitignore file - add to prevent committing sensitive files"}')
    fi

    # Check for README
    if [ ! -f "README.md" ] && [ ! -f "README.txt" ]; then
        recommendations+=('{"priority":"high","category":"documentation","message":"Missing README file - add project documentation"}')
    fi

    # Check commit activity
    local days_since=$(git log -1 --format=%ct 2>/dev/null | awk -v now=$(date +%s) '{print int((now - $1) / 86400)}' 2>/dev/null || echo "999")
    if [ -n "$days_since" ] && [ "$days_since" -gt 90 ] 2>/dev/null; then
        recommendations+=('{"priority":"medium","category":"activity","message":"No commits in last 90 days - repository may be inactive"}')
    fi

    # Check for CI/CD
    if [ ! -d ".github/workflows" ] && [ ! -f ".gitlab-ci.yml" ] && [ ! -f "Jenkinsfile" ]; then
        recommendations+=('{"priority":"medium","category":"automation","message":"No CI/CD configuration detected - consider adding automated testing and deployment"}')
    fi

    # Check for conventional commits
    local commit_messages=$(git log -50 --pretty=format:'%s' 2>/dev/null || echo "")
    local conventional_commits=$(echo "$commit_messages" | grep -cE '^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)(\(.+\))?: ' 2>/dev/null || echo "0")
    conventional_commits=$(echo "$conventional_commits" | tr -d ' \n')
    if [ -n "$conventional_commits" ] && [ "$conventional_commits" -lt 10 ] 2>/dev/null; then
        recommendations+=('{"priority":"low","category":"commit_quality","message":"Consider using Conventional Commits format for better commit history"}')
    fi

    # Check for tags/releases
    local tags_count=$(git tag 2>/dev/null | wc -l | tr -d ' \n' || echo "0")
    if [ -n "$tags_count" ] && [ "$tags_count" -eq 0 ] 2>/dev/null; then
        recommendations+=('{"priority":"low","category":"releases","message":"No tags found - consider using semantic versioning and tagging releases"}')
    fi

    # Check for signed commits
    local signed_commits=$(git log -100 --show-signature 2>/dev/null | grep -c "Good signature" 2>/dev/null || echo "0")
    signed_commits=$(echo "$signed_commits" | tr -d ' \n')
    if [ -n "$signed_commits" ] && [ "$signed_commits" -eq 0 ] 2>/dev/null; then
        recommendations+=('{"priority":"low","category":"security","message":"No signed commits detected - consider enabling commit signing for better security"}')
    fi

    # Convert recommendations array to JSON
    if [ ${#recommendations[@]} -gt 0 ]; then
        local recs_json=$(printf '%s\n' "${recommendations[@]}" | jq -s '.')
        JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --argjson recs "$recs_json" '.recommendations = $recs')
    fi
}

# ============================================
# Main Execution
# ============================================
main() {
    get_repo_info
    get_branches
    detect_workflow
    analyze_commits
    analyze_contributors
    analyze_repository_health
    generate_recommendations

    # Output final JSON
    echo "$JSON_OUTPUT" | jq -c '.'
}

main

