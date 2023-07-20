#!/bin/sh
# Measure time to crawl dirs --- nimf
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

f -tdi -d1 "$@" -e '
start=$(date +%s.%N)
output=$(f {} | wc -lc)
end=$(date +%s.%N)

# Extract seconds and nanoseconds
start_s=${start%.*}
end_s=${end%.*}
start_ns=$(printf "%.0f" ${start#*.})
end_ns=$(printf "%.0f" ${end#*.})

# Calculate duration in seconds, milliseconds, and nanoseconds
duration_s=$((end_s - start_s))
duration_ms=$(( (end_ns - start_ns) / 1000000 ))
duration_ns=$(( (end_ns - start_ns) % 1000000 ))

printf "%ds %03dms %06dns %s "{}"\n" $duration_s $duration_ms $duration_ns "$output"' | sort -n
