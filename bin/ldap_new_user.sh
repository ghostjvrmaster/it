#!/bin/bash
# Diganta Saha  2017-06-08


if [ `uname -s` == "Linux" ]
   then
	echo -n "User shortname ?"
	read NEWUSER
	echo -n "Location. nas1 or la1-nas1? *note* no error correction in script :"
	read NASNAME
	mkdir -p /net/${NASNAME}/users1/${NEWUSER}
	sudo rsync -av /net/nas1/users1/_skel/ /net/${NASNAME}/users1/${NEWUSER}/
	sudo chown -R ${NEWUSER}:users /net/${NASNAME}/users1/${NEWUSER}
	sudo /jaunt/groups/it/bin/automount_users_sync.py
	sudo /jaunt/groups/it/bin/automount_mac2linux_sync.py
	sudo /jaunt/groups/it/bin/automount_reload_linux

	# Set up Metacity preferences
	sudo su - ${NEWUSER} -c "gconftool-2 --set /apps/metacity/general/auto_raise --type boolean false"
	sudo su - ${NEWUSER} -c "gconftool-2 --set /apps/metacity/general/focus_mode --type string sloppy"
 	sudo su - ${NEWUSER} -c "gconftool-2 --set /apps/metacity/general/mouse_button_modifier --type string \"<Super>\""

	# Set up file browser preferences
	sudo su - ${NEWUSER} -c "gconftool-2 --set /apps/nautilus/preferences/always_use_browser --type boolean true"
	sudo su - ${NEWUSER} -c "gconftool-2 --set /apps/nautilus/preferences/default_folder_viewer --type string \"list_view\""
  else
    echo "Please run this script from a Linux host."
fi
