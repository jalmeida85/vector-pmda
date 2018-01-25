#!/bin/bash

# environment
PATH=/bin:/usr/bin:$PATH
HOSTNAME=$(uname -n)
TS=`date +%Y%m%d-%T`
#DIR
WEBDIR=/usr/share/pcp/jsdemos/jstack
WDIR=/var/log/pcp/vector/JSTACK
BDIR=/var/lib/pcp/pmdas/vector/BINFlameGraph
THDIR=/apps/tomcat/logs/cores
#FILE
THSVG=$WEBDIR/threadump-history.svg
S3THSVG=threadump-history
DEMOSVG=$WEBDIR/threadump-Demo.svg
S3DEMOSVG=threadump-Demo
#
if [ ! -d "$WDIR" ];
then
/bin/mkdir -p $WDIR
fi
#
if [ ! -d "$WEBDIR" ];
then
/bin/mkdir -p $WEBDIR
fi

if [ -d "$WEBDIR" ];
then
/bin/rm $WEBDIR/*
fi

# find all java process and run jstack 10 times at interval of 2 seconds
j=0
for i in `ps -e|grep java|awk '{print $1}'`
 do
  while [ $j -le 10 ]
   do
   JAVA_USER=$(ps ho user -p $i)
   sudo -u $JAVA_USER /usr/bin/jstack $i >> $WDIR/jstack.out.$i
    sleep 2
    j=$(( $j + 1 ))
   done
j=0
$BDIR/stackcollapse-jstack.pl < $WDIR/jstack.out.$i > $WDIR/jstack.out.$i-folded  
$BDIR/flamegraph.pl < $WDIR/jstack.out.$i-folded > $WEBDIR/jstack-$i-PID.svg
/bin/rm $WDIR/jstack.out.$i
/bin/rm $WDIR/jstack.out.$i-folded
done

if  ls $THDIR/threaddump*.txt &> /dev/null; then 
/bin/cat $THDIR/threaddump*.txt > $WDIR/all-threaddump.txt
$BDIR/stackcollapse-jstack.pl < $WDIR/all-threaddump.txt >$WDIR/out.folded  
$BDIR/flamegraph.pl < $WDIR/out.folded > $THSVG 
else
# For Demo purpose only
/bin/cat /var/lib/pcp/pmdas/vector/JSTACK/threaddump*.txt > $WDIR/all-threaddump.txt
$BDIR/stackcollapse-jstack.pl < $WDIR/all-threaddump.txt >$WDIR/out.folded  
$BDIR/flamegraph.pl < $WDIR/out.folded > $DEMOSVG 
fi

/bin/rm $WDIR/out.folded
/bin/rm $WDIR/all-threaddump.txt

# Updated: Wed Apr 10 21:04:12 2013 by webmaster@askapache
# @ http://uploads.askapache.com/2013/04/gnu-mirror-index-creator.txt
# Copyright (C) 2013 Free Software Foundation, Inc.
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.

function create_gnu_index ()
{
    # call it right or die
    #[[ $# != 3 ]] && echo "bad args. do: $FUNCNAME '/DOCUMENT_ROOT/' '/' 'gnu.askapache.com'" && exit 2

    # D is the doc_root containing the site
    local L= D="/usr/share/pcp/jsdemos/jstack/" SUBDIR="jstack" DOMAIN="http://$HOSTNAME/" F=

    # The index.html file to create
    F="${D}index.html"

    # if dir doesnt exist, create it
    [[ -d $D ]] || mkdir -p $D;

    # cd into dir or die
    cd $D || exit 2;

    # touch index.html and check if writable or die
    touch $F && test -w $F || exit 2;

    # remove empty directories, they dont need to be there and slow things down if they are
    find . -maxdepth 1 -type d -empty -exec rm -rf {} \;

    # start of total output for saving as index.html
    (

        # print the html header
        echo '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">';
        echo "<html><head><title>jstack samples:  http://${DOMAIN}${SUBDIR}</title></head>";
        echo "<body><h1>${SUBDIR} Samples and Threaddump </h1><pre>      Name                                        Last modified      Size";

        # start of content output
        (
            # change IFS locally within subshell so the for loop saves line correctly to L var
            IFS=$'\n';

            # pretty sweet, will mimick the normal apache output
            for L in $(find -L . -mount -depth -maxdepth 1 -type f ! -name 'index.html' -printf "      <a href=${DOMAIN}${SUBDIR}/"%f">%-44f@_@%Td-%Tb-%TY %Tk:%TM  @%f@\n"|sort|sed 's,\([\ ]\+\)@_@,</a>\1,g');
            do
                # file
                F=$(sed -e 's,^.*@\([^@]\+\)@.*$,\1,g'<<<"$L");

                # file with file size
                F=$(du -bh $F | cut -f1);

                # output with correct format
                sed -e 's,\ @.*$, '"$F"',g'<<<"$L";
            done;
        )

        # now output a list of all directories in this dir (maxdepth 1) other than '.' outputting in a sorted manner exactly like apache
        find -L . -mount -depth -maxdepth 1 -type d ! -name '.' -printf "      <a href=\"%f\">%-43f@_@%Td-%Tb-%TY %Tk:%TM  -\n"|sort -d|sed 's,\([\ ]\+\)@_@,/</a>\1,g'

        # print the footer html
        echo "</pre><address>PCP pmwebd at ${DOMAIN}</address></body></html>";

    # finally save the output of the subshell to index.html
    )  > $F;

}

# start the run ( use function so everything is local and contained )
#    $1 is absolute document_root with trailing '/'
#    $2 is subdir like '/subdir/' if thats the web root, '/' if no subdir
#    $3 is the domain 'subdomain.domain.tld'
#create_gnu_index "${HOME}/sites/gnu.askapache.com/htdocs/" "/" "gnu.askapache.com"
create_gnu_index

# takes about 1-5 seconds to complete
exit
