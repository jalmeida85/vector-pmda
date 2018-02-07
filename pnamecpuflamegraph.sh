#!/bin/bash
#
# pnamecpuflamegraph - a Vector pcp pmda for generating a package name flame graph
#		       as a background task
#
# USAGE: pnamecpuflamegraph [seconds]
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
METRIC=pnamecpuflamegraph
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
SECS=${1:-60}		# default to 60 seconds if not sepcified
HERTZ=49

#
# Ensure output directories exist
#
[ ! -d "$WORKING_DIR" ] && mkdir -p $WORKING_DIR
[ ! -d "$WEBSITE_DIR" ] && mkdir -p $WEBSITE_DIR
[ -d "$WEBSITE_DIR" -a -e "$OUT_SVG" ] && rm $OUT_SVG
[ -d "$FG_DIR" ] || errorexit "Flame graph software missing"

# terminator for new log group:
echo >&2

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
	cgroupfilter="-e cpu-clock --cgroup=$cgroup"
	tasklist=$(cat $CGROUPFS/perf_event/$cgroup/tasks)
	fgtitle="Package CPU Flame Graph (Java only): $PCP_CONTAINER_NAME, $TS"
else
	cgroupfilter=""
	tasklist=""
	fgtitle="Package CPU Flame Graph (Java only): $HOSTNAME, $TS"
fi

#
# Profile
#
perf record -o $PERF_DATA -F $HERTZ -a $cgroupfilter sleep $SECS >/dev/null &
s=0
# update status message
while (( s < SECS )); do
	sleep 5
	(( s += 5 ))
	statusmsg "Profiling for $SECS seconds ($s/$SECS)" 2>/dev/null
done
wait

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
# currently only Java is supported (hence the grep):
timeout 20 perf script -i $PERF_DATA | $FG_DIR/pkgsplit-perf.pl | grep java > $OUT_FOLDED
statusmsg "Flame Graph generation"
$FG_DIR/flamegraph.pl --minwidth=0.5 --color=$color --hash --title="$fgtitle" < $OUT_FOLDED > $OUT_SVG

# send to s3
# statusmsg "s3 archive"
# s3cp $OUT_SVG $S3BUCKET/${METRIC}-$TS.svg >/dev/null &
# s3cp $OUT_FOLDED $S3BUCKET/${METRIC}-$TS.folded >/dev/null &

statusmsg "Usage: $(rusage)"
statusmsg "DONE"

# $PERF_DATA file left behind for debug or custom reports
# XXX add code that cleans up all output files except the most recent 10
