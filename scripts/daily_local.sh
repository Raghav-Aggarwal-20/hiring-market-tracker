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
.venv/bin/python -m extract
gh workflow run daily.yml -f skip_extract=true
echo "deploy run triggered"
