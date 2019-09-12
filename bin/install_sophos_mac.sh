#!/bin/bash
# Diganta Saha  2017-06-08
# checks for Sophos and then installs from script 

if [ `uname -s` == "Darwin" ]
  then
	if [ `/bin/ls /Library/Frameworks/SophosGenericsCommon.framework | wc | awk '{print $1 "\t"}'` == "3" ]	
	   then 
		echo "Sophos already installed. Please uninstall first" 
           else 
		sudo mkdir /Volumes/mount-smb-tmp
		sudo mount_smbfs -N //guest@sophos-ec.corp.jauntvr.com/SophosUpdate /Volumes/mount-smb-tmp
		sudo /Volumes/mount-smb-tmp/CIDs/S000/ESCOSX/Sophos\ Installer.app/Contents/MacOS/tools/InstallationDeployer --install
		sudo umount /Volumes/mount-smb-tmp
		sudo rmdir /Volumes/mount-smb-tmp
        fi
  else
    echo "Please run this script from a Mac host."
fi

