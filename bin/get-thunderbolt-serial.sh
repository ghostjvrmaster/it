#!/bin/bash

if  [ $(uname) == 'Darwin' ]; then
   system_profiler SPDisplaysDataType | grep -e "^\ {8}[A-Z]" -e "Display Serial Number" | sed 's/^[ \t]*//' | sed -e :a -e '$!N;s/\nDisplay Serial Number: / /;ta' -e 'P;D'
else
   echo "This is for OSX only."
fi

