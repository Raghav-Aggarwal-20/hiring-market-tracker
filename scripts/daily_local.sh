#!/bin/zsh
# Daily extract from this Mac, then a GitHub run that builds and deploys from BigQuery.
# Why here and not on GitHub: Workday's boards have refused GitHub runner IPs since 2026-11-16 (429).
# Scheduled by scripts/com.hiringmarkettracker.daily.plist; launchd runs a missed time once the Mac wakes.
# Run it from a clone outside ~/Documents (e.g. ~/hmt-daily): macOS blocks launchd jobs from reading Documents.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
cd "${0:A:h}/.."
echo "=== $(date -u '+%Y-%m-%d %H:%M UTC')"
git pull -q --ff-only
# The Mac's network can drop for a minute around wake (2026-11-20: the BigQuery load lost its connection), so retry once.
.venv/bin/python -m extract || { echo "extract failed, retrying in 5 min"; sleep 300; .venv/bin/python -m extract; } || {
  osascript -e 'display notification "Daily extract failed twice; see ~/hmt-daily/logs/daily_local.log" with title "hiring-market-tracker"'
  exit 1
}
gh workflow run daily.yml -f skip_extract=true
echo "deploy run triggered"
