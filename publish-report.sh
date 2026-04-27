#!/bin/bash
# Publish Playwright test reports to GitHub Pages
#
# ONLY publishes fully successful runs on the live branch.
# Failed runs or non-live branches are silently skipped.
#
# Usage: ./publish-report.sh <site-name> <report-dir> <project-dir> [commit-ref]
#
# Arguments:
#   site-name    — identifier for this project (e.g. "lcd", "client-store")
#   report-dir   — path to test-results dir containing hyva-*-reports/
#   project-dir  — path to project git repo (for branch check + commit ref)
#   commit-ref   — optional, auto-detected from project-dir if omitted
#
# Example:
#   ./publish-report.sh lcd \
#       /var/www/html/tests/m2-hyva-playwright/test-results/lcd \
#       /var/www/html
#
# Environment variables:
#   TEST_REPORTS_REPO — override path to test-reports clone (default: script dir)

set -euo pipefail

SITE="${1:?Usage: publish-report.sh <site-name> <report-dir> <project-dir> [commit-ref]}"
REPORT_DIR="${2:?Usage: publish-report.sh <site-name> <report-dir> <project-dir> [commit-ref]}"
PROJECT_DIR="${3:?Usage: publish-report.sh <site-name> <report-dir> <project-dir> [commit-ref]}"
COMMIT_REF="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${TEST_REPORTS_REPO:-$SCRIPT_DIR}"
DATE=$(date +%Y-%m-%d_%H%M)

if [ ! -d "$REPORT_DIR" ]; then
    echo "ERROR: Report directory not found: $REPORT_DIR"
    exit 1
fi

# --- Gate 1: Must be on live branch ---
CURRENT_BRANCH=$(cd "$PROJECT_DIR" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [ "$CURRENT_BRANCH" != "live" ]; then
    echo "SKIP: Not on live branch (current: $CURRENT_BRANCH). Reports only published for live."
    exit 0
fi

# --- Gate 2: All tests must pass ---
HAS_FAILURES=0
REPORT_COUNT=0
for json_report in "$REPORT_DIR"/hyva-*-reports/json-reports/json-report.json; do
    [ -f "$json_report" ] || continue
    REPORT_COUNT=$((REPORT_COUNT + 1))
    failed=$(jq '[.suites[]?.specs[]?.tests[]? | select(.status == "unexpected" or .status == "failed")] | length' "$json_report" 2>/dev/null || echo 0)
    if [ "$failed" -gt 0 ]; then
        HAS_FAILURES=1
        suite_name=$(basename "$(dirname "$(dirname "$json_report")")" | sed 's/^hyva-//;s/-reports$//')
        echo "FAIL: ${suite_name} has ${failed} failed test(s)"
    fi
done

if [ "$REPORT_COUNT" -eq 0 ]; then
    echo "SKIP: No JSON reports found in $REPORT_DIR"
    exit 0
fi

if [ "$HAS_FAILURES" -eq 1 ]; then
    echo "SKIP: Test failures detected. Only fully successful runs are published."
    exit 0
fi

# Auto-detect commit ref from project if not provided
if [ -z "$COMMIT_REF" ]; then
    COMMIT_REF=$(cd "$PROJECT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "")
fi

cd "$REPO_DIR"

# Pull latest to avoid conflicts
git pull --rebase origin main 2>/dev/null || true

# Collect report suites and stats
SUITES=()
TOTAL_PASSED=0

for suite_dir in "$REPORT_DIR"/hyva-*-reports/playwright-report; do
    [ -d "$suite_dir" ] || continue

    # Extract suite name: hyva-admin-reports -> admin
    suite_name=$(basename "$(dirname "$suite_dir")" | sed 's/^hyva-//;s/-reports$//')
    SUITES+=("$suite_name")

    # Create target directory
    target="${SITE}/${DATE}/${suite_name}"
    mkdir -p "$target"

    # Copy HTML report
    cp -r "$suite_dir"/* "$target/"

    # Extract pass count from JSON report
    json_report="$(dirname "$suite_dir")/json-reports/json-report.json"
    if [ -f "$json_report" ] && command -v jq &>/dev/null; then
        passed=$(jq '[.suites[]?.specs[]?.tests[]? | select(.status == "expected" or .status == "passed")] | length' "$json_report" 2>/dev/null || echo 0)
        TOTAL_PASSED=$((TOTAL_PASSED + passed))
    fi
done

if [ ${#SUITES[@]} -eq 0 ]; then
    echo "SKIP: No playwright-report directories found in $REPORT_DIR"
    exit 0
fi

# Create combined index page for this run
cat > "${SITE}/${DATE}/index.html" << INDEXEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Test Run — ${SITE} ${DATE}</title>
    <style>
        body { font-family: -apple-system, sans-serif; background: #0d1117; color: #c9d1d9; padding: 2rem; max-width: 900px; margin: 0 auto; }
        a { color: #58a6ff; text-decoration: none; }
        h1 { margin-bottom: 0.5rem; }
        .meta { color: #8b949e; margin-bottom: 2rem; }
        .suite { margin: 1rem 0; padding: 1rem; background: #161b22; border: 1px solid #30363d; border-radius: 6px; }
        .suite a { font-size: 1.1rem; }
        .pass { color: #3fb950; }
    </style>
</head>
<body>
    <h1>Test Run — ${SITE}</h1>
    <p class="meta">${DATE} | commit: ${COMMIT_REF} | <span class="pass">${TOTAL_PASSED} tests passed</span></p>
    <p><a href="../../">← All reports</a></p>
INDEXEOF

for suite in "${SUITES[@]}"; do
    echo "    <div class=\"suite\"><a href=\"${suite}/index.html\">▶ ${suite} suite</a></div>" >> "${SITE}/${DATE}/index.html"
done

echo "</body></html>" >> "${SITE}/${DATE}/index.html"

# Update reports.json
SUITES_JSON=$(printf '%s\n' "${SUITES[@]}" | jq -R . | jq -s .)
NEW_ENTRY=$(jq -n \
    --arg date "$DATE" \
    --arg path "${SITE}/${DATE}/" \
    --arg commit "$COMMIT_REF" \
    --argjson passed "$TOTAL_PASSED" \
    --argjson failed "0" \
    --argjson suites "$SUITES_JSON" \
    '{date: $date, path: $path, commit: $commit, passed: $passed, failed: $failed, suites: $suites}')

if [ ! -f reports.json ] || [ ! -s reports.json ]; then
    echo '{}' > reports.json
fi

jq --arg site "$SITE" --argjson entry "$NEW_ENTRY" \
    'if .[$site] then .[$site] += [$entry] else .[$site] = [$entry] end' \
    reports.json > reports.json.tmp && mv reports.json.tmp reports.json

# Keep last 20 runs per site
jq 'to_entries | map(.value = (.value | sort_by(.date) | reverse | .[:20])) | from_entries' \
    reports.json > reports.json.tmp && mv reports.json.tmp reports.json

# Commit and push
git add -A
git commit -m "report: ${SITE} ${DATE} — ${TOTAL_PASSED} passed (${COMMIT_REF})" || true
git push origin main

echo ""
echo "Published: $(git remote get-url origin | sed 's|git@github.com:|https://|;s|\.git$||' | sed 's|https://github.com/\([^/]*\)/|https://\L\1\E.github.io/|')/${SITE}/${DATE}/"
