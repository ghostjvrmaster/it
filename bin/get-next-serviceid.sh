#!/bin/bash

expr 1 + $(getent passwd | grep -E '1[0-9]{5}' | sort -t: -k 3 -n | tail -1 | awk -F: '{print $3}')

