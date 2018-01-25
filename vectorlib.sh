# vectorlib.sh - shell library for Vector pmda
#
# This library was developed for Vector: http://vectoross.io/
#
# PREREQUISITES
#
# $OUT_STATUS: a path for the file containing status messages
#
# Copyright 2017 Netflix, Inc.
# Licensed under the Apache License, Version 2.0 (the "License")

# environment
DEBUG_MSG=1	# set to zero to disable debug messages (pmda log via STDERR)
STATUS_MSG=1	# set to zero to disable status messages (pmda request status)

#
# Functions
#

# Print a debug message on STDERR with a PID and timestamp
function debugtime {
	(( DEBUG_MSG )) || return
	local ts=$(date +%H:%M:%S.%3N)
	# switch to printf's %()T operator when compatibility is acceptable:
	echo >&2 "DEBUG $$ $ts: $*"
}

function statusmsg {
	# debug messages are written to STDERR with a PID and timestamp:
	(( DEBUG_MSG )) && debugtime "$@"
	# status messages are set in a file, for reading by the pmda:
	if [[ "$OUT_STATUS" == "" ]]; then
		echo >&2 "ERROR status file not set in \$OUT_STATUS. Can't write status."
	else
		(( STATUS_MSG )) && echo "$*" > $OUT_STATUS
	fi
}

function rusage {
	read procstat < /proc/$$/stat
	set -- ${procstat#*)}	# strip comm, as it can be multi-field
	echo "minflt ${8} cminflt ${9} majflt ${10} cmajflt ${11} utime ${12} stime ${13} cutime ${14} cstime ${15}"
}

function errorexit {
	if (( $# )); then
		statusmsg "ERROR $@"
	else
		statusmsg "ERROR"
	fi
	exit 1
}
