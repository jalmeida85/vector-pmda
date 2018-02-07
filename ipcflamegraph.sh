#!/bin/bash
#
# ipcflamegraph - a Vector pcp pmda for generating a CPU flame graph
#
# USAGE: ipcflamegraph [seconds]
#
# The $PCP_CONTAINER_NAME environment variable will be read, and if it is
# not NULL, a CPU flame graph will be generated for the container name it
# identifies only.
#
# Check and adjust the environment settings below.
#
# REQUIREMENTS: The libraries perfmaplib.sh and vectorlib.sh. See those
# files for their own requirements.
#
# DEBUG: STDERR includes timestamped debug messages, and command errors. It
# is redirected to the pmda vector log (/var/log/pcp/pmcd/vector.log).
#
# SEE ALSO: http://vectoross.io http://pcp.io
#
# Copyright 2017 Netflix, Inc.
# Licensed under the Apache License, Version 2.0 (the "License")

# host
export TZ=US/Pacific
TS=$(date +%Y-%m-%d_%T)
PATH=/bin:/usr/bin:$PATH
HOSTNAME=$(uname -n)

# pcp pmda paths
METRIC=ipcflamegraph
PMDA_DIR=${0%/*}
WEBSITE_DIR=/usr/share/pcp/webapps/$METRIC
WORKING_DIR=/var/log/pcp/vector/$METRIC
FG_DIR=/var/lib/pcp/pmdas/vector/BINFlameGraph
OUT_SVG=$WEBSITE_DIR/${METRIC}.${PCP_CONTEXT}.svg
OUT_STATUS=$WORKING_DIR/${METRIC}.${PCP_CONTEXT}.status
OUT_FOLDED=$WORKING_DIR/perf.folded.$$
PERF_DATA=$WORKING_DIR/perf.data.$$	# adding $$ avoids a clash of concurrent runs
CGROUPFS=/sys/fs/cgroup

# libraries
. $PMDA_DIR/vectorlib.sh
. $PMDA_DIR/perfmaplib.sh

# s3
# S3BUCKET="s3://"

# perf settings
SECS=${1:-30}		# default to 30 seconds if not sepcified

#
# Ensure output directories exist
#
[ ! -d "$WORKING_DIR" ] && mkdir -p $WORKING_DIR
[ ! -d "$WEBSITE_DIR" ] && mkdir -p $WEBSITE_DIR
[ -d "$WEBSITE_DIR" -a -e "$OUT_SVG" ] && rm $OUT_SVG
[ -d "$FG_DIR" ] || errorexit "Flame graph software missing"

# terminator for new log group:
echo >&2

#
# Check for PMC and PEBS access
#
eventdir=/sys/devices/cpu/events
if [ ! -e $eventdir/cpu-cycles -o ! -e $eventdir/instructions ]; then
	errorexit "PMCs not available on this instance (see help)"
fi
PEBS=1
grep pebs /proc/cpuinfo > /dev/null || PEBS=0

debugtime "$0 start, container=$PCP_CONTAINER_NAME"
statusmsg "Profiling for $SECS seconds"

#
# Container filter
#
if [[ "$PCP_CONTAINER_NAME" != "" ]]; then
	#
	# Set $cgroupfilter for perf record, and $tasklist of container PIDs.
	#
	# The code below assumes that $PCP_CONTAINER_NAME is a Docker container
	# name, and so uses the docker command and cgroup v1 paths in
	# /sys/fs/cgroup. This code will need modifications for different
	# container software, and for cgroup v2.
	#
	UUID=$(docker inspect --format='{{ .Id }}' $PCP_CONTAINER_NAME)
	[[ "$UUID" == "" ]] && errorexit "Container not found"
	pid=$(docker inspect --format='{{ .State.Pid }}' $UUID)
	cgroup=$(awk -F: '$2 == "perf_event" { print $3; exit }' /proc/$pid/cgroup)
	[ ! -e $CGROUPFS/perf_event/$cgroup ] && errorexit "Container cgroup not found"
	cgroupfilter="--cgroup=$cgroup"
	tasklist=$(cat $CGROUPFS/perf_event/$cgroup/tasks)
	fgtitle="IPC Flame Graph (no idle): $PCP_CONTAINER_NAME, $TS"
else
	cgroupfilter=""
	tasklist=""
	fgtitle="IPC Flame Graph (no idle): $HOSTNAME, $TS"
fi

#
# Profile
#
if (( PEBS )); then
	# one-level for now:
	cpuevent=cpu-cycles:p
	insevent=instructions:p
else
	cpuevent=cpu-cycles
	insevent=instructions
fi
events="-e $cpuevent -e $insevent"
statusmsg "Using perf events: $events"
count=100000000
perf record -o $PERF_DATA $events -c $count -a $cgroupfilter -g sleep $SECS >/dev/null &
bgpid=$!
s=0
# update status message
while (( s < SECS )); do
	# give perf a chance to error before doing a kill -0 check:
	sleep 1
	kill -0 $bgpid > /dev/null 2>&1 || break
	sleep 4
	(( s += 5 ))
	statusmsg "Profiling for $SECS seconds ($s/$SECS)" 2>/dev/null
done
wait -n
status=$?
(( status == 0 )) || errorexit "PMC instrumentation failed. Are PMCs available? (See help.)"

# lower our priority before flame graph generation, to reduce CPU contention:
renice -n 19 -p $$ &>/dev/null

# prepare symbol maps
statusmsg "Collecting symbol maps"
dump_java_maps $tasklist
fix_node_maps $tasklist

# decide upon a palette
if pgrep -x node >/dev/null; then
	color=js
else
	color=java
fi

# generate flame graph and stash it away with the folded profile on s3
statusmsg "Processing profile"
timeout 20 perf script -i $PERF_DATA | $FG_DIR/stackcollapse-perf.pl --all --event-filter=$cpuevent | egrep -v 'cpu_idle|cpuidle_enter' > $OUT_FOLDED.cpu-cycles
timeout 20 perf script -i $PERF_DATA | $FG_DIR/stackcollapse-perf.pl --all --event-filter=$insevent | egrep -v 'cpu_idle|cpuidle_enter' > $OUT_FOLDED.instructions
timeout 20 $FG_DIR/difffolded.pl -ns $OUT_FOLDED.instructions $OUT_FOLDED.cpu-cycles > $OUT_FOLDED.diff
ipc=$(timeout 20 perf report --stdio | awk '
	/^# Samples: / { if (/instructions/) { i = 1; } else { i = 0; } }
	/^# Event count/ { if (i) { ins = $NF; } else { cyc = $NF; } }
	END { if (cyc) { printf("%.2f\n", ins / cyc); } else { print "?" } }')
statusmsg "Flame Graph generation"
$FG_DIR/flamegraph.pl --minwidth=0.5 --color=$color --hash --title="$fgtitle" --subtitle="IPC: $ipc; PEBS: $PEBS; red == instruction heavy, blue == stall heavy" --negate < $OUT_FOLDED.diff > $OUT_SVG
rm $OUT_FOLDED.cpu-cycles $OUT_FOLDED.instructions

# send to s3
# statusmsg "s3 archive"
# s3cp $OUT_SVG $S3BUCKET/${METRIC}-$TS.svg >/dev/null &
# s3cp $OUT_FOLDED $S3BUCKET/${METRIC}-$TS.folded >/dev/null &

statusmsg "Usage: $(rusage)"
statusmsg "DONE"

# $PERF_DATA file left behind for debug or custom reports
# XXX add code that cleans up all output files except the most recent 10
