#!/usr/bin/python

import os
import os.path
import pwd
import sys


"""
    This script is intended to be used to remap files on a user's local machine 
    from the local account's uid numbers to new LDAP uid numbers.  This script 
    must be run after the machine has been bound to the LDAP directory.

    Example:

    sudo id_remap_loca.py 501 greg | tee changes.log
"""

MOCK = False

PATHS = ["/Applications", "/Developer", "/Library", "/opt", "/private", "/Users", "/usr"]

def remapFiles(old_uid, username, path):
    for (dirpath, dirnames, filenames) in os.walk(path):
        for dirname in dirnames:
            path = dirpath + os.sep + dirname
            if os.path.islink(path):
                cur_uid = os.lstat(path).st_uid
                cur_gid = os.lstat(path).st_gid
            else:
                cur_uid = os.stat(path).st_uid
                cur_gid = os.stat(path).st_gid
            if cur_uid == old_uid:
                new_uid = pwd.getpwnam(username).pw_uid
                mock_str = ""
                if MOCK:
                    mock_str = "would "
                #print(path + " -- " + mock_str + "change uid:gid " + 
                #      str(cur_uid) + ":" + str(cur_gid) + " ==> " + 
                #      str(new_uid) + ":20")
                print(",".join([path, str(cur_uid), str(cur_gid), 
                      str(new_uid), "-1"]))
                if not MOCK:
                     if os.path.islink(path):
                         os.lchown(path, new_uid, -1)
                     else:
                         os.chown(path, new_uid, -1)
        for filename in filenames:
            path = dirpath + os.sep + filename
            if os.path.islink(path):
                cur_uid = os.lstat(path).st_uid
                cur_gid = os.lstat(path).st_gid
            else:
                cur_uid = os.stat(path).st_uid
                cur_gid = os.stat(path).st_gid
            if cur_uid == old_uid:
                new_uid = pwd.getpwnam(username).pw_uid
                mock_str = ""
                if MOCK:
                    mock_str = "would "
                #print(path + " -- " + mock_str + "change uid:gid " + 
                #      str(cur_uid) + ":" + str(cur_gid) + " ==> " + 
                #      str(new_uid) + ":20")
                print(",".join([path, str(cur_uid), str(cur_gid), 
                      str(new_uid), "-1"]))
                if not MOCK:
                     if os.path.islink(path):
                         os.lchown(path, new_uid, -1)
                     else:
                         os.chown(path, new_uid, -1)

def main():
    if len(sys.argv) == 3:
        for item in PATHS:
            remapFiles(int(sys.argv[1]), sys.argv[2], item)
    else:
        print("Usage:  " + os.path.basename(sys.argv[0]) + " <old_uid> <username>")

if __name__ == "__main__":
    main()
