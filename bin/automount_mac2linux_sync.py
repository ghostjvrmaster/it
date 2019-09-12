#!/usr/bin/env python

import getpass
import os.path
import subprocess
import sys

"""
    This script reads Open Directory LDAP OS X automount maps and syncs 
    the Linux automount maps living on the same LDAP server to match the 
    OS X configuration.

"""

MOCK = False

LINUX_AUTOMOUNT_LDIF_ADD_TEMPLATE = """
dn: automountKey=%(automountKey)s,automountMapName=auto.tree,cn=automountMap,dc=corp,dc=jauntvr,dc=com
objectClass: automount
automountKey: %(automountKey)s
automountInformation: %(automountInformation)s
"""

NFS_V4_ONLY_SERVER_HOSTS = ["render02.corp.jauntvr.com"]
NFS_MOUNTD_V3_ONLY_SERVER_HOSTS = ["la1-nas1.corp.jauntvr.com", "nas1.corp.jauntvr.com", "nas2.corp.jauntvr.com", "nas3.corp.jauntvr.com"]

def fetchAutomountMapData(platform):
    """ Use ldapsearch to fetch raw data for a set of automount maps. """
    if platform == "Mac":
        dn_prefix = ""
        base_cn = "mounts"
        object_class = "mount"
    elif platform == "Linux":
        dn_prefix = "automountMapName=auto.tree,"
        base_cn = "automountMap"
        object_class = "automount"
    else:
        raise ValueError("Unknown platform \"%s\"." % platform)
    cmd = ("ldapsearch -x -o ldif-wrap=no -h ldap.corp.jauntvr.com " + 
           "-b %scn=%s,dc=corp,dc=jauntvr,dc=com objectClass=%s" % 
           (dn_prefix, base_cn, object_class))
    #print cmd
    split_cmd = cmd.split()
    p = subprocess.Popen(split_cmd, stdout=subprocess.PIPE)
    lines = p.stdout.readlines()
    lines = [line.strip() for line in lines]
    return lines


def generateAutomountMapFromMapData(map_data, platform):
    """ Create a dictionary of dictionaries where each key is a cn and each 
        sub-dictionary is a mount entry """
    if platform == "Mac":
        base_cn = "mounts"
        #key_field = "cn"
        key_field = "mountDirectory"
        string_key_names = ["mountDirectory", "cn"]
        list_key_names = ["mountOptions"]
    elif platform == "Linux":
        base_cn = "automountMap"
        #key_field = "automountInformation"
        key_field = "automountKey"
        string_key_names = ["automountKey", "automountInformation"]
        list_key_names = []
    else:
        raise ValueError("Unknown platform \"%s\"." % platform)

    mount_map = {}
    in_record = False
    for line_num in xrange(len(map_data)):
        line = map_data[line_num]
        if line.startswith('#'):
            continue
        if not in_record:
            if not (",cn=%s,dc=corp,dc=jauntvr,dc=com" % base_cn) in line:
                continue
            else:
                in_record = True
                mount = {}
                continue
        if not line: # Reached the end of a record
            in_record = False
#            if platform == "Linux":
#                mount_key = mount[key_field].split()[1]
#                mount_map[mount_key] = mount
#            else:
#                mount_map[mount[key_field]] = mount
            mount_map[mount[key_field]] = mount
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

def addLinuxAutomountRecord(mount, password):
    print("Adding automount record for \"%s\" targeting \"%s\"." % 
          (mount["automountKey"], mount["automountInformation"]))
    cmd = ("ldapadd -h ldap.corp.jauntvr.com " + 
           "-D uid=diradmin,cn=users,dc=corp,dc=jauntvr,dc=com -w %s" % 
           password)
    ldif_data = LINUX_AUTOMOUNT_LDIF_ADD_TEMPLATE % mount
    print ldif_data
    if not MOCK:
        p = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE, 
                                          stdin=subprocess.PIPE, 
                                          stderr=subprocess.PIPE)
        (stdout_data, stderr_data) = p.communicate(input=ldif_data)
        print("Result: " + stdout_data)
        if stderr_data:
            print("Error: " + stderr_data)
        if p.wait():
            raise ValueError("Error adding LDAP record for \"%s\"." % mount["automountKey"])
    

def removeLinuxAutomountRecord(mount, password):
    print("Removing automount record for \"%s\"." % mount["automountKey"])
    cmd = "ldapdelete -h ldap.corp.jauntvr.com -D uid=diradmin,cn=users,dc=corp,dc=jauntvr,dc=com -w %(password)s automountKey=%(key)s,automountMapName=auto.tree,cn=automountMap,dc=corp,dc=jauntvr,dc=com" % {"key" : mount["automountKey"], "password" : password}
    if not MOCK:
        result = subprocess.check_call(cmd.split())
        if result:
            raise ValueError("Unable to delete key \"%s\"." % key)


def getLinuxMountFromOSXMount(mount):
    #exclude_mount_opts = ['browse', 'bg', 'soft', 'locallocks', 'nolocks']
    exclude_mount_opts = ['browse', 'locallocks', 'nolocks', 'nonegnamecache', 'nfc', 'intr']
    extra_mount_opts = ['intr', 'vers=4', 'minorversion=1', 'sec=sys']
    # HACK:  Don't use NFS 4.1 for CentOS 6 servers
    #if mount["cn"].split(":")[0] in NFS_V4_ONLY_SERVER_HOSTS:
    if True:  # That's everybody for now, but probably ok to remove this - Greg
        extra_mount_opts = ['intr', 'vers=4', 'sec=sys']
    # HACK:  Don't use rpc.mountd version 1 for new QNAPs
    if mount["cn"].split(":")[0] in NFS_MOUNTD_V3_ONLY_SERVER_HOSTS:
        extra_mount_opts.append('nfsvers=3')
    mountOptions = [item for item in mount["mountOptions"] 
                    if not item in exclude_mount_opts]
    mountOptions += extra_mount_opts
    return {
            "automountKey" : mount['mountDirectory'],
            "automountInformation" : '-' + ','.join(mountOptions) + 
                                     ' ' + mount['cn']
           }


def syncMap(osx_mount_map, linux_mount_map, ldap_admin_password):
    osx_mount_keys = osx_mount_map.keys()
    osx_mount_keys.sort()
    linux_mount_keys = linux_mount_map.keys()
    linux_mount_keys.sort()
    x_index = 0
    l_index = 0
    while x_index < len(osx_mount_keys) or l_index < len(linux_mount_keys):
        if (x_index < len(osx_mount_keys) and 
            (l_index == len(linux_mount_keys) or 
             osx_mount_keys[x_index] < linux_mount_keys[l_index])):
            addLinuxAutomountRecord(getLinuxMountFromOSXMount(osx_mount_map[osx_mount_keys[x_index]]), ldap_admin_password)
            x_index += 1
        elif (l_index < len(linux_mount_keys) and 
              (x_index == len(osx_mount_keys) or 
               osx_mount_keys[x_index] > linux_mount_keys[l_index])):
            removeLinuxAutomountRecord(linux_mount_map[linux_mount_keys[l_index]], ldap_admin_password)
            l_index += 1
        else: # x_index and l_index are pointing to equivalent records
            #print("Checking \"%s\"" % osx_mount_keys[x_index])
            osx_mount = osx_mount_map[osx_mount_keys[x_index]]
            linux_mount = linux_mount_map[linux_mount_keys[l_index]]
            gen_linux_mount = getLinuxMountFromOSXMount(osx_mount)
            if not linux_mount == gen_linux_mount:
                removeLinuxAutomountRecord(linux_mount_map[linux_mount_keys[l_index]], ldap_admin_password)
                addLinuxAutomountRecord(getLinuxMountFromOSXMount(osx_mount_map[osx_mount_keys[x_index]]), ldap_admin_password)
            #else:
            #    print("ok")
            x_index +=1
            l_index +=1
        

def main():
    if len(sys.argv) == 3 and "-p" in sys.argv:
        ldap_admin_password = sys.argv[2]
    elif len(sys.argv) == 1:
        ldap_admin_password = getpass.getpass("Enter the diradmin password:\n")
    if (len(sys.argv) == 3 and "-p" in sys.argv) or len(sys.argv) == 1:
        osx_map_data = fetchAutomountMapData("Mac")
        linux_map_data = fetchAutomountMapData("Linux")
        mac_mount_map = generateAutomountMapFromMapData(osx_map_data, "Mac")
        linux_mount_map = generateAutomountMapFromMapData(linux_map_data, "Linux")
        syncMap(mac_mount_map, linux_mount_map, ldap_admin_password)
    else:
        print("Usage:  " + os.path.basename(sys.argv[0]) + " [-p password]")

if __name__ == "__main__":
    main()
