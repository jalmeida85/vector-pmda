#!/bin/bash
TS=`date +%Y%m%d-%T`

#DIR
WEBDIR=/usr/share/pcp/jsdemos/heatmap
WDIR=/var/log/pcp/vector/HEATMAP
BDIR=/var/lib/pcp/pmdas/vector/BINHeatMap
#FILE
SVG=$WEBDIR/heatmap.svg
PERF=$WDIR/perf.data.$TS
#
if [ ! -d "$WDIR" ]
then
/bin/mkdir -p $WDIR
fi

if [ ! -d "$WEBDIR" ]
then
/bin/mkdir -p $WEBDIR
fi
#
if [ -d "$WEBDIR" ]
then
/bin/rm $SVG
fi
#
#
/usr/bin/perf record -o $PERF -e block:block_rq_issue -e block:block_rq_complete -a sleep 120 &> /dev/null
timeout 20 /usr/bin/perf script -i $PERF| awk '{ gsub(/:/, "") } $5 ~ /issue/ { ts[$6, $10] = $4 } $5 ~ /complete/ { if (l = ts[$6, $9]) { printf "%.f %.f\n", $4 * 1000000, ($4 - l) * 1000000; ts[$6, $10] = 0 } }' > $WDIR/out.lat_us
#
$BDIR/trace2heatmap.pl --unitstime=us --unitslat=us --grid --maxlat=100000 $WDIR/out.lat_us >$SVG
#clean up
/bin/rm $PERF
/bin/rm $WDIR/out.lat_us
