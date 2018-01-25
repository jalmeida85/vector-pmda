# perfmaps.sh - shell library for generating Linux perf symbol map files
#
# This generates the /tmp/perf-PID.map files used by perf for symbol
# translation of JIT runtimes.
#
# PREREQUISITES
#
# For Java symbols:
# - Java processes running with -XX:+PreserveFramePointer
# - perf-map-agent installed in $PM_ORACLE_PMA_DIR (built for Oracle JDK)
#     and/or installed in $PM_OPENJDK_PMA_DIR (built for OpenJDK).
#     See the Environment settings below.
#
# For Node.js symbols:
# - Node processes running with --perf_basic_prof[_only_functions]
# - The perfmaptidy.pl program in the same directory as this script.
# 
# A new symobl dump technique may be added to node, at which point this
# script will need to be updated, and perfmaptidy.pl may no longer be needed.
#
# USAGE: . perfmaps.sh		# declares the following functions:
#
# dump_java_maps([PIDs]): dumps symbol files for all processes named
#     "java". For Oracle JDK Java processes, this will use the perf-map-agent
#     library from the $PM_ORACLE_PMA_DIR directory, if it exists. For
#     OpenJDK Java processes, it will attempt to use $PM_OPENJDK_PMA_DIR
#     instead (note that using the wrong perf-map-agent binaries can crash
#     Java). For Java in containers, this will attempt to install the
#     appropriate perf-map-agent version, if it doesn't already exist in the
#     container. An optional list of PIDs can be provided, to restrict scanning
#     to those specified (eg, listing PIDs in a container or containers. Note
#     that the "java" process name check is still performed.)
#
# fix_node_maps([PIDs]): find all "node" processes and ensure a symbol
#     map is available. This can mean fixing the map permissions, and also
#     copying maps from containers to the host. Stale entries are also
#     cleaned up from maps (perfmaptidy.pl). An optional list of PIDs can
#     be provided, to restrict scanning to those specified.
#
# This library was developed for Vector: http://vectoross.io/
#
# SEE ALSO: https://github.com/jvm-profiling-tools/perf-map-agent
#
# Copyright 2017 Netflix, Inc.
# Licensed under the Apache License, Version 2.0 (the "License")

#
# Environment
#

# PM is short for perfmaps.sh
PM_CONTAINER_AWARE=1	# set to zero to disable container code
# note: it's important to have separate builds for the following:
PM_ORACLE_PMA_DIR=/usr/lib/jvm/perf-map-agent	# todo: move to -oracle
PM_OPENJDK_PMA_DIR=/usr/lib/jvm/perf-map-agent-openjdk
PM_HOME=${0%/*}
PM_UNINLINED=0

#
# Generic Functions
#

# dummy map to include an error message in the flame graph
function _dummy_map {
	local mapfile=$1
	echo "000000000000 f00000000000 missing_perf_map" > $mapfile
}

# takes a pid, and returns its user as a -u argument that will work with sudo
function _pid_to_sudo_user {
	local pid=$1
	local user=$(ps ho user -p $pid)
	if [[ "$user" == [0-9]* ]]; then
		# prefix UID with '#' for use with sudo
		user="#$user"
	fi
	echo $user
}

# takes a pid, and returns its UID
function _pid_to_uid {
	local pid=$1
	local uid=$(ps ho uid -p $pid)
	echo $uid
}

# takes a pid, and returns its GID
function _pid_to_gid {
	local pid=$1
	local gid=$(ps ho gid -p $pid)
	echo $gid
}

# takes a pid, and returns its namespace PID
function _pid_to_nspid {
	local pid=$1
	local nspid=$(awk '/^NSpid:/ { print $3; exit }' /proc/$pid/status)
	[[ "$nspid" == "" ]] && nspid=$pid	# not in another namespace
	echo $nspid
}

#
# Java
#

# return JAVA_HOME for a given pid
function _pid_to_java_home {
	local pid=$1
	# fetch java home by parsing java's /proc/$pid/exe symlink destination.
	# could also use stat %N, but it adds quotes.
	set -- $(ls -l /proc/$pid/exe)
	echo ${11%%/jre/bin/java}
}

# given a pid, generate a /tmp/perf-PID.map symbol file using Java
# perf-map-agent. This should be called when the perf-map-agent output files
# are in the current directory.
function _host_java_map {
	local pid=$1
	local mapfile=/tmp/perf-$pid.map
	local no_pma=0
	[ -e $mapfile ] && rm $mapfile

	# check Java version
	local java_home=$(_pid_to_java_home $pid)
	if [[ "$java_home" = *openjdk* ]]; then
		local pma=$PM_OPENJDK_PMA_DIR
	else
		local pma=$PM_ORACLE_PMA_DIR
	fi

	# check that we can find perf-map-agent, and that the jar exists.
	# the perf-map-agent output may be in /out subdir, or not,
	# depending on the version used.
	if [ -d $pma/out ]; then
		cd $pma/out
	elif [ -d $pma ]; then
		cd $pma
	else
		no_pma=1
	fi
	[ ! -e attach-main.jar ] && no_pma=1
	[ ! -e libperfmap.so ] && no_pma=1

	# if no perf-map-agent, write a dummy map
	if (( no_pma )); then
		_dummy_map $mapfile
		echo >&2 "WARNING: perfmaplib no perf-map-agent for PID $pid ($java_home)"
		return
	fi

	local java_home=$(_pid_to_java_home $pid)
	local user=$(_pid_to_sudo_user $pid)
	local opts=""
	(( PM_UNINLINED )) && opts="unfoldall"
	# run as java user to avoid "well-known file is not secure" error
	sudo -u $user $java_home/bin/java -cp attach-main.jar:$java_home/lib/tools.jar net.virtualvoid.perf.AttachOnce $pid $opts > /dev/null
	[ -e $mapfile ] && chown root:root $mapfile
}

# generate a /tmp/perf-PID.map symbol file for the PID, which is assumed to be
# in a container. This should be called when the perf-map-agent output files
# are in the current directory. This uses nsenter to copy the perf-map-agent
# files to the container, and nsenter to copy the symbol file back to the host.
function _container_java_map {
	local pid=$1
	local nspid=$2	# optional,
	[[ "$nspid" == "" ]] && nspid=$(_pid_to_nspid $pid)
	local nsroot=/proc/$pid/root

	local mapfile=/tmp/perf-$pid.map
	local nsmapfile=/tmp/perf-$nspid.map
	[ -e $mapfile ] && rm $mapfile

	# check Java version
	local java_home=$(_pid_to_java_home $pid)
	if [[ "$java_home" = *openjdk* ]]; then
		local pma=$PM_OPENJDK_PMA_DIR
	else
		local pma=$PM_ORACLE_PMA_DIR
	fi

	# check that we can find perf-map-agent, and that the jar exists.
	# first check in the container, then the host.
	# the perf-map-agent output may be in /out subdir, or not,
	# depending on the version used.
	local need_copy=0
	local nspma=$pma	# where to find pma in the container
	if [ -d $nsroot/$pma/out ]; then
		cd $nsroot/$pma/out
		local nspma=$pma/out
	elif [ -d $nsroot/$pma ]; then
		cd $nsroot/$pma
	elif [ -d $pma/out ]; then
		cd $pma/out
		need_copy=1
	elif [ -d $pma ]; then
		cd $pma
		need_copy=1
	else
		no_pma=1
	fi
	# now that we've chdir'd:
	[ ! -e attach-main.jar ] && no_pma=1
	[ ! -e libperfmap.so ] && no_pma=1

	# if no perf-map-agent, write a dummy map
	if (( no_pma )); then
		_dummy_map $mapfile
		echo >&2 "WARNING: perfmaplib no perf-map-agent for PID $pid NSPID $nspid ($java_home)"
		return
	fi

	if (( need_copy )); then
		# copy perf-map-agent into /tmp on the container
		mkdir $nsroot/$pma
		cp -p attach-main.jar libperfmap.so $nsroot/$pma
		# if the /proc/PID/root/tmp approach stops working, use:
		# tar cf - attach-main.jar libperfmap.so | nsenter -t $pid -m -p sh -c 'cd '$pma'; tar xf -'
	fi

	# run as java user to avoid "well-known file is not secure" error.
	# execute perf-map-agent from within the container.
	local java_home=$(_pid_to_java_home $pid)
	local uid=$(_pid_to_uid $pid)
	local gid=$(_pid_to_uid $pid)
	local opts=""
	(( PM_UNINLINED )) && opts="unfoldall"
	nsenter -t $pid -m -p -u -S $uid -G $gid sh -c '
		cd '$pma'
		'$java_home'/bin/java -cp attach-main.jar:'$java_home'/lib/tools.jar net.virtualvoid.perf.AttachOnce '$nspid' '$opts' > /dev/null' > /dev/null

	# copy the map file back to the host
	cp ${nsroot}$nsmapfile $mapfile
	# if the /proc/PID/root/tmp approach stops working, use:
	# nsenter -t $pid -m -p sh -c 'cat '$nsmapfile > $mapfile

	[ -e $mapfile ] && chown root:root $mapfile
}

# dump_java_maps([container]): finds all processes named "java" and dumps their
# maps. If the processes are in containers, then copy the maps to the host. If a
# list of PIDs is provided, only dump "java" maps from those PIDs.
function dump_java_maps {
	local filter_pids	# effectively resets it between runs
	for p in $*; do filter_pids[$p]=1; done

	# do all processes named "java" (use jps instead?)
	local pid
	for pid in $(pgrep -x java); do
		# filter on pids, if provided
		if (( ${#filter_pids[@]} )); then
			(( ! filter_pids[pid] )) && continue
		fi

		if (( PM_CONTAINER_AWARE )); then
			# check the namespace pid to determine if a pid is in a
			# container
			local nspid=$(_pid_to_nspid $pid)
			if (( nspid == pid )); then
				_host_java_map $pid
			else
				_container_java_map $pid $nspid
			fi
		else
			# not container aware approach
			_host_java_map $pid
		fi
	done
}

# with uninlining of Java symbols
function dump_java_maps_uninlined {
	PM_UNINLINED=1
	dump_java_maps "$@"
}

#
# Node.js
#

# if node is logging symbols, tidy up the map file and leave it with the
# correct permissions for perf.
function _host_node_map {
	local pid=$1
	local mapfile=/tmp/perf-$pid.map
	local livemapfile=/tmp/perf-$pid.livemap

	local args=$(ps ho args $pid)
	if [[ "$args" == *perf-basic-prof* || "$args" == *perf_basic_prof* ]]; then
		# node is using the --perf_basic_prof[_only_functions] live
		# symbol log.

		# perf reads $mapfile, but we want to process it first, so
		# rename the live map so that we can create our own map. We'll
		# leave it renamed, and node will continue writing to the
		# renamed version.
		if [ ! -e $livemapfile ]; then
			mv $mapfile $livemapfile
		fi

		./perfmaptidy.pl < $livemapfile > $mapfile
		# new map file should be owned by root, as needed by perf
	else
		# node may one day support on-demand map dumps, in which case,
		# change this code to invoke it
		if [ ! -e $mapfile ]; then
			_dummy_map $mapfile
		fi
	fi
}

# if node is logging symbols, fetch the map file from the container, tidy it,
# and leave it with the correct permissions for perf.
function _container_node_map {
	local pid=$1
	local nspid=$2	# optional,
	[[ "$nspid" == "" ]] && nspid=$(_pid_to_nspid $pid)
	local mapfile=/tmp/perf-$pid.map
	local nsmapfile=/tmp/perf-$nspid.map
	local nsroot=/proc/$pid/root

	local args=$(ps ho args $pid)
	if [[ "$args" == *perf-basic-prof* || "$args" == *perf_basic_prof* ]]; then
		# node is using the --perf_basic_prof[_only_functions] live
		# symbol log.

		if [ -e ${nsroot}$nsmapfile ]; then
			./perfmaptidy.pl < ${nsroot}$nsmapfile > $mapfile
		# if the /proc/PID/root approach stops working, use:
		# if nsenter -t $pid -m [ -e $nsmapfile ]; then
		# 	nsenter -t $pid -m cat $nsmapfile | ./perfmaptidy.pl > $mapfile
		else
			_dummy_map $mapfile
		fi
	else
		# node may one day support on-demand map dumps, in which case,
		# change this code to invoke it
		if [ ! -e $mapfile ]; then
			_dummy_map $mapfile
		fi
	fi
}


# fix_node_maps([container]): find all "node" processes and fix the map
# permissions so that perf can read them as root. For node processes in
# containers, copy their maps to the host. If a list of PIDs is provided,
# only fix "node" maps from those PIDs.
function fix_node_maps {
	local filter_pids	# effectively resets it between runs
	for p in $*; do filter_pids[$p]=1; done

	cd $PM_HOME

	for pid in $(pgrep -x node); do
		# filter on pids, if provided
		if (( ${#filter_pids[@]} )); then
			(( ! filter_pids[pid] )) && continue
		fi

		if (( PM_CONTAINER_AWARE )); then
			# check the namespace pid to determine if a pid is in a
			# container
			local nspid=$(_pid_to_nspid $pid)
			if (( nspid == pid )); then
				_host_node_map $pid
			else
				_container_node_map $pid $nspid
			fi
		else
			# not container aware approach
			_host_node_map $pid
		fi
	done
}
