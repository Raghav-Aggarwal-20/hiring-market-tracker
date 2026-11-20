#!/bin/zsh
# Daily extract from this Mac, then a GitHub run that builds and deploys from BigQuery.
# Why here and not on GitHub: Workday's boards have refused GitHub runner IPs since 2026-11-16 (429).
# Scheduled by scripts/com.hiringmarkettracker.daily.plist at 11:00 and 14:00 local; launchd runs a missed time once the Mac wakes.
# Run it from a clone outside ~/Documents (e.g. ~/hmt-daily): macOS blocks launchd jobs from reading Documents.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
cd "${0:A:h}/.."
echo "=== $(date -u '+%Y-%m-%d %H:%M UTC')"
day=$(date -u +%F)
# 11:00 is the main run and 14:00 the backup; the backup does nothing if 11:00 already got all companies.
if [[ "$(cat logs/last_complete 2>/dev/null)" == "$day" ]]; then echo "already complete for $day"; exit 0; fi
git pull -q --ff-only
if .venv/bin/python -m extract | tee logs/last_extract.txt; then
  gh workflow run daily.yml -f skip_extract=true  # deploy what loaded, even if a board or two failed
  echo "deploy run triggered"
  grep -q '^failed:' logs/last_extract.txt || { echo "$day" > logs/last_complete; exit 0; }
fi
# Crashed (e.g. network dropped during the BigQuery load, 2026-11-20) or some boards failed.
if (( $(date +%H) >= 14 )); then
  osascript -e 'display notification "Daily extract incomplete after the 2pm backup; see ~/hmt-daily/logs/daily_local.log" with title "hiring-market-tracker"'
fi
exit 1
