#!/bin/bash
### Brian Hart
### Given a project name, determine how large an archive of it would be

if [ -z $1 ]; then 
	echo "Please pass a project name as the first argument."
	exit 1
fi

PROJECT=$1

if [ ! -d /jaunt/prod/projects/${PROJECT} ]; then
	echo "Cannot find project $PROJECT"
	exit 1
fi

val1=$(du -cmLs /jaunt/prod/projects/${PROJECT}/library/medusa/recordings/ | grep 'total' | awk '{print $1}')
val2=$(du -cms /jaunt/prod/projects/${PROJECT}/ | grep 'total' | awk '{print $1}')

recordings=$(echo "scale=2;$val1 / 1024" | bc -l)
restofproject=$(echo "scale=2;$val2 / 1024" | bc -l)
total=$(echo "scale=2;$recordings + $restofproject" | bc -l)

echo "Recordings are ${recordings} GB"
echo "The rest is ${restofproject} GB"

echo "Total size to archive is $total GB"

exit 0
