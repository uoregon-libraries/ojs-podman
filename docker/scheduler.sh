#!/bin/bash

# Runs OJS's scheduled tasks at the start of every minute, like the cron job
# OJS's docs suggest. OJS's own "scheduler.php work" does the same, but it
# quits if OJS isn't installed yet, and as PID 1, it ignores SIGTERM.

# Bash ignores SIGTERM as PID 1, too, unless it's trapped
trap 'exit 0' TERM

while true; do
  # Sleeping in the background lets the trap run right away
  sleep $((60 - $(date +%-S))) &
  wait $!

  # Each run starts on time even if the last one hasn't finished, as with
  # cron, so a slow run can't make OJS skip a task that's due
  php lib/pkp/tools/scheduler.php run &
done
