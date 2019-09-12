#!/bin/bash
expr 1 + $(getent passwd | grep -E '2[0-9]{3}' | sort -t: -k 3 -n | tail -2 | head -1 | awk -F: '{print $3}')
