#!/usr/bin/env python

import os.path
import subprocess
import sys

"""
    This script reads Open Directory LDAP automount maps and outputs 
    automount map files that can be used for non-LDAP autofs or automount
    configuration on Mac or Linux.

    Typical use:

    % automount_map_localize.py mac auto_tree
    % automount_map_localize.py linux auto.tree

    To use the resulting file on OS X:

    1. Copy the file into /etc
    2. Add the following line to the end of the /etc/auto_master file:

    /-              <your_file_name_here>

    e.g.

    /-              auto_tree

    3. After making the changes, run "sudo automount -vc" to activate them.

    To use the resulting file on Linux:

    1. Copy the file into /etc
    2. Add the following line to the end of the /etc/auto.master file:

    /-			<your_file_name_here>		--timeout=600

    e.g.

    /-			auto.tree			--timeout=600

    3. After making the changes, run "sudo service autofs restart" to activate.
"""

def fetchMapData():
    cmd = 'ldapsearch -x -o ldif-wrap=no -h ldap.corp.jauntvr.com -b cn=mounts,dc=corp,dc=jauntvr,dc=com'
    split_cmd = cmd.split()
    p = subprocess.Popen(split_cmd, stdout=subprocess.PIPE)
    lines = p.stdout.readlines()
    lines = [line.strip() for line in lines]
    return lines


def generateMountMapFromMapData(map_data):
    """ Create a dictionary of dictionaries where each key is a cn and each 
        sub-dictionary is a mount entry """
    string_key_names = ["mountDirectory", "cn"]
    list_key_names = ["mountOptions"]

    mount_map = {}
    in_record = False
    for line_num in xrange(len(map_data)):
        line = map_data[line_num]
        if not in_record:
            if not ",cn=mounts,dc=corp,dc=jauntvr,dc=com" in line:
                continue
            else:
                in_record = True
                mount = {}
                continue
        if not line: # Reached the end of a record
            in_record = False
            mount_map[mount['cn']] = mount
            continue
        split_line = line.split(': ')
        split_line = [item.strip() for item in split_line]
        if len(split_line) >= 2:
            (key, value) = split_line[0:2]
        else:
            continue
        if key in string_key_names:
            mount[key] = value
        if (key + 's') in list_key_names:
            if not (key + 's') in mount:
                mount[key + 's'] = [value]
            else:
                mount[key + 's'].append(value)
    return mount_map

def outputMap(mount_map, platform):
    if platform == "linux":
        exclude_mount_opts = ['browse', 'bg', 'soft', 'locallocks', 'nolocks']
        extra_mount_opts = ['rw', 'intr']
    elif platform == "mac":
        exclude_mount_opts = []
        extra_mount_opts = []
    else:
        raise ValueError("No such platform: " + platform)
    mount_keys = mount_map.keys()
    mount_keys.sort()
    for mount_key in mount_keys:
        line = ""
        line += mount_map[mount_key]['mountDirectory']
        num_tabs = (40 - len(line)) / 8
        tabs = '\t' * num_tabs
        if not tabs:
            tabs = ' '
        line += tabs
        mount_opts = [item for item in mount_map[mount_key]['mountOptions'] 
                      if not item in exclude_mount_opts]
        mount_opts += extra_mount_opts
        line += '-' + ','.join(mount_opts)
        line += '\t'
        line += mount_map[mount_key]['cn']
        print(line)


def main():
    if len(sys.argv) == 2:
        map_data = fetchMapData()
        mount_map = generateMountMapFromMapData(map_data)
        outputMap(mount_map, sys.argv[1])
    else:
        print("Usage:  " + os.path.basename(sys.argv[0]) + 
              " <linux|mac>")

if __name__ == "__main__":
    main()
