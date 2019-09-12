#!/usr/bin/env python

import getpass
import os.path
import subprocess
import sys

"""
    This script crawls known mount points containing restored 
    project data in vaults and ensures that a Mac automount 
    entry exists for each project under /jaunt/vaults/<site>
    for the data servers at that site.

"""

MOCK = False

LA1_PATHS = [ "/net/la1-nas1.corp.jauntvr.com/vaults1"]
SV1_PATHS = [ "/net/nas1.corp.jauntvr.com/vaults1", 
              "/net/nas2.corp.jauntvr.com/vaults1", 
              "/net/nas3.corp.jauntvr.com/vaults1" 
            ]

EXTRA_DIRS = []
EXCLUDE_DIRS = []

LDAP_HOSTNAME="ldap.corp.jauntvr.com"
LDAP_BASEDN="dc=corp,dc=jauntvr,dc=com"

MOUNT_ADD_LDIF_TEMPLATE = """
dn: cn={filesystem}/{subpath},cn=mounts,{base_dn}s
mountType: nfs
mountDirectory: /jaunt/vaults/{site}/{subpath}
objectClass: mount
objectClass: top
mountOption: bg
mountOption: soft
mountOption: locallocks
mountOption: nolocks
cn: {filesystem}/{subpath}
"""

NFS_V4_ONLY_SERVER_HOSTS = []

def generate_automount_map_for_dir(site, subpath, server_hostname, server_export_path):
    filesystem = server_hostname + ":" + server_export_path
    result = (MOUNT_ADD_LDIF_TEMPLATE.format(
                  { "site" : site,
                    "subpath" : subpath, 
                    "filesystem" : filesystem,
                    "base_dn" : LDAP_BASEDN }
             )
    return result.split('\n')

def gather_sparsed_dirs(paths):
    """ Gather the unique leaf nodes from partially mirrored file trees. """
    for base_path in paths:
        XXX
        
#def fetch_ldap_users():
#    cmd = (("ldapsearch -LLL -x -h %s -b cn=users,%s | " +
#            "egrep '^uid:' | awk '{print $2}' | sort") %
#            (LDAP_HOSTNAME, LDAP_BASEDN))
#    split_cmd = cmd.split()
#    p = subprocess.Popen(["/bin/bash", "-c", cmd], stdout=subprocess.PIPE)
#    lines = p.stdout.readlines()
#    lines = [line.strip() for line in lines]
#    return lines

def fetch_automount_map_data(platform):
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
    cmd = ("ldapsearch -x -o ldif-wrap=no -h " +
           "%s -b %scn=%s,%s objectClass=%s" % 
           (LDAP_HOSTNAME, dn_prefix, base_cn, LDAP_BASEDN, object_class))
    #print cmd
    split_cmd = cmd.split()
    p = subprocess.Popen(split_cmd, stdout=subprocess.PIPE)
    lines = p.stdout.readlines()
    lines = [line.strip() for line in lines]
    return lines


def generate_automount_map_from_map_data(map_data, platform):
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
    #print(str(mount_map))
    return mount_map

def create_LDAP_automount_record(mount, ldap_password):
    username = os.path.basename(mount["cn"])
    filesystem = os.path.dirname(mount["cn"])
    ldif_path = "/tmp/project.ldif"
    ldif_string = (USER_MOUNT_ADD_LDIF_TEMPLATE %
                   { "username" : username,
                     "filesystem" : filesystem,
                     "base_dn" : LDAP_BASEDN })
    if os.path.exists(ldif_path):
        os.remove(ldif_path)
    fd = open(ldif_path, 'w')
    fd.write(ldif_string)
    fd.close()
    w_flag = "-W "
    if ldap_password:
        w_flag = "-w " + ldap_password + " "
    cmd = ("ldapadd -h " + LDAP_HOSTNAME + " " +
           "-D uid=diradmin,cn=users," + LDAP_BASEDN + " " +
           w_flag + "-f " + ldif_path)
    print("Adding LDAP record for " + username + " on " + mount["cn"] + ".")
    result = None
    if not MOCK:
        result = subprocess.check_call(cmd.split())
    os.remove(ldif_path)
    if result:
        raise ValueError("Call to ldapadd failed.")


def delete_LDAP_automount_record(mount, ldap_password):
    dn = "cn=" + mount["cn"] + ",cn=mounts," + LDAP_BASEDN
    w_flag = "-W "
    if ldap_password:
        w_flag = "-w " + ldap_password + " "
    cmd = ("ldapdelete -h " + LDAP_HOSTNAME + " " +
           "-D uid=diradmin,cn=users," + LDAP_BASEDN + " " +
           w_flag + " " + dn)
    print("Deleting LDAP record " + dn + ".")
    result = None
    if not MOCK:
        result = subprocess.check_call(cmd.split())
    if result:
        raise ValueError("Call to ldapdelete failed.  Command was:\n%s\n" % cmd)


def sync_mounts(desired_mount_map, current_mount_map, ldap_admin_password):
    desired_mount_keys = desired_mount_map.keys()
    desired_mount_keys.sort()
    current_mount_keys = current_mount_map.keys()
    current_mount_keys.sort()
    x_index = 0
    l_index = 0
    while x_index < len(desired_mount_keys) or l_index < len(current_mount_keys):
        if (x_index < len(desired_mount_keys) and 
            (l_index == len(current_mount_keys) or 
             desired_mount_keys[x_index] < current_mount_keys[l_index])):
            create_LDAP_automount_record(desired_mount_map[desired_mount_keys[x_index]], ldap_admin_password)
            x_index += 1
        elif (l_index < len(current_mount_keys) and 
              (x_index == len(desired_mount_keys) or 
               desired_mount_keys[x_index] > current_mount_keys[l_index])):
            delete_LDAP_automount_record(current_mount_map[current_mount_keys[l_index]], ldap_admin_password)
            l_index += 1
        else: # x_index and l_index are pointing to equivalent records
            #print("Checking \"%s\"" % desired_mount_keys[x_index])
            desired_mount = desired_mount_map[desired_mount_keys[x_index]]
            current_mount = current_mount_map[current_mount_keys[l_index]]
            if not current_mount == desired_mount:
                delete_LDAP_automount_record(current_mount_map[current_mount_keys[l_index]], ldap_admin_password)
                create_LDAP_automount_record(desired_mount_map[desired_mount_keys[x_index]], ldap_admin_password)
            x_index +=1
            l_index +=1
 

def gather_active_dir_listings(paths):
    """ Given a list of directory paths, build a dictionary with the path 
        names as keys and the directorys' contents as values. """
    result = {}
    for path in paths:
        subdirs = os.listdir(path)
        nonempty_subdirs = [item for item in subdirs if 
                            len(os.listdir(path + os.sep + item))]
        result[path] = nonempty_subdirs
    return result       


def find_matching_contents(key, match_dict):
    """ Given a search key and a dictionary of named lists, return all names 
        of lists that contain the key. """
    result = []
    for (dict_key, dict_value) in match_dict.items():
        if key in dict_value:
            result.append(dict_key)
    return result


def main():
    if len(sys.argv) == 3 and "-p" in sys.argv:
        ldap_admin_password = sys.argv[2]
    elif len(sys.argv) == 1:
        ldap_admin_password = getpass.getpass("Enter the diradmin password:\n")
    if (len(sys.argv) == 3 and "-p" in sys.argv) or len(sys.argv) == 1:
        valid_users = EXTRA_DIRS + fetch_ldap_users()
        users_paths_listings = gather_active_dir_listings(USERS_PATHS)
        desired_map_data = []
        for username in valid_users:
            if username in EXCLUDE_DIRS:
                continue
            homedir_locations = find_matching_contents(username, 
                                                       users_paths_listings)
            if len(homedir_locations) == 0:
                print("Warning:  No home directory found for user %s." % 
                      username)
                continue
            elif len(homedir_locations) > 1:
                raise ValueError("Error:  Multiple home directories found " + 
                                 "for user %s at %s and %s!" %
                                 (username, ",".join(homedir_locations[:-1]), 
                                  homedir_locations[-1]))
            else:
                homedir_location = homedir_locations[0]
            hostname = homedir_location.split(os.sep)[2]
            export_path = os.sep + homedir_location.split(os.sep)[3]
            desired_map_data += generate_automount_map_for_dir(site,
                                                               username, 
                                                               hostname, 
                                                               export_path)
        #print(desired_map_data)
        desired_mount_map = generate_automount_map_from_map_data(desired_map_data, "Mac")
        current_map_data = fetch_automount_map_data("Mac")
        current_mount_map = generate_automount_map_from_map_data(current_map_data, "Mac")
        users_mount_map = {}
        for (key, value) in current_mount_map.items():
            if value["mountDirectory"].startswith("/jaunt/users"):
               users_mount_map[key] = value
        sync_mounts(desired_mount_map, users_mount_map, ldap_admin_password)
    else:
        print("Usage:  " + os.path.basename(sys.argv[0]) + " [-p password]")

if __name__ == "__main__":
    main()
