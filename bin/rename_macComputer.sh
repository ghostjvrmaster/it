#!/bin/sh
####################################################################################################
#
# ABOUT
#
#   Rename Computer
#
####################################################################################################
#
#   Version 2.0, 16-May-2017, Diganta Saha
#####################################################################################################

/bin/echo "*** Rename Computer script ***" 

### Log current computer name
currentComputerName=`/usr/sbin/scutil --get ComputerName`
/bin/echo " Current Computer Name: $currentComputerName"
/bin/echo " ------------------------------------------- "
/bin/echo " Enter New Name:"   
read newComputerName 

### Set and log new computer name
/usr/sbin/scutil --set ComputerName "$newComputerName"
/usr/sbin/scutil --set HostName "$newComputerName"
/usr/sbin/scutil --set LocalHostName "$newComputerName"

currentHostName=`/usr/sbin/scutil --get HostName`
/bin/echo " Changed Computer Name to $currentHostName"

### Update the JSS
/usr/local/bin/jamf recon
