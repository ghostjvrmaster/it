#!/bin/bash

USERNAME=$1
GROUPNAME=$(id -gn $USERNAME)

SKEL_PATH=/net/nas1/users1/_skel
USERS_PATH=/net/nas1/users1

if [ ! $1 ]
  then
    echo "Usage:  $0 <user>"
    exit 1
fi
#if [ `uname -s` == "Linux" ]
#  then
if [ ! "$UID" == "0" ]
  then
    echo "You must run as root."
fi
# Flush the LDAP caches
if [ "$(uname -s)" == "Darwin" ]
  then
    launchctl stop com.apple.opendirectord
elif [ "$(uname -s)" == "Linux" ]
  then
    #systemctl restart nslcd.service
    nscd -i group
else
  echo "What sort of platform are you on, anyway?"
fi

# Build the homedir
rsync -av "${SKEL_PATH}/" "${USERS_PATH}/${USERNAME}/"
chown -R $USERNAME "${USERS_PATH}/${USERNAME}/"
chgrp -R $GROUPNAME "${USERS_PATH}/${USERNAME}/"

# Reload automount maps
if [ "$(uname -s)" == "Darwin" ]
  then
    launchctl stop com.apple.opendirectord
    launchctl stop com.apple.autofsd
elif [ "$(uname -s)" == "Linux" ]
  then
    systemctl restart nslcd.service
    systemctl restart autofs.service
else
  echo "What sort of platform are you on, anyway?"
fi

while [ ! -d /jaunt/software/installs/linux ]
  do
    echo "Waiting for mounts..."
    sleep 2;
done
#    # Set up Metacity preferences
#    sudo su - $USERNAME -c "gconftool-2 --set /apps/metacity/general/auto_raise --type boolean false"
#    sudo su - $USERNAME -c "gconftool-2 --set /apps/metacity/general/focus_mode --type string sloppy"
#    sudo su - $USERNAME -c "gconftool-2 --set /apps/metacity/general/mouse_button_modifier --type string \"<Super>\""
#
#    # Set up file browser preferences
#    sudo su - $USERNAME -c "gconftool-2 --set /apps/nautilus/preferences/always_use_browser --type boolean true"
#    sudo su - $USERNAME -c "gconftool-2 --set /apps/nautilus/preferences/default_folder_viewer --type string \"list_view\""

/jaunt/groups/it/bin/automount_users_sync.py
/jaunt/groups/it/bin/automount_mac2linux_sync.py
