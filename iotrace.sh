#!/bin/sh
# Kozell, 2013
if [ "x$1" == "x-h" ]; then
	echo "Usage: ./iotrace.sh [<pid>]"
	exit 0;
fi

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root (or this script extended to recognize if we are the same user that runs the specified <pid>...)" 1>&2
   exit 1
fi

if [ $# -gt 0 ]; then
	PID=$1
else
	echo "Oops no"
	exit 2
fi

ps -eL | grep $PID | awk '{print"-p " $2}' | xargs strace -q -f -v -ttt -T -s 0 -e trace=open,close,read,readv,pread64,write,writev,pwrite64 2>&1 | awk -v pid=$PID '
function output(a, f, r, t)
{
	# a - action
	# f - file descriptor
	# r - result
	# t - time as unix epoch
	if (f in fd)
		file = fd[f];
	else
	{
		("readlink /proc/" pid "/fd/" f) | getline file;
		fd[f] = file;
	}
	if (file !~ /^(socket|pipe|\/dev|\/proc)/ || r ~ /\d+/)
		print a, file, r, strftime("%Y-%m-%d %H:%M:%S"); #substr(t, 0, index(t, ".")-1));
}

BEGIN { OFS=";"; print "op;path;bytes;epoch";}
{
	if($6 ~ /resumed>/)
	{
		if ($5 ~ /open/){fd[$(NF-1)] = pending[$2];}
		else if ($5 ~ /close/){match($4, /([0-9]+)/, a);delete fd[a[1]];}
		else if ($5 ~ /write/){match($4, /([0-9]+)/, a);output("write", pending[$2], $(NF-1), $3);}
		else if ($5 ~ /read/) {match($4, /([0-9]+)/, a);output("read", pending[$2], $(NF-1), $3);}
		
		delete pending[$2];
	}
	else if ($4 ~ /open/)
	{
		match($4, /\"(.+)\"/, a);
		f = a[1];
		if ($(NF-1) == "<unfinished")
		{
			pending[$2] = f;
		} else {
			fd[$(NF-1)] = f;
		}
	}
	else if ($4 ~ /close/)
	{
		match($4, /([0-9]+)/, a);
		f = a[1];
		if ($(NF-1) == "<unfinished")
		{
			pending[$2] = f;
		} else {
			delete fd[f];
		}
	}
	else if ($4 ~ /write/)
	{
		match($4, /([0-9]+)/, a);
		f = a[1];
		if ($(NF-1) == "<unfinished")
		{
			pending[$2] = f;
		} else {
			output("write", f, $(NF-1), $3);
		}
	}
	else if ($4 ~ /read/)
	{
		match($4, /([0-9]+)/, a);
		f = a[1];
		if ($(NF-1) == "<unfinished")
		{
			pending[$2] = f;
		} else {
			output("read", f, $(NF-1), $3);
		}
	}
}'
