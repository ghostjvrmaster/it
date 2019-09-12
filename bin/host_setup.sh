#!/bin/bash

#
# host_setup.sh
# 
# Updates a Workstation, Server or Laptop with the latest Jaunt configuration.
# Always safe to run!

LDAP_SERVERS="ldap.corp.jauntvr.com"
CONFIG_FILE_SERVER="infra01.corp.jauntvr.com"

# TODO:  Traveling hosts get separate Foxpass keys
# TODO:  Fix screen saver too fast


# Internal functions
# args:  packages to install
function VerifyInstalledPackagesUbuntu {
    # Install tools
    if ! dpkg -l $@ > /dev/null 2>&1 || dpkg -l $@ | grep -E '^un |^rc ' > /dev/null
      then
        echo Installing $@
        while fuser /var/lib/dpkg/status > /dev/null 2>&1
          do
            if [ -z $notified ]
              then
                echo -n "Check for unclicked dialog boxes!  Waiting for dpkg lock to be free."
                notified=1
            fi
            echo -n "."
            sleep 1
        done
        apt update
        apt -y install "$@"
    fi
}

# Add demo account users
function CreateDemoUserAccount {
    if [ $USER = 'root' ]
      then
        if ! id demo > /dev/null 2>&1
          then
            useradd --create-home --shell /bin/bash --uid 1100 demo
            echo "Enter the password for the demo user."
            passwd demo
            usermod -a -G sudo demo
        fi
        mkdir -p ~demo/.ssh
        chown demo:demo ~demo/.ssh
        chmod 700 ~demo/.ssh
        cp /jaunt/groups/it/etc/demo.pub ~demo/.ssh/id_rsa.pub
        chown demo:demo ~demo/.ssh/id_rsa.pub
        chmod 755 ~demo/.ssh/id_rsa.pub
        cp /jaunt/groups/it/etc/demo.pem ~demo/.ssh/id_rsa
        chown demo:demo ~demo/.ssh/id_rsa
        chmod 700 ~demo/.ssh/id_rsa
    fi
}

# Activate Ethernet Interfaces
function ActivateEthernetInterfacesCentOS {
    if [ $USER = 'root' ]
      then
        for item in `ls /etc/sysconfig/network-scripts/ifcfg-eth*`
          do
            if=${item:(-4)}  # FIXME:  Breaks after 10 ethernet interfaces
            # Enable enterfaces
            sed 's/^ONBOOT=no$/ONBOOT=yes/' <$item >/tmp/ifcfg-tmp
            chown root:root /tmp/ifcfg-tmp
            chmod 644 /tmp/ifcfg-tmp
            mv /tmp/ifcfg-tmp $item
            sed 's/^MTU=*$/MTU=9000/' <$item >/tmp/ifcfg-tmp
            chown root:root /tmp/ifcfg-tmp
            chmod 644 /tmp/ifcfg-tmp
            mv /tmp/ifcfg-tmp $item
            # Restart interfaces (if safe to do so)
            result=`runlevel`
            runlevel=${result:(-1)}
            if [[ $runlevel != "5" ]] && [[ `cat /sys/class/net/${if}/operstate` != "up" ]]
              then
                ifup ${if}
              else
                echo "Skipping (re-)activation of ${if}.  It would log you out."
            fi
          done
      else
        echo "Skipping enabling of ethernet interfaces due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Prefer IPv4.  Fixes hangups especially with Canonical's apt servers
function PreferIpV4Ubuntu {
    if [ $USER = 'root' ]
      then
        data='precedence ::ffff:0:0\/96  100'
        if ! grep -Pq "^$data$" /etc/gai.conf
          then
            sed -i'' -E "s/#\s?${data}/${data}/" /etc/gai.conf
        fi
        # Config file changes are seen by any newly-started processes
    fi
}

# Install essential administration packages
function InstallSynergyUbuntu {
    if [ $USER = 'root' ]
      then
        # Install tools
        packages="synergy"
        if ! dpkg -l $packages > /dev/null 2>&1 || dpkg -l $packages | grep -e '^un' > /dev/null 
          then
            apt update
            apt -y install $packages
        fi
    fi
}

# Install essential administration packages
function InstallAdminPackagesUbuntu {
    if [ $USER = 'root' ]
      then
        VerifyInstalledPackagesUbuntu ethtool htop iftop iotop iperf3 lm-sensors mesa-utils net-tools nvme-cli screen smbclient sysvbanner traceroute vim xclip
        # Allow anyone to run iftop
        if [ ! -e /usr/bin/iftop ]
          then
            chmod u+s /usr/sbin/iftop
            ln -s ../sbin/iftop /usr/bin/iftop
        fi
        # Allow anyone to run iotop
        if [ ! -e /etc/sudoers.d/jaunt_iotop ]
          then
            echo "%users ALL=(ALL) NOPASSWD:/usr/sbin/iotop" > /etc/sudoers.d/jaunt_iotop
        fi
        # Install Zoom
        packages="zoom libxcb-xtest0"
        if ! dpkg -l $packages > /dev/null 2>&1 || dpkg -l $packages | grep -e '^un' > /dev/null 
          then
            apt -y install libxcb-xtest0
            dpkg -i /jaunt/software/packages/linux/Zoom/zoom_amd64.deb 
        fi
        # Install Slack
        packages="slack-desktop libappindicator1 libindicator7"
        if ! dpkg -l $packages > /dev/null 2>&1 || dpkg -l $packages | grep -e '^un' > /dev/null 
          then
            apt -y install libappindicator1 libindicator7
            dpkg -i /jaunt/software/packages/linux/Slack/slack-desktop-3.3.8-amd64.deb
        fi
    fi
}

# Install USB throughput monitor
function InstallUsbTop {
    if [ $USER = 'root' ]
      then
        VerifyInstalledPackagesUbuntu libboost-dev libpcap-dev
        if ! which cmake > /dev/null
          then
            apt -y install cmake
        fi
        if ! [ -e /usr/local/sbin/usbtop ]
          then
            curl -L -o /tmp/usbtop-release-1.0.tar.gz 'https://github.com/aguinet/usbtop/archive/release-1.0.tar.gz'
            tar xvfz /tmp/usbtop-release-1.0.tar.gz -C /tmp/
            mkdir -p /tmp/usbtop-release-1.0/build
            pushd $PWD
            cd /tmp/usbtop-release-1.0/build
            cmake -DCMAKE_BUILD_TYPE=Release ..
            make
            make install
            popd
            modprobe usbmon
            chmod u+s /usr/local/sbin/usbtop
            # Allow anyone to run modprobe and run usbmon
        fi
        if [ ! -e /usr/local/bin/usbtop ]
          then
            ln -s ../sbin/usbtop /usr/local/bin/usbtop
        fi
        echo "%users ALL=(ALL) NOPASSWD:/sbin/modprobe usbmon" > /etc/sudoers.d/jaunt_usbtop
    fi
}

# Install NVIDIA process monitor
function InstallNvtop {
    if [ $USER = 'root' ]
      then
        if ! which nvtop > /dev/null
          then
            # Install tools
            packages="libncurses5-dev libncursesw5-dev git"  
            if ! dpkg -l $packages > /dev/null 2>&1 || dpkg -l $packages | grep -e '^un' > /dev/null 
              then
                apt -y install $packages
            fi
            if ! which cmake
              then
                apt -y install cmake
            fi
            curl -L -o /tmp/nvtop-1.0.0.tar.gz 'https://github.com/Syllo/nvtop/archive/1.0.0.tar.gz'
            tar xvfz /tmp/nvtop-1.0.0.tar.gz -C /tmp/
            mkdir -p /tmp/nvtop-1.0.0/build
            pushd $PWD
            cd /tmp/nvtop-1.0.0/build
            if !  cmake ..
              then
                cmake .. -DNVML_RETRIEVE_HEADER_ONLINE=True
            fi
            make
            make install
            popd
        fi
    fi
}

# Disable OS Updates
function DisableUpdatePromptUbuntu {
    if [ $USER = 'root' ]
      then
        sed -i'' 's/Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades
    fi

}

function InstallCaptureDependenciesUbuntu {
    if [ $USER = 'root' ]
      then
        VerifyInstalledPackagesUbuntu hdfview hdf5-tools
    fi
}

function InstallLinkDependenciesUbuntu {
    if [ $USER = 'root' ]
      then
        VerifyInstalledPackagesUbuntu awscli jq python-boto3 python-jinja2 
    fi
}

function InstallRealSenseDriversUbuntu {
    if [ $USER = 'root' ]
      then
        # Install RealSense Packages
        packages="librealsense2-udev-rules librealsense2-dkms librealsense2 librealsense2-utils librealsense2-dev librealsense2-dbg intel-realsense-dfu"
        if ! dpkg -l $packages > /dev/null 2>&1 || dpkg -l $packages | grep -e '^un' > /dev/null
          then
            apt-key adv --keyserver keys.gnupg.net --recv-key C8B3A55A6F3EFCDE || sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key C8B3A55A6F3EFCDE
            add-apt-repository "deb http://realsense-hw-public.s3.amazonaws.com/Debian/apt-repo xenial main" -u
            apt update
            apt -y install $packages
            echo "You must reboot to activate the RealSense drivers."
        fi
    fi
}

# Modify group 20 "dialout" to be called group "staff" and 
# group 50 "staff" to group "localstaff" and group 100 from users to localusers
function RenameGroupsUbuntu {
    if [ $USER = 'root' ]
      then
        if grep -q dialout:x:20: /etc/group || ! grep -q staff:x:20: /etc/group
          then
            sed -i'' 's/^dialout:x:20:$/staff:x:20:/' /etc/group
        fi
        if grep -q staff:x:50: /etc/group || ! grep -q localstaff:x:50: /etc/group
          then
            sed -i'' 's/^staff:x:50:$/localstaff:x:50:/' /etc/group
        fi
        if grep -q users:x:100: /etc/group || ! grep -q localusers:x:100: /etc/group
          then
            sed -i'' 's/^users:x:100:$/localusers:x:100:/' /etc/group
        fi
      else
        echo "Skipping groups configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}
# Modify group 20 "games" to be called group "staff" and 
# modify group 100 "users" to be called "localusers"
function RenameGroupsCentos {
    if [ $USER == 'root' ]
      then
        if [ ! `grep games:x:20: /etc/group` = "" ]
          then
            sed 's/^games:x:20:$/staff:x:20:/' </etc/group >/tmp/group
            chown root:root /tmp/group
            chmod 644 /tmp/group
            mv /tmp/group /etc/group
        fi
        if [ ! `grep users:x:100: /etc/group` = "" ]
          then
            sed 's/^users:x:100:$/localusers:x:100:/' </etc/group >/tmp/group
            chown root:root /tmp/group
            chmod 644 /tmp/group
            mv /tmp/group /etc/group
        fi
      else
        echo "Skipping groups configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}


# Configure global umask settings
function ConfigureGlobalUmaskDarwin {
    if [ $USER == 'root' ]
      then
        # First set umask for GUI apps
        os_ver="$(sw_vers -productVersion)"
        os_major_ver="$(echo $os_ver | cut -d '.' -f 1)"
        os_minor_ver="$(echo $os_ver | cut -d '.' -f 2)"
        if [ "$os_major_ver" -eq "10" ] && [ "$os_minor_ver" -ge "4" ] && [ "$os_minor_ver" -le "6" ]
          then
            defaults write /Library/Preferences/.GlobalPreferences NSUmask 2
            chmod 644 /Library/Preferences/.GlobalPreferences.plist
        fi
        if [ "$os_major_ver" -eq "10" ] && [ "$os_minor_ver" -ge "7" ] && [ "$os_minor_ver" -le "9" ]
          then
            ## Set for the system
            #echo "umask 002" > /etc/launchd-user.conf
            # Set for user apps
            # Add 	<key>Umask</key>
            #           <integer>002</integer>
            # to /System/Library/LaunchAgents/com.apple.Finder.plist
            if ! grep Umask /System/Library/LaunchAgents/com.apple.Finder.plist
              then
                python -c "import plistlib; pl = plistlib.readPlist(\"/System/Library/LaunchAgents/com.apple.Finder.plist\") ; pl[\"Umask\"] = \"002\" ; plistlib.writePlist(pl, \"/System/Library/LaunchAgents/com.apple.Finder.plist\")"
            fi
        fi
        if [ "$os_major_ver" -eq "10" ] && [ "$os_minor_ver" -ge "10" ]
          then
             if [ ! -e /private/var/db/com.apple.xpc.launchd/config/user.plist ] || ! grep -A 1 '<key>Umask</key>' /private/var/db/com.apple.xpc.launchd/config/user.plist | grep '<integer>2</integer>' > /dev/null
               then
                 launchctl config user umask 002
             fi
        fi
        # Now set umask for the shell
        umask_code='if [[ `groups` == *users* ]]; then umask 002; fi'
        umask_search="if \[\[ \`groups\` == \*users\* ]]; then umask 002; fi"
        if [ -z "$(grep "$umask_search" /etc/profile)" ]
          then
            echo $umask_code >> /etc/profile
        fi
    else
        echo "Skipping configuration of umask due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}
function ConfigureGlobalUmaskLinux {
    if [ $USER = 'root' ]
      then
        umask_code='if [[ `groups` == *users* ]]; then umask 002; fi'
        umask_search="if \[\[ \`groups\` == \*users\* ]]; then umask 002; fi"
        if [[ `grep "$umask_search" /etc/profile` = "" ]]
          then
            echo $umask_code >> /etc/profile
        fi
      else
        echo "Skipping umask settings config due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Make itadmin user
function CreateITAdminUserDarwin {
    username='itadmin'
    if ! id $username > /dev/null 2>&1  # If $username user does not exist
      then
        if [ $USER = 'root' ]
          then
            # Find out the next available user ID
            #MAXID=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -ug | tail -1)
            #USERID=$((MAXID+1))
            USER_ID=501
            while [ `id $USER_ID >/dev/null 2>&1 ; echo $?` == 0 ]  # While the UID is already taken
              do
                USER_ID=$((USER_ID+1))
            done
            echo "Creating new account $username as uid $USER_ID."
            dscl . create /Users/$username
            dscl . create /Users/$username UserShell /bin/bash
            dscl . create /Users/$username RealName "IT Administrator"
            dscl . create /Users/$username UniqueID $USER_ID
            dscl . create /Users/$username PrimaryGroupID 20
            dscl . create /Users/$username NFSHomeDirectory /Users/$username
            echo "Enter the new password for the $username account:"
            dscl . passwd /Users/$username
            dscl . append /Groups/admin GroupMembership $username
            createhomedir -c -u $username
            # To undo the above:
            # dscl . -list /Users
            # dscl . -delete /Users/<username>
            # rm -rf /Users/<username>
          else
            echo "Skipping IT Admin account creation due to lack of privileges."
            echo "Re-run this script as root to run this module."
        fi
    fi
}
function CreateITAdminUserLinux {
    if [ $USER = 'root' ]
      then
        if ! id itadmin > /dev/null
          then
            groupadd -g 400 itadmin
            useradd -m -u 501 -g 400 -s /bin/bash itadmin
            echo "Enter the password for the itadmin account:"
            passwd itadmin
        fi
      else
        echo "Skipping IT Admin account creation due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Set up sudoers file
function ConfigureSudoersDarwin {
    if [ $USER = 'root' ]
      then
        # Create external sudoers file
        echo "
Defaults        env_keep += \"PYTHONPATH\"
# The following 5 lines are for Deadline
Defaults        env_keep += \"RLM_LICENSE\"
Defaults        env_keep += \"THINKBOX_LICENSE_FILE\"
Defaults        env_keep += \"NUKE_PATH\"
Defaults        env_keep += \"MAGICK_CONFIGURE_PATH\"
Defaults        env_keep += \"LD_LIBRARY_PATH\"
Defaults        !requiretty
Defaults        secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/jaunt/apps/pyhome/bin"

Cmnd_Alias AUTOFS_MGMT = /bin/launchctl stop com.apple.opendirectoryd, /bin/launchctl stop com.apple.autofsd, /bin/rmdir
itadmin ALL = NOPASSWD: AUTOFS_MGMT
web ALL = NOPASSWD: AUTOFS_MGMT
medusa ALL = NOPASSWD: AUTOFS_MGMT
" > /etc/sudoers_jaunt_osx
        chmod 440 /etc/sudoers_jaunt_osx
        # Configure include of external sudoers file
        if [[ `grep "#include /etc/sudoers_jaunt_osx" /etc/sudoers` = "" ]]
          then
            cp /etc/sudoers /tmp/sudoers.$$
            echo "#include /etc/sudoers_jaunt_osx" >> /tmp/sudoers.$$
            visudo -c -f /tmp/sudoers.$$
            if [ $? = 0 ]
              then
                cat /tmp/sudoers.$$ > /etc/sudoers
              else
                echo "Syntax error detected in new sudoers file."
            fi
            rm /tmp/sudoers.$$
        fi
    else
        echo "Skipping sudoers configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}
function ConfigureSudoersLinux {
echo
    if [ $USER = 'root' ]
      then
        echo "
Defaults        env_keep += \"PYTHONPATH\"
# The following 5 lines are for ThinkBox Deadline
Defaults        env_keep += \"RLM_LICENSE\"
Defaults        env_keep += \"THINKBOX_LICENSE_FILE\"
Defaults        env_keep += \"NUKE_PATH\"
Defaults        env_keep += \"MAGICK_CONFIGURE_PATH\"
Defaults        env_keep += \"LD_LIBRARY_PATH\"
Defaults        !requiretty
Defaults	secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/jaunt/apps/pyhome/bin"

%itadmin ALL=(ALL) ALL
%users ALL=NOPASSWD: /bin/systemctl restart autofs
%users ALL=NOPASSWD: /bin/systemctl restart anydesk
" > /etc/sudoers.d/sudoers_jaunt_linux
        chmod 440 /etc/sudoers.d/sudoers_jaunt_linux
    else
        echo "Skipping sudoers configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Set up itadmin .ssh keys
function InstallItadminPasswordlessSSHKeyFileDarwin {
    if [[ $USER == 'root' || $USER == 'itadmin' ]]
      then
        if [ `hostname -s` != $CONFIG_FILE_SERVER ]
          then
            ls /Users/itadmin/.ssh/id_rsa > /dev/null 2>&1
            if [ $? != 0 ] 
              then
                if [ ! -e /Users/itadmin/.ssh ]
                  then
                    mkdir /Users/itadmin/.ssh
                    chown itadmin:staff /Users/itadmin/.ssh
                    chmod 700 /Users/itadmin/.ssh
                fi
                echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDpf7KX8AdOZW0/VgFJk9DrAgvEtG3CpT2SGHueaT3i+fTcuFbw1Hllo8ny3WW/4e4NfQvb5jYjJfe80wunKg+ns3HG9tR1O4Jcyzqh76NC19fbsetYN6DzYGlzc/cgYNJOvg8nMC9D2irFvkBioENJ/EVygAFyCSQ84r0MdjLUMxPps9O0Tc2MqCeHI0LsFermQKFdM4RzU8ENz8LlBBp69CRwlL/FC1etZ2Cy/eE+bNQ+1rAHFoOS0cgZbZwUDeCaleX91M0YMCxN7RUAn0SrBje7kn1/cmuQTptjDvhSN/fSPk372KMN+tIBc8srxKNM5RsYvVttZ88jTqAcrDkL itadmin" >> /Users/itadmin/.ssh/authorized_keys
                sudo chown itadmin:staff /Users/itadmin/.ssh/authorized_keys
                sudo chmod 600 /Users/itadmin/.ssh/authorized_keys
                echo "${CONFIG_FILE_SERVER},10.135.1.30 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDPZRizpMMIZ3GT6EATaqqLjnfPn5T5AUKP4nQqWXD+k12Q4SCnMTpgazskHO3DumbtZ7JfyFriiX2jF4xUIbY0HSIWhNcsxxXltizUbkUHfTwhsDCVyN8NFnOAy88z23eWeiEyAorNF2hNeekgjZ32kUyROfqYfVLuPTmmtPc6R68hOXj0rB/MBYtVGBFnML9FJeGW7IHsAvBeiZEWBehxbiETx+6RK0SzKUDqgLVwBdJN/9QPj4gkfQZ+VZVf54QzlXc9wC/V0hFgrywsjB5aPuW9gAnAOFyaNfoFQESukIz6ENdoVAV+Otn4Rnbxrq9UXnkpD1c7ao9DkCeDnqvJ" > /Users/itadmin/.ssh/known_hosts
                chown itadmin:staff /Users/itadmin/.ssh/known_hosts
                chmod 700 /Users/itadmin/.ssh/known_hosts
                scp itadmin@${CONFIG_FILE_SERVER}:/home/itadmin/.ssh/id_rsa /Users/itadmin/.ssh/id_rsa
                chown itadmin:staff /Users/itadmin/.ssh/id_rsa
                chmod 700 /Users/itadmin/.ssh/id_rsa
            fi
        fi
      else
        echo "Skipping itadmin ssh key configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}
function InstallItadminPasswordlessSSHKeyFileLinux {
    if [ $USER == 'root' ] 
      then
        if [ `hostname -s` != $CONFIG_FILE_SERVER ]
          then
            if [ ! -e /home/itadmin/.ssh ]
              then
                mkdir -p /home/itadmin/.ssh
                chown itadmin:itadmin /home/itadmin/.ssh
                chmod 711 /home/itadmin/.ssh
            fi
            echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDpf7KX8AdOZW0/VgFJk9DrAgvEtG3CpT2SGHueaT3i+fTcuFbw1Hllo8ny3WW/4e4NfQvb5jYjJfe80wunKg+ns3HG9tR1O4Jcyzqh76NC19fbsetYN6DzYGlzc/cgYNJOvg8nMC9D2irFvkBioENJ/EVygAFyCSQ84r0MdjLUMxPps9O0Tc2MqCeHI0LsFermQKFdM4RzU8ENz8LlBBp69CRwlL/FC1etZ2Cy/eE+bNQ+1rAHFoOS0cgZbZwUDeCaleX91M0YMCxN7RUAn0SrBje7kn1/cmuQTptjDvhSN/fSPk372KMN+tIBc8srxKNM5RsYvVttZ88jTqAcrDkL itadmin" >> /home/itadmin/.ssh/authorized_keys
            chown itadmin:itadmin /home/itadmin/.ssh/authorized_keys
            chmod 600 /home/itadmin/.ssh/authorized_keys
            # The following must be run interactively to enter the admin password.
            if ! [ -e /home/itadmin/.ssh/id_rsa ] 
              then
                scp -o "StrictHostKeyChecking no" itadmin@${CONFIG_FILE_SERVER}:/home/itadmin/.ssh/id_rsa /home/itadmin/.ssh/id_rsa
                chown itadmin:itadmin /home/itadmin/.ssh/id_rsa
                chmod 600 /home/itadmin/.ssh/id_rsa
            fi
            chmod 700 /home/itadmin/.ssh
        fi
    fi
}


# Set up shell environment configuration for the itadmin user
function ConfigureItadminProfile {
    if [[ $USER = 'root' || $USER = 'itadmin' ]]
      then
        # Create external profile file
        echo "
##### WARNING:  THIS FILE IS AUTOMATICALLY GENERATED BY                 #####
#####           /jaunt/groups/it/bin/host_setup.sh                      #####
#####           CHANGES MADE TO THIS FILE WILL BE LOST                  #####
export PYTHONPATH=\"/jaunt/apps/pyhome/lib\"
" > ~itadmin/.profile_jaunt
        chmod 644 ~itadmin/.profile_jaunt
        # Configure include of external profile file
        if [ ! -e ~itadmin/.profile ]
          then
            touch ~itadmin/.profile
        fi
        if [[ `grep "source .profile_jaunt" ~itadmin/.profile` = "" ]]
          then
            cp ~itadmin/.profile /tmp/.profile.$$
            echo "source .profile_jaunt" >> /tmp/.profile.$$
            chown itadmin:staff /tmp/.profile.$$
            chmod 644 /tmp/.profile.$$
            mv /tmp/.profile.$$ ~itadmin/.profile
        fi
      else
        echo "Skipping itadmin profile configuration due to lack of privileges."
        echo "Re-run this script as root or itadmin to run this module."
    fi
}

# Enable ssh (on mac)
function EnableRemoteLoginDarwin {
    if [ $USER = 'root' ]
      then
        if [ `systemsetup -getremotelogin | awk '{print $3}'` != "On" ]
          then
            systemsetup -setremotelogin on
            dseditgroup -o create -q com.apple.access_ssh
            dseditgroup -o edit -a admin -t group com.apple.access_ssh
        fi
      else
        echo "Skipping remote login configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
     fi
}
# Enable ssh (on Ubuntu)
function EnableRemoteLoginUbuntu {
    if [ $USER = 'root' ]
      then
        VerifyInstalledPackagesUbuntu openssh-server
      else
        echo "Skipping ssh configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
     fi
}


# Configure Vim as the default editor
function ConfigureDefaultEditorUbuntu {
    if [ $USER = 'root' ]
      then
        echo "3" | update-alternatives --config editor
    fi
}


# Configure LDAP
function ConfigureLDAPDarwin {
    if [ $USER = 'root' ]
      then
        # Macs will not bind to OpenDirectory over SSL without the host 
        # in the /etc/hosts file.  Don't know why. - Greg
        if [[ `grep "10.135.1.20	ldap.corp.jauntvr.com" /etc/hosts` = '' ]]
          then
            echo "10.135.1.20	ldap.corp.jauntvr.com" >> /etc/hosts
        fi
        # Add new LDAP server
        if [[ ! `dscl localhost -list /LDAPv3` =~ 'ldap.corp.jauntvr.com' ]] # If not already bound
          then
            ping -o -t 3 ldap.corp.jauntvr.com > /dev/null 2>&1
            if [ $? = 0 ]   # If ldap.corp.jauntvr.com is pingable
              then
                dsconfigldap -a ldap.corp.jauntvr.com -N
                # Check the above with:
                # dscl localhost -list /LDAPv3
                # Unbind with:
                # dsconfigldap -sr ldap.corp.jauntvr.com
              else
                echo "LDAP Server not reachable.  Skipping LDAP configuration."
            fi
        fi
    else
        echo "Skipping LDAP configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

function ConfigureAutomountLDAPUbuntu {
    if [ $USER = 'root' ]
      then
        if [ "$(lsb_release -r -s | cut -d. -f1)" == "14" ]
          then
            if ! dpkg -l nscd > /dev/null
              then
                apt-get -y install nscd
            fi
            if ! dpkg -l ldap-auth-config >/dev/null 2>&1
              then
                    echo "Follow the instructions at https://jauntvr.atlassian.net/wiki/display/IT/Systems+Procedures#SystemsProcedures-ConfigureUbuntuhostasanLDAPClienttoOpenDirectoryServer"
                    read -p "Press [Enter] to enter configuration tool:"
                    apt-get -y install ldap-auth-config
                    auth-client-config -t nss -p lac_ldap
                    service nscd restart
            fi
        elif [ "$(lsb_release -r -s | cut -d. -f1)" == "16" ] || [ "$(lsb_release -r -s | cut -d. -f1)" == "18" ]
          then
            data='^dns=dnsmasq'
            if grep -Pq "$data" /etc/NetworkManager/NetworkManager.conf
              then
                sed -i'' -E "s/${data}/#dns=dnsmasq/" /etc/NetworkManager/NetworkManager.conf
                systemctl restart NetworkManager
            fi
            changed=False
            packages="autofs nfs-common autofs-ldap libnss-ldapd ldap-utils libpam-ldapd ldap-auth-client ldap-auth-config"
            if ! dpkg -l $packages > /dev/null 2>&1 || dpkg -l $packages | grep -e '^un' > /dev/null
              then
                # Install tools
                while fuser /var/lib/dpkg/status > /dev/null 2>&1
                  do
                    if [ -z $notified ]
                      then
                        echo -n "Check for unclicked dialog boxes!  Waiting for dpkg lock to be free."
                        notified=1
                    fi
                    echo -n "."
                    sleep 1
                done
                apt update
                export DEBIAN_FRONTEND=noninteractive
                apt -y install $packages
            fi
#            if ! grep -qs dc=corp,dc=jauntvr,dc=com /etc/ldap.conf 
#              then
#                echo "
#base dc=corp,dc=jauntvr,dc=com
#uri ldap://ldap.corp.jauntvr.com:389
#ldap_version 3
#pam_password md5
#nss_initgroups_ignoreusers _apt,avahi,avahi-autoipd,backup,bin,colord,daemon,dnsmasq,games,gnats,hplip,irc,kernoops,libuuid,lightdm,list,lp,mail,man,messagebus,news,nvidia-persistenced,postfix,proxy,pulse,root,rtkit,saned,speech-dispatcher,sshd,statd,sync,sys,syslog,systemd-bus-proxy,systemd-network,systemd-resolve,systemd-timesync,usbmux,uucp,uuidd,whoopsie,www-data" >> /etc/ldap.conf
#                changed=True
#            fi
            data="LDAP_URI=\"ldap://ldap.corp.jauntvr.com\""
            if ! grep -q "$data" /etc/default/autofs
              then
                echo "$data" >> /etc/default/autofs
                changed=True
            fi
            data="SEARCH_BASE=\"dc=corp,dc=jauntvr,dc=com\""
            if ! grep -q "$data" /etc/default/autofs
              then
                echo "$data" >> /etc/default/autofs
                changed=True
            fi
            data="automount:\tfiles ldap"
            if ! grep -q "automount" /etc/nsswitch.conf
              then
                echo -e "$data" >> /etc/nsswitch.conf
                changed=True
            elif ! grep -Pq "$data" /etc/nsswitch.conf
              then
                sed -i'' "s/^automount:.*/$data/" /etc/nsswitch.conf
                changed=True
            fi
            data="+auto.master\t\t# Use directory service"
            if ! grep -q "+auto.master" /etc/auto.master
              then
                echo -e "$data" >> /etc/auto.master
                changed=True
            elif ! grep -Pq \\"$data" /etc/auto.master
              then
                sed -i'' -E "s/#?\s?\+auto.master.*/$data/" /etc/auto.master
                changed=True
            fi
            data="/net\t\t\t-hosts\t\t-nosuid,nfsvers=3,proto=tcp"
            if ! grep -Pq "/net\s*-hosts.*" /etc/auto.master
              then
                echo -e "$data" >> /etc/auto.master
                changed=True
            elif ! grep -Pq "$data" /etc/auto.master
              then
                sed -i'' -E 's/^#?\s?\/net.*/'\\"$data/" /etc/auto.master
                changed=True
            fi
            if [ $changed == "True" ]
              then
                systemctl restart nslcd.service
                systemctl restart autofs.service
                while [ ! -d /jaunt/software/installs/linux ]
                  do
                    echo "Waiting for mounts..."
                    sleep 2;
                done
            fi
        fi
    else
        echo "Skipping LDAP configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}
function ConfigureLDAPCentos {
    if [ $USER = 'root' ]
      then
        grep ldap.corp.jauntvr.com /etc/sssd/sssd.conf >/dev/null 2>&1
        if [ $? != 0 ]
          then
            echo "Configuring"
            yum -y install sssd pam_ldap
            authconfig --updateall --passalgo=sha512 --enableldap --enableldapauth --ldapserver=ldap.corp.jauntvr.com --ldapbasedn=dc=corp,dc=jauntvr,dc=com --disableldaptls --enablesssd --enablesssdauth
        fi
        # Also need "ldap_tls_reqcert = never" in [domain/default] in
        # /etc/sssd/sssd.conf.  I'm not sure where OD serves up its certs
        # so we can tell LDAP for Linux where to get them and make secure 
        # LDAP work.  - Greg
        if [[ `grep "ldap_tls_reqcert = never" /etc/sssd/sssd.conf` = "" ]]
          then
            #echo "ldap_tls_reqcert = never" >> /etc/sssd/sssd.conf
            python -c "import ConfigParser; cp = ConfigParser.RawConfigParser(); cp.read('/etc/sssd/sssd.conf');cp.set('domain/default', 'ldap_tls_reqcert', 'never'); cp.write(open('/tmp/sssd.conf', 'w'))"
            chmod 600 /tmp/sssd.conf
            mv /tmp/sssd.conf /etc/sssd/sssd.conf
            service sssd restart
        fi
      else
        echo "Skipping LDAP configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

function ConfigureFoxpassUbuntu {
    if [ ${USER} = 'root' ]
      then
        if ! getent group foxpass-sudo > /dev/null
          then
            __InstallFoxpassUbuntu
        fi
      else
        echo "Skipping LDAP configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

function ReInstallFoxpassUbuntu {
    if [ ${USER} = 'root' ]
      then
        __InstallFoxpassUbuntu
      else
        echo "Skipping LDAP configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

function __InstallFoxpassUbuntu {
    if [ -z "${FOXPASS_LOC}" ]
      then
        if [[ $(hostname -I) == 10.135.* ]]
          then
            FOXPASS_LOC=sanmateo
        elif [[ $(hostname -I) == 10.132.* ]]
          then
            FOXPASS_LOC=chicago
        else
            FOXPASS_LOC=remoteworker
        fi
    fi
    if [ -z "${FOXPASS_LDAPBIND}" ]
      then
        read -r -s -p "Enter Foxpass LDAP Bind Password for linux-${FOXPASS_LOC}: " FOXPASS_LDAPBIND
    fi
    echo
    if [ -z "${FOXPASS_APIKEY}" ]
      then
        read -r -s -p "Enter Foxpass API Key for sshd-${FOXPASS_LOC}: " FOXPASS_APIKEY
    fi
    if [ -n "${FOXPASS_LDAPBIND}" ] && [ -n "${FOXPASS_APIKEY}" ]
      then
        if [ "$(lsb_release -r -s | cut -d. -f1)" == "14" ]
          then
            wget https://raw.githubusercontent.com/foxpass/foxpass-setup/master/linux/ubuntu/14.04/foxpass_setup.py
        elif [ "$(lsb_release -r -s | cut -d. -f1)" == "16" ]
          then
            wget https://raw.githubusercontent.com/foxpass/foxpass-setup/master/linux/ubuntu/16.04/foxpass_setup.py
        elif [ "$(lsb_release -r -s | cut -d. -f1)" == "18" ]
          then
            wget https://raw.githubusercontent.com/foxpass/foxpass-setup/master/linux/ubuntu/18.04/foxpass_setup.py
        fi
        python3 foxpass_setup.py --base-dn dc=jauntvr,dc=com --bind-user linux-"${FOXPASS_LOC}" --bind-pw "${FOXPASS_LDAPBIND}" --api-key "${FOXPASS_APIKEY}" --sudoers-group foxpass-sudo-rnd
    else
        echo "Passwords not entered.  Skipping Foxpass install."
    fi
}

function InstallAnyDeskUbuntu {
    if [ $USER = 'root' ]
      then
        if ! dpkg -l anydesk > /dev/null 2>&1 || dpkg -l anydesk | grep -E '^un |^rc ' > /dev/null
          then
            #dpkg -i /jaunt/software/packages/linux/AnyDesk/anydesk_5.0.0-1_amd64.deb
            dpkg -i /jaunt/software/packages/linux/AnyDesk/anydesk_5.1.1-1_amd64.deb
            config="ad.anynet.pwd_hash=7fff0aef91287c12a7fd73868aed0dece8d2369e652af37b4223e162cbd7c0cd\nad.anynet.pwd_salt=2d6c98ac450ee1ed8f955dd5e71631f0\nad.anynet.accept_volatile_tokens=\nad.anynet.token_salt=febdef1e60df9b614bec8b2d8f08b6f2"
            echo -e "$config" >> /etc/anydesk/service.conf
            # system.conf is written with current config at stop or restart time.  
            # Always stop it before changing it.
            systemctl stop anydesk 
            config="ad.security.interactive_access=0\nad.features.unattended=true\nad.security.allow_logon_token=false\nad.security.block_input=false\nad.security.acl_enabled=true\nad.security.acl_list=*@jauntxr.com:true\nad.security.acl_trigger=true"
            echo -e "$config" >> /etc/anydesk/system.conf
            systemctl start anydesk
            read -r -s -p "Enter AnyDesk License Key: " ANYDESK_LICENSE_KEY
            echo $ANYDESK_LICENSE_KEY | anydesk --register-license
            #systemctl stop anydesk 
            hostname=$(hostname -s)@jauntxr.com
            #sed -i'' "s/ad.anynet.alias=.*/ad.anynet.alias=${hostname}/" /etc/anydesk/system.conf 
            #systemctl start anydesk 
            anydesk_client_id=$(anydesk --get-id)
            echo Go to https://my.anydesk.com/clients with password using https://www.secretserveronline.com/SecretView.aspx?secretid=1463034 to set the host alias for client $anydesk_client_id to \"$hostname\" 
        fi
    fi
}
        
        
function InstallZsh {
    if [ $USER = 'root' ]
      then
          if [ ! -e /usr/local/bin/zsh ]
            then
                cd /tmp
                yum install -y ncurses-devel
                tar xvfz /jaunt/software/packages/linux/zsh/zsh-5.3.1.tar.gz
                cd /tmp/zsh-5.3.1
                sudo /tmp/zsh-5.3.1/configure
                sudo make
                sudo make install
          fi
    fi
}

# Utility for fixing broken LDAP connection.  Not part of the normal 
# config process.
function LDAPReconfigureDarwin {
    if [[ `dscl localhost -list /LDAPv3` =~ 'ldap.local' ]]  # If already bound
      then
        dsconfigldap -sr ldap.local
    fi
    dsconfigldap -a ldap.corp.jauntvr.com -N
}


# TODO: on Linux, apt-get -y install ldap-utils

function ConfigureAutoMasterDarwin {
    if [ $USER = 'root' ]
      then
        cp /etc/auto_master /tmp/auto_master
        if [[ `grep "+auto_master" /tmp/auto_master` = '' ]]
          then
            echo "+auto_master\t\t# Use directory service" >> /tmp/auto_master
          else
            sed -E 's/#\s?\+auto_master/\+auto_master/' /tmp/auto_master >/tmp/auto_master_tmp
            mv /tmp/auto_master_tmp /tmp/auto_master
        fi
        if [[ `grep "/net\t\t\tauto_net" /etc/auto_master` = '' ]]
          then
            if [[ `grep "/net" /tmp/auto_master` != '' ]]
              then
                sed -E 's/^\/net/#\/net/' /tmp/auto_master >/tmp/auto_master_tmp
                mv /tmp/auto_master_tmp /tmp/auto_master
            fi
            echo -e "/net\t\t\tauto_net" >> /tmp/auto_master
        fi
        if [ ! -f /etc/auto_net ]
          then
            read -d '' -r auto_net_file << EndOfAutoNet
#!/bin/sh
if [ \$# = 0 ]
  then
    echo ""
else
    /usr/bin/showmount -e -3 \$1 | awk 'NR > 1 {print \$1"        '\$1':"\$1 " \\\\"}' | sort
fi
EndOfAutoNet
            echo "${auto_net_file}" > /etc/auto_net
            chmod 755 /etc/auto_net
        fi
        if [[ `grep "/Network/Servers" /tmp/auto_master` = '' ]]
          then
            echo "/Network/Servers\t-fstab" >> /tmp/auto_master
          else
            sed -E 's/#\s?\/Network\/Servers/\/Network\/Servers/' /tmp/auto_master >/tmp/auto_master_tmp
            mv /tmp/auto_master_tmp /tmp/auto_master
        fi
        if [[ `grep "/-\t\t\t-static" /tmp/auto_master` = '' ]]
          then
            echo "/-\t\t\t-static" >> /tmp/auto_master
          else
            sed -E 's/#\s?\/-			-static/\/-			-static/' /tmp/auto_master >/tmp/auto_master_tmp
            mv /tmp/auto_master_tmp /tmp/auto_master
        fi
        chown root:wheel /tmp/auto_master
        chmod 644 /tmp/auto_master
        mv /tmp/auto_master /etc/auto_master
      else
        echo "Skipping Automounter configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}
# vvvv OBSOLETE vvvv
function ConfigureAutomountUbuntu {
    # Old ugly code.  REFACTOR ME.
    if [ $USER = 'root' ]
      then
        if ! dpkg -l autofs > /dev/null
          then
            apt-get -y install autofs
        fi
        if ! dpkg -l nfs-common > /dev/null
          then
            apt-get -y install nfs-common
        fi
        
        if ! dpkg -l autofs-ldap > /dev/null
          then
            apt-get -y install autofs-ldap
        fi
        if [[ `grep "LDAP_URI=\"ldap://ldap.corp.jauntvr.com\"" /etc/default/autofs` = '' ]]
          then
            echo "LDAP_URI=\"ldap://ldap.corp.jauntvr.com\"" >> /etc/default/autofs
        fi
        if [[ `grep "SEARCH_BASE=\"dc=corp,dc=jauntvr,dc=com\"" /etc/default/autofs` = '' ]]
          then
            echo "SEARCH_BASE=\"dc=corp,dc=jauntvr,dc=com\"" >> /etc/default/autofs
        fi
        if [[ `egrep "automount:\s+files ldap" /etc/nsswitch.conf` = '' ]]
          then
            echo "automount:	files ldap" >> /etc/nsswitch.conf
        fi
        cp /etc/auto.master /tmp/auto.master
        if [[ `grep "+auto.master" /tmp/auto.master` = '' ]]
          then
            echo -e "+auto_master\t\t# Use directory service" >> /tmp/auto.master
          else
            sed -E 's/#\s?\+auto.master/\+auto.master/' /tmp/auto.master >/tmp/auto.master_tmp
            mv /tmp/auto.master_tmp /tmp/auto.master
        fi
        if [[ `grep "/net" /tmp/auto.master` = '' ]]
          then
            echo -e "/net\t\t\t-hosts\t\t-nosuid,nfsvers=3,proto=tcp" >> /tmp/auto.master
          else
            sed -E 's/#\s?\/net/\/net/' /tmp/auto.master >/tmp/auto.master_tmp1
            sed -E 's/^\/net.*$/\/net\t\t\t-hosts\t\t-nosuid,nfsvers=3/' /tmp/auto.master_tmp1 >/tmp/auto.master_tmp2
            rm /tmp/auto.master_tmp1
            mv /tmp/auto.master_tmp2 /tmp/auto.master
        fi
        chown root:root /tmp/auto.master
        chmod 644 /tmp/auto.master
        mv /tmp/auto.master /etc/auto.master
        if [ "$(lsb_release -r -s | cut -d. -f1)" == "14" ]
          then
            # Configure Kerberos GSSD to prevent timeout errors when mounting
            if [[ `grep "NEED_GSSD=yes" /etc/default/nfs-common` = "" ]]
              then
                sed 's/^NEED_GSSD=$/NEED_GSSD=yes/' </etc/default/nfs-common >/tmp/nfs-common
                chown root:root /tmp/nfs-common
                chmod 644 /tmp/nfs-common
                mv /tmp/nfs-common /etc/default/nfs-common
            fi
        fi
        if [ "$(lsb_release -r -s | cut -d. -f1)" == "14" ]
          then
            service autofs start
          else
            systemctl restart autofs
        fi
      else
        echo "Skipping Automounter configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}
# ^^^^ OBSOLETE ^^^^
function AutomountConfigureCentOS {
    if [ $USER = 'root' ]
      then
        sudo yum -y install autofs nfs-utils
#centos7 Add for centos7, may throw an error (AS)
	systemctl stop autofs.service
	systemctl enable autofs.service
	systemctl start autofs.service
#END centos7 Add for centos7, may throw an error (AS)
	
        if [ ! -e /jaunt ]
          then
            mkdir /jaunt
        fi
        if ! egrep -q "automount:\s+files ldap" /etc/nsswitch.conf
          then
            sed -i'' -r 's/^automount:\s+files.*$/automount:  files ldap/' /etc/nsswitch.conf
        fi
      else
        echo "Skipping Automounter configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Configure delayed autofs start due to slow Cisco port start
# Fixes broken automounter on boot 
# (which can be fixed manually by "service autofs reload")

function ConfigureDelayedAutomountStartCentOS { 
    if [ $USER = 'root' ]
      then
        if [[ `grep "sleep 10" /etc/rc.d/init.d/autofs` = "" ]]
          then
            prevline="\techo -n \$\"Starting \$prog: \""
            newline="        sleep 10"
            sed "s/$prevline/$prevline\\
$newline/" /etc/rc.d/init.d/autofs > /tmp/autofs
            chown root:root /tmp/autofs
            chmod 755 /tmp/autofs
            mv /tmp/autofs /etc/rc.d/init.d/autofs
        fi
      else
        echo "Skipping Automounter configuration due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}


# Refresh AutoFS Maps
function AutomountMapReloadDarwin {
    if [[ ! $LDAP_SERVERS =~ `hostname -s` ]] # Don't run this on an LDAP server
      then
        sudo launchctl stop com.apple.opendirectoryd
    fi
    sleep 3
    sudo launchctl stop com.apple.autofsd
    sleep 10
}
function AutomountMapReloadUbuntu {
    # FIXME:  The following line causes hung mounts!  Fixed now?
    #sudo service autofs stop
    #sudo rm /etc/mtab~*
    #sudo service autofs start
    # Does this line actually work?  Nope.
    if [ "$(lsb_release -r -s | cut -d. -f1)" == "14" ]
      then
        #sudo service autofs reload
        echo "This is impossible on Ubuntu 14. Have a nice day."
    elif [ "$(lsb_release -r -s | cut -d. -f1)" == "16" ] || [ "$(lsb_release -r -s | cut -d. -f1)" == "18" ]
      then
        systemctl nslcd restart
        systemctl autofs restart
    fi
}
function AutomountMapReloadCentOS {
    if [ $USER = 'root' ]
      then
          service autofs reload
      else  # $USER is itadmin, web or medusa
          sudo service autofs reload
    fi
}
#Platform-independent helper function

# Added fix for centos7 (AS)
function InstallRedhatLsbCore {
	yum install -y redhat-lsb-core
#	execute `yum install -y redhat-lsb-core`
}
function InstallAutoFSandEnable {
      yum install -y autofs
      systemctl enable autofs.service
      systemctl start autofs.service
}
function InstallNFS-Utils {
	yum install -y nfs-utils
}


# END of Added fix for centos7 (AS)
function AutomountMapReload {
  if [ `uname -s` = 'Darwin' ]
    then
      AutomountMapReloadDarwin
  elif [ `lsb_release -i | awk '{print $3}'` = 'Ubuntu' ]
    then
      AutomountMapReloadUbuntu
  elif [ `lsb_release -i | awk '{print $3}'` = 'Ubuntu' ]
    then
      AutomountMapReloadCentOS
  fi
}

# Delete stray AutoFS directories
function RemoveDeadAutomountDirectories {
    # IF directory
    #    is in the top 3 levels under /jaunt
    #    Has no subdirectories
    #    df shows it is on the root filesystem
    #  then rmdir it
    # We do the following find/while craziness in order to support 
    # bottom-up breadth-first search with spaces in directory names
    if [ $USER = 'root' ]
      then
        find /jaunt -maxdepth 3 -mindepth 3 -type d -print0 | while read -d $'\0' path
          do
            if [ `ls "$path" | wc -l` = 0 ]
              then
                if [ ! `df "$path" | awk '/^nas/ {print $1}'` ]
                  then
                    echo "Removing dead automount path: $path"
                    sudo rmdir "$path"
                fi
            fi
        done
        find /jaunt -maxdepth 2 -mindepth 2 -type d -print0 | while read -d $'\0' path
          do
            if [ `ls "$path" | wc -l` = 0 ]
              then
                if [ ! `df "$path" | awk '/^nas/ {print $1}'` ]
                  then
                    echo "Removing dead automount path: $path"
                    sudo rmdir "$path"
                fi
            fi
        done
        find /jaunt -maxdepth 1 -mindepth 1 -type d -print0 | while read -d $'\0' path
          do
            if [ `ls "$path" | wc -l` = 0 ]
              then
                if [ ! `df "$path" | awk '/^nas/ {print $1}'` ]
                  then
                    echo "Removing dead automount path: $path"
                    sudo rmdir "$path"
                fi
            fi
        done
      else
        echo "Skipping dead automount directory cleanup due to lack of "
        echo "privileges.  Re-run this script as root to run this module."
    fi
}

# Set up X logins to allow users to type their username
function ConfigureGreeterManualLoginUbuntu {
    if [ $USER = 'root' ]
      then
        if [ "$(lsb_release -r -s | cut -d. -f1)" == "16" ]
          then
            if [ ! -e /usr/share/lightdm/lightdm.conf.d/50-jaunt-custom.conf ]
              then
                text="[SeatDefaults]\ngreeter-show-manual-login=true\nallow-guest=false\ngreeter-hide-users=true"
                echo -e "$text" > /usr/share/lightdm/lightdm.conf.d/50-jaunt-custom.conf
            fi
        elif [ "$(lsb_release -r -s | cut -d. -f1)" == "18" ]
          then
            text="disable-user-list=true"
            if ! grep -q "$text" /etc/gdm3/greeter.dconf-defaults
              then
                echo "$text" >> /etc/gdm3/greeter.dconf-defaults
            fi
        fi
    fi
}

# Delete stray AutoFS project directories
function RemoveDeadProjectDirectories {
    # IF df shows project directory is on the root system
    #  then rmdir it
    if [ $USER = 'root' ]
      then
        find /jaunt/prod/projects -type d -maxdepth 1 -mindepth 1 -exec rmdir '{}' 2> /dev/null \;
      else
        echo "Skipping dead automount directory cleanup due to lack of "
        echo "privileges.  Re-run this script as root to run this module."        
          
    fi
}


# Set up /apps link
function CreateJauntAppsSymlinkDarwin {
    if [ $USER == 'root' ]
      then
        if [ ! -d /jaunt/apps ]
          then
            rm -rf /jaunt/apps
        fi
        if [ ! -h /jaunt/apps ]
          then
            SAVED_WD="$PWD"
            cd /jaunt
            ln -s /jaunt/software/installs/darwin apps
            cd "$PWD"
        fi
    else
        echo "Skipping creation of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}
function CreateJauntAppsSymlinkLinux {
    if [ $USER == 'root' ]
      then
        if [ ! -d /jaunt/apps ]
          then
            rm -rf /jaunt/apps
        fi
        if [ ! -h /jaunt/apps ]
          then
            SAVED_WD="$PWD"
            cd /jaunt
            ln -s /jaunt/software/installs/linux apps
            cd "$PWD"
        fi
    else
        echo "Skipping creation of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Sync apps locally
function SyncSharedAppsDarwin {
    if [ $USER == 'root' ]
      then
        if [ -h /jaunt/apps ]
          then
            rm /jaunt/apps
        fi
        while [ ! -d /jaunt/software/installs/darwin ]
          do
            echo "Waiting for mounts..."
            sleep 2;
        done
#        rsync -rtLv --delete --size-only --exclude latest /jaunt/software/installs/darwin/ /jaunt/apps/
#        rsync -rtlv --prune-empty-dirs --include=latest --include=\*/ --exclude=\* /jaunt/software/installs/darwin/ /jaunt/apps/
        # This line activates the automount point if it is not yet active
        ls /jaunt/software/installs/darwin/ > /dev/null
        rsync --delete -rtlv --progress --exclude=/pyhome /jaunt/software/installs/darwin/ /jaunt/apps/
        rsync -rtLv --progress /jaunt/software/installs/darwin/pyhome /jaunt/apps/
        chown -R treeadmin:users /jaunt/apps
        chmod -R ug+rw /jaunt/apps
        chmod -R o+r /jaunt/apps
        
    else
        echo "Skipping syncing of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}


function SyncSharedAppsDarwinLA {
    if [ $USER == 'root' ]
      then
        if [ -h /jaunt/apps ]
          then
            rm /jaunt/apps
        fi
        while [ ! -d /net/la1-nas1.corp.jauntvr.com/software1/installs/darwin ]
          do
            echo "Waiting for mounts..."
            sleep 2;
        done
        # This line activates the automount point if it is not yet active
        ls /net/la1-nas1.corp.jauntvr.com/software1/installs/darwin/ > /dev/null
        rsync --delete -rtlv --progress --exclude=/pyhome /net/la1-nas1.corp.jauntvr.com/software1/installs/darwin/ /jaunt/apps/
        rsync -rtLv --progress /net/la1-nas1.corp.jauntvr.com/software1/installs/darwin/pyhome /jaunt/apps/
        chown -R treeadmin:users /jaunt/apps
        chmod -R ug+rw /jaunt/apps
        chmod -R o+r /jaunt/apps
        
    else
        echo "Skipping syncing of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}


function SyncSharedAppsLiteDarwin {
    if [ $USER == 'root' ]
      then
        if [ -h /jaunt/apps ]
          then
            rm /jaunt/apps
        fi
        while [ ! -d /jaunt/software/installs/darwin ]
          do
            echo "Waiting for mounts..."
            sleep 2;
        done
#        rsync -rtLv --delete --size-only --exclude latest /jaunt/software/installs/darwin/ /jaunt/apps/
#        rsync -rtlv --prune-empty-dirs --include=latest --include=\*/ --exclude=\* /jaunt/software/installs/darwin/ /jaunt/apps/
        # This line activates the automount point if it is not yet active
        ls /jaunt/software/installs/darwin/ > /dev/null
        rsync --delete -rtlv --exclude=/pyhome --exclude=/nuke --exclude=/nukehome --exclude=/rv --exclude=/jaunt-player --exclude=/dozer /jaunt/software/installs/darwin/ /jaunt/apps/
        rsync -rtLv /jaunt/software/installs/darwin/pyhome /jaunt/apps/
        chown -R treeadmin:users /jaunt/apps
        chmod -R ug+rw /jaunt/apps
        chmod -R o+r /jaunt/apps
        
    else
        echo "Skipping syncing of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

function SyncSharedNukeDarwin {
    if [ $USER == 'root' ]
      then
        while [ ! -d /jaunt/software/installs/darwin ]
          do
            echo "Waiting for mounts..."
            sleep 2;
        done
        # This line activates the automount point if it is not yet active
        ls /jaunt/software/installs/darwin/ > /dev/null
        rsync --delete -rtlv /jaunt/software/installs/darwin/nuke* /jaunt/apps/
    else
        echo "Skipping syncing of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}


function SyncSharedNukeDarwinLA {
    if [ $USER == 'root' ]
      then
        while [ ! -d /jaunt/software/installs/darwin ]
          do
            echo "Waiting for mounts..."
            sleep 2;
        done
        # This line activates the automount point if it is not yet active
        ls /net/la1-nas1.corp.jauntvr.com/software1/installs/darwin/ > /dev/null
        rsync --delete -rtlv /net/la1-nas1.corp.jauntvr.com/software1/installs/darwin/nuke* /jaunt/apps/
    else
        echo "Skipping syncing of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

function SyncSharedShotgunDarwin {
    if [ $USER == 'root' ]
      then
        while [ ! -d /jaunt/software/installs/darwin ]
          do
            echo "Waiting for mounts..."
            sleep 2;
        done
        # This line activates the automount point if it is not yet active
        ls /jaunt/software/installs/darwin/ > /dev/null
        rsync --delete -av /jaunt/software/installs/darwin/shotgun /jaunt/apps
    else
        echo "Skipping syncing of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}


function SyncSharedShotgunDarwinLA {
    if [ $USER == 'root' ]
      then
        while [ ! -d /jaunt/software/installs/darwin ]
          do
            echo "Waiting for mounts..."
            sleep 2;
        done
        # This line activates the automount point if it is not yet active
        ls /net/la1-nas1.corp.jauntvr.com/software1/installs/darwin/ > /dev/null
        rsync --delete -av /net/la1-nas1.corp.jauntvr.com/software1/installs/darwin/shotgun /jaunt/apps
    else
        echo "Skipping syncing of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}


function SyncSharedAppsLinux {
    if [ $USER == 'root' ]
      then
        if [ -h /jaunt/apps ]
          then
            rm /jaunt/apps
        fi
#centos7 fix
	systemctl reload autofs.service
#END centos7 fix       
        while [ ! -d /jaunt/software/installs/linux ]
          do
            echo "Waiting for mounts LINUX FIX TEST..."
            sleep 2;
        done
        rsync -av --delete --exclude=/pyhome /jaunt/software/installs/linux/ /jaunt/apps/
        rsync -rtLv --progress /jaunt/software/installs/linux/pyhome /jaunt/apps/

#        chown -R treeadmin:users /jaunt/apps/*
#        chmod -R ug+rw /jaunt/apps
#        chmod -R o+r /jaunt/apps
    else
        echo "Skipping syncing of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}



function SyncSharedNukeLinux {
    if [ $USER == 'root' ]
      then
        while [ ! -d /jaunt/software/installs/linux ]
          do
            echo "Waiting for mounts..."
            sleep 2;
        done
        rsync -av --delete /jaunt/software/installs/linux/nuke* /jaunt/apps/
    else
        echo "Skipping syncing of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}


function SyncSharedAutodeskLinux {
    if [ $USER == 'root' ]
      then
        while [ ! -d /jaunt/software/installs/linux ]
          do
            echo "Waiting for mounts..."
            sleep 2;
        done
        rsync -av --delete /jaunt/software/installs/linux/autodesk* /jaunt/apps/
    else
        echo "Skipping syncing of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

function SyncSharedShotgunLinux {
    if [ $USER == 'root' ]
      then
        while [ ! -d /jaunt/software/installs/linux ]
          do
            echo "Waiting for mounts..."
            sleep 2;
        done
        rsync -av --delete /jaunt/software/installs/linux/shotgun /jaunt/apps/
    else
        echo "Skipping syncing of apps link due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

function SyncLARepo {
    if [ $USER = 'root' ]
      then
        sudo rsync -avz /jaunt/software/installs/darwin/ admin@la1-nas1.corp.jauntvr.com:/share/CACHEDEV1_DATA/software1/installs/darwin
    else
        echo "Skipping host_setup.sh install due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Configure mhddfs mount points
function ConfigureMHDDFSDarwin {
    if [ $USER = 'root' ]
      then
        os_ver=$(sw_vers -productVersion)
        os_major_ver=$(echo $os_ver | cut -d '.' -f 1)
        os_minor_ver=$(echo $os_ver | cut -d '.' -f 2)
        if [ ! -e /usr/local/lib/libfuse.dylib ] && [ ! -d /Library/Frameworks/OSXFUSE.framework ]
          then
            echo "Installing Fuse for OS X"
            attach_info=$(hdiutil attach /jaunt/software/packages/darwin/Fuse\ for\ OS\ X/osxfuse-3.3.3.dmg)
            mount_dev=$(echo $attach_info | cut -d ' ' -f 2-)
            # Can't seem to figure out how to get installer to install 
            # a file with spaces in the name...
            cp "/Volumes/FUSE for OS X/FUSE for OS X" /tmp/fuse.pkg
            installer -pkg /tmp/fuse.pkg -target /
            rm /tmp/fuse.pkg
            hdiutil detach "$mount_dev"
        fi
        if [ $os_major_ver -eq "10" ] && [ "$os_minor_ver" -eq "10" ]
          then
            mkdir -p /opt/local/bin
            cp /jaunt/software/packages/darwin/mhddfs/osx-10.10/mhddfs /opt/local/bin/
        elif [ $os_major_ver -eq "10" ] && [ "$os_minor_ver" -eq "11" ]
          then
            #installer -pkg /jaunt/software/packages/darwin/MacPorts/MacPorts-2.3.4-10.11-ElCapitan.pkg -target /
            #/opt/local/bin/port sync
            #port install mhddfs
            mkdir -p /opt/local/bin
            cp /jaunt/software/packages/darwin/mhddfs/osx-10.11/mhddfs /opt/local/bin/
        else
            echo "Your version of OS X is not supported."
            return
        fi
        launch_agent_name="com.jauntvr.mhddfs-vaults-sv1"
        launch_agent_path=/Library/LaunchDaemons/${launch_agent_name}.plist
        if ! launchctl list $launch_agent_name &> /dev/null 
            then
            read -d '' -r plist_template << EndOfPList
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jauntvr.mhddfs-vaults</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>umount /jaunt/vaults ; /opt/local/bin/mhddfs /net/nas1.corp.jauntvr.com/vaults1,/net/nas2.corp.jauntvr.com/vaults1,/net/nas3.corp.jauntvr.com/vaults1 /jaunt/vaults_sv1 -o ro,allow_other,default_permissions,volname=vaults_sv1</string>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/mhddfs-vaults_out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/mhddfs-vaults_err.log</string>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EndOfPList
            echo "${plist_template}" > $launch_agent_path
            launchctl load -w $launch_agent_path
        fi
        # To uninstall:
        #     sudo launchctl stop com.jauntvr.mhddfs-vaults-sv1
        #     sudo launchctl unload /Library/LaunchDaemons/com.jauntvr.mhddfs-vaults-sv1.plist
        #     sudo rm  /Library/LaunchDaemons/com.jauntvr.mhddfs-vaults-sv1.plist
        #mkdir -p /jaunt/vaults_sv1
        #mkdir -p /jaunt/vaults_la1
        #/opt/local/bin/mhddfs /net/nas1.corp.jauntvr.com/vaults1,/net/nas2.corp.jauntvr.com/vaults1,/net/nas3.corp.jauntvr.com/vaults1 /jaunt/vaults_sv1 -o ro,allow_other,default_permissions
    else
        echo "Skipping mhddfs config due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Configure s3fs mount points
function ConfigureS3FSDarwin {
    if [ $USER = 'root' ]
      then
        os_ver=$(sw_vers -productVersion)
        os_major_ver=$(echo $os_ver | cut -d '.' -f 1)
        os_minor_ver=$(echo $os_ver | cut -d '.' -f 2)
        if [ $os_major_ver -gt "10" ] || [ "$os_minor_ver" -gt "10" ]
          then
            echo "ERROR: s3fs-fuse cannot run on OS X releases newer than Yosemite"
            return
        fi
        if [ ! -e /usr/local/lib/libfuse.dylib ]
          then
            echo "Installing Fuse4X"
            attach_info=$(hdiutil attach /jaunt/software/packages/darwin/Fuse4X/Fuse4X-0.9.2.dmg)
            mount_dev=$(echo $attach_info | cut -d ' ' -f 3)
            installer -pkg /Volumes/Fuse4X/Fuse4X.pkg -target /
            hdiutil detach $mount_dev
        fi
#        bucket_list = "production.jauntvr.com medusaqa.jauntvr.com medusadev.jauntvr.com dev-shared.jauntvr.com"
        bucket_list="dev-shared.jauntvr.com"
        for bucket in $bucket_list
          do
            if [ ! -e /mnt/$bucket ]
              then
                mkdir -p /mnt/$bucket
            fi
            launch_agent_name="com.jauntvr.s3fs-${bucket}"
            launch_agent_path=/Library/LaunchDaemons/${launch_agent_name}.plist
            launchctl list $launch_agent_name &> /dev/null
            if [ $? != 0 ]
              then
                if [ ! -e /etc/passwd-s3fs ] || [[ $(grep $bucket /etc/passwd-s3fs) = "" ]]
                  then
                    if [[ "dev-shared.jauntvr.com jauntdev-medusadev-us-west-1 medusaqa.jauntvr.com" =~ $bucket ]]
                      then
                        echo "${bucket}:AKIAIRW6PQCTG5N2YNQQ:tMAw2pLcoUem8NPIio3OUJwalB+sx3e8WFerMZXD" >> /etc/passwd-s3fs
                      else
                        echo "${bucket}:<key>:<secret>" >> /etc/passwd-s3fs
                        echo "Please add your S3 IAM keys to /etc/passwd-s3fs"
                    fi
                    chmod 600 /etc/passwd-s3fs
                fi
                read -d '' -r plist_template << EndOfPList
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jauntvr.s3fs-${bucket}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>umount /mnt/${bucket} ; /jaunt/apps/s3fs/latest/bin/s3fs ${bucket} /mnt/${bucket} -f -o allow_other -o parallel_count=2 -o fd_page_size=20971520</string>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/s3fs-${bucket}_out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/s3fs-${bucket}_err.log</string>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EndOfPList
                result=$(eval echo "'$plist_template'")
                echo "${result}" > $launch_agent_path
                launchctl load $launch_agent_path
            fi
          # To uninstall:
          #     sudo launchctl stop com.jauntvr.s3fs-dev-shared.jauntvr.com
          #     sudo launchctl unload /Library/LaunchDaemons/com.jauntvr.s3fs-dev-shared.jauntvr.com.plist
          #     sudo rm  /Library/LaunchDaemons/com.jauntvr.s3fs-dev-shared.jauntvr.com.plist
          #  for each bucket, plus:
          #     sudo rm /etc/passwd-s3fs
          #  To remove Fuse4X:
          #     sudo /Library/Filesystems/fuse4x.fs/Contents/Executables/uninstall.sh
        done
    else
        echo "Skipping s3fs setup due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

## Configure s3fs mount points
#function ConfigureS3FSUbuntu {
#    if [ $USER = 'root' ]
#      then
#         # Don't need this.  Already installed in /jaunt/apps/s3fs
##        apt-get -y install openssl libssl-dev build-essential libcurl4-nss-dev automake libxml2-dev pkg-config
##        mkdir /tmp/s3fs_install
##
##        # Install fuse
##        cd /tmp/s3fs_install && tar xvf /jaunt/software/packages/linux/Jaunt
##        cd /tmp/s3fs_install/fuse-2.9.3 && ./configure
##        cd /tmp/s3fs_install/fuse-2.9.3 && make install
##
##        # Install fuse-s3fs aa custom
##        cd /tmp/s3fs_install && tar xvfz /jaunt/software/packages/linux/Jaunt/s3fs-fuse-v1.78aa2.tar.gz
##        mv /tmp/s3fs_install/s3fs-fuse /tmp/s3fs_install/s3fs-fuse-v1.78aa2
##        cd /tmp/s3fs_install/s3fs-fuse-1.78aa2 && ./autogen.sh
##        cd /tmp/s3fs_install/s3fs-fuse-1.78aa2 && ./configure
##        cd /tmp/s3fs_install/s3fs-fuse-1.78aa2 && make install
#
#        cp /jaunt/software/packages/linux/Jaunt/s3fs-*.conf /etc/init/
#        mkdir -p /home/medusa
#        chown medusa:services /home/medusa
#        echo "production.jauntvr.com:AKIAIKWXU2Y2MB3CYXBQ:Duw/K4nTU1IbkpAVaCKATH9oDkOnepzsJf24H7GG
#dev-shared.jauntvr.com:AKIAIZYINDZLD24SM72Q:xepgtNNOTYpFiQkFgcfMnmCq8/LRuUmeEu9GWt0S
#medusaqa.jauntvr.com:AKIAJ53DXQB5N3GMJOEQ:vdkPJCj+WQcJ3mDlga5WksQ7QilHSnT52Z3grW90
#medusadev.jauntvr.com:AKIAJ53DXQB5N3GMJOEQ:vdkPJCj+WQcJ3mDlga5WksQ7QilHSnT52Z3grW90" > /home/medusa/.passwd-s3fs
#        chown medusa:services /home/medusa/.passwd-s3fs
#        chmod 600 /home/medusa/.passwd-s3fs
#        start s3fs-dev-shared.jauntvr.com
#        start s3fs-medusaqa.jauntvr.com
#        start s3fs-medusadev.jauntvr.com
#        start s3fs-production.jauntvr.com
#    fi
#}

# Configure s3fs mount points
function ConfigureS3FSUbuntu {
    # This module assumes s3fs is installed at /jaunt/apps/s3fs/latest/bin/s3fs
    if [ $USER = 'root' ]
      then
        if [ ! -e /home/medusa ]
          then
            mkdir -p /home/medusa
            chown medusa:services /home/medusa
        fi
        if ! grep -q "fuse.s3fs" /etc/updatedb.conf
          then
            sed -i'' "s/^PRUNEFS=\"\(.*\)\"$/PRUNEFS=\"\1 fuse.s3fs\"/" /etc/updatedb.conf
        fi
        bucket_list="jauntvr-medusaprod-us-west-1 jauntdev-medusadev-us-west-1 dev-shared.jauntvr.com"
        for bucket in ${bucket_list}
          do
            service_name="s3fs-${bucket}"
            service_path=/etc/init/${service_name}.conf
            if ! status $service_name | grep running >> /dev/null
              then
                if [ ! -e /home/medusa/.passwd-s3fs ] || [ ! $(grep -s ${bucket} /home/medusa/.passwd-s3fs) ]
                  then
                    if [[ "dev-shared.jauntvr.com jauntdev-medusadev-us-west-1 medusaqa.jauntvr.com" =~ ${bucket} ]]
                      then
                        echo "${bucket}:AKIAIRW6PQCTG5N2YNQQ:tMAw2pLcoUem8NPIio3OUJwalB+sx3e8WFerMZXD" >> /home/medusa/.passwd-s3fs
                    elif [[ "production.jauntvr.com jauntvr-medusaprod-us-west-1" =~ $bucket ]]
                      then
                        echo "${bucket}:AKIAJAGN5SGKVQGTAWPA:JcmDeJgQ6FGwPN2q0BKAynZjqFFf/sy/iCyVpo+p" >> /home/medusa/.passwd-s3fs
                    else
                        echo "${bucket}:<key>:<secret>" >> /etc/passwd-s3fs
                        echo -n "Please manually add your S3 IAM keys to "
                        echo "/home/medusa/.passwd-s3fs for the ${bucket} bucket."
                    fi
                    chmod 600 /home/medusa/.passwd-s3fs
                    chown medusa:services /home/medusa/.passwd-s3fs
                fi
                read -d '' -r init_script_template << EndOfInitScript
# (c)2015 Jaunt Inc, Greg Brauer
# Based on pancam/medusa/init_scripts/Ubuntu/s3fs-dev-shared.jauntvr.com
description "Medusa S3FS Filesystem"
author      "Jaunt, Inc."

start on started udev-finish
stop on runlevel [!2345]

respawn

env BUCKET=${bucket}
env MOUNT_POINT=/mnt/${bucket}
env USERNAME=medusa
env GROUPNAME=services
env ROLE=
env ALLOW_OTHER=true
env S3FS_BIN=/jaunt/apps/s3fs/latest/bin/s3fs
# Note: If ALLOW_OTHER="true" and USERNAME!=root , /etc/fuse.conf will
#       be modified.

pre-start script
    if [ ! -d \$MOUNT_POINT ]
      then
        mkdir -p \$MOUNT_POINT
    fi
    chown \$USERNAME:\$GROUPNAME \$MOUNT_POINT
end script

script
    OPT_ALLOW_OTHER=""
    if [ "\$ALLOW_OTHER" = true ]
      then
        if [ \$USERNAME != root ]
          then
            sed -i'' "s/#user_allow_other/user_allow_other/" /etc/fuse.conf
            chmod 644 /etc/fuse.conf
        fi
        OPT_ALLOW_OTHER="-o allow_other"
    fi
    OPT_IAM_ROLE=""
    if [ "\$ROLE" = "auto" ]
      then
        ROLE=\$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)
    fi
    if [ "\$ROLE" != "" ]
      then
        OPT_IAM_ROLE="-o iam_role=\${ROLE}"
    fi
    # Re-create legacy mount point in ephemeral storage
    #if [ ! -e /mnt/scratch ]
    #  then
    #    ln -s "\$MOUNT_POINT" /mnt/scratch
    #fi
    echo su - -c "\${S3FS_BIN} \$BUCKET "\$MOUNT_POINT" -f -o parallel_count=2 -o fd_page_size=20971520 \$OPT_ALLOW_OTHER \$OPT_IAM_ROLE -o uid=100004 -o gid=100000 -o umask=0002" \$USERNAME
    exec su - -c "\${S3FS_BIN} \$BUCKET "\$MOUNT_POINT" -f -o parallel_count=2 -o fd_page_size=20971520 \$OPT_ALLOW_OTHER \$OPT_IAM_ROLE -o uid=100004 -o gid=100000 -o umask=0002" \$USERNAME
end script

pre-stop script
    /usr/local/bin/fusermount -u "\$MOUNT_POINT"
end script
EndOfInitScript
                result=$(eval echo "'$init_script_template'")
                echo "${result}" > $service_path
                start ${service_name}
            fi
          # To uninstall:
          #     sudo stop s3fs-${bucket}
          #     sudo rm s3fs-${bucket}
          #  for each bucket, plus:
          #     sudo rm /etc/passwd-s3fs
        done
    else
        echo "Skipping install of S3FS init scripts due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Add our custom OpenCV and Ceres packages library package
function ConfigureJToolsDependencies {
    if [ $USER = 'root' ]
      then
        if [ ! -e /usr/share/OpenCV/OpenCVModules.cmake ]
          then
            tar xvfz /jaunt/software/packages/linux/Jaunt/OpenCV_3.0rc1_linux.tgz -C /usr
        fi
        if [ ! -e /usr/share/Ceres/FindGlog.cmake ]
          then
            tar xvfz /jaunt/software/packages/linux/Jaunt/ceres_installv1.tgz -C /usr
        fi
    fi
}

function VerifyInstalledCmakeUbuntu {
    if [ $USER = 'root' ]
      then
        if ! /usr/local/bin/cmake --version | grep 3.13.4 > /dev/null || ! which cmake-gui > /dev/null
          then
            VerifyInstalledPackagesUbuntu qt4-default
            # Install cmake >= 3.12.1
            tar xvfz /jaunt/software/packages/linux/CMake/cmake-3.13.4.tar.gz -C /tmp/
            pushd $(pwd)
            cd /tmp/cmake-3.13.4/ && ./configure --qt-gui && ./bootstrap --system-curl && make -j $(nproc) && make install
            popd
        fi
    fi
}

function VerifyInstalledCUDA {
    if [ $USER = 'root' ]
      then
        if ! [ -e /usr/local/cuda-10.0 ]
          then
            if [ "$(lsb_release -r -s | cut -d. -f1)" == "16" ]
              then
                # Install CUDA 10
                dpkg -i /jaunt/software/packages/linux/NVIDIA/cuda-repo-ubuntu1604-10-0-local-10.0.130-410.48_1.0-1_amd64.deb
                apt-key add /var/cuda-repo-10-0-local-10.0.130-410.48/7fa2af80.pub
                apt-get update
                apt-get install -y cuda-toolkit-10-0
                # Want to uninstall?
                # sudo apt purge $(dpkg -l | grep cuda | grep 10 | cut -d ' ' -f 3)
            fi
            if [ "$(lsb_release -r -s | cut -d. -f1)" == "18" ]
              then
                # Install CUDA 10
                dpkg -i /jaunt/software/packages/linux/NVIDIA/cuda-repo-ubuntu1804-10-0-local-10.0.130-410.48_1.0-1_amd64.deb
                apt-key add /var/cuda-repo-10-0-local-10.0.130-410.48/7fa2af80.pub
                apt-get update
                apt-get install -y cuda-toolkit-10-0
            fi
        fi
    fi
}

function VerifyInstalledGitLfs {
    if [ $USER = 'root' ]
      then
        # Install Git-LFS
        if ! git-lfs -v > /dev/null 2>&1
          then
            curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
            apt-get install git-lfs
        fi
    fi
}

function InstallTronBuildDependencies {
    if [ $USER = 'root' ]
      then
        VerifyInstalledPackagesUbuntu python3 python3-pip virtualenv
        VerifyInstalledGitLfs
        VerifyInstalledCmakeUbuntu
        VerifyInstalledCUDA
    fi
}

function InstallVolcapBuildDependencies {
    if [ $USER = 'root' ]
      then
        # Runtime dependencies
        VerifyInstalledPackagesUbuntu freeglut3-dev libusb-1.0-0-dev xorg-dev libglu1-mesa-dev libva-dev libcurl4-openssl-dev libasound2-dev libgtk-3-dev libjsoncpp-dev liblapack3 libblas3 hdfview python-h5py
        # Install clion dependencies
        VerifyInstalledPackagesUbuntu mercurial
        VerifyInstalledGitLfs
        VerifyInstalledCmakeUbuntu
        VerifyInstalledCUDA
    fi
}

# Install host_setup.sh in itadmin home dir
function InstallDockerUbuntu {
    if [ $USER = 'root' ]
      then
        # Install Docker
        if [ ! -e /usr/bin/docker ]
          then
            apt -y install apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
            add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            apt update
            apt -y install docker-ce
        fi
        # Install Docker Compose
        if [ -e /usr/bin/docker-compose ]
          then
            apt purge docker-compose
        fi
        curl -L "https://github.com/docker/compose/releases/download/1.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod 755 /usr/local/bin/docker-compose
        # Add all users to docker group
        nscd --invalidate group
        for username in $(getent group users | cut -d : -f 4 | tr ',' ' ') jenkins demo
          do
            if id $username > /dev/null 2>&1
              then
                usermod -aG docker $username
            fi
        done
    fi
}

function InstallNVIDIADockerUbuntu {
    if [ $USER = 'root' ]
      then
        # Install Docker
        if [ ! -e /usr/bin/nvidia-docker ]
          then
            # Add the package repositories
            curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
            distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
            curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
            sudo apt-get update

            # Install nvidia-docker2 and reload the Docker daemon configuration
            apt-get install -y nvidia-docker2
            pkill -SIGHUP dockerd
        fi
        # Add all users to docker group
        nscd --invalidate group
        for username in $(getent group users | cut -d : -f 4 | tr ',' ' ') jenkins demo
          do
            if id $username > /dev/null 2>&1
              then
                usermod -aG docker $username
            fi
        done
    fi
}

function InstallX11DockerUbuntu {
    if [ $USER = 'root' ]
      then
        if ! dpkg -l kaptain > /dev/null 2>&1
          then
            VerifyInstalledPackagesUbuntu libqt4-qt3support libqt4-designer
            pushd $PWD
            cd /tmp
            curl -L -O https://github.com/mviereck/kaptain/raw/master/kaptain_0.73-1_amd64_ubuntu.deb
            popd
            dpkg -i /tmp/kaptain_0.73-1_amd64_ubuntu.deb
        fi
        if ! which x11docker > /dev/null
          then
            curl -L -o /tmp/x11docker-5.6.0.tar.gz https://github.com/mviereck/x11docker/archive/v5.6.0.tar.gz
            tar -xvf /tmp/x11docker-5.6.0.tar.gz -C /tmp 
            pushd $PWD
            cd /tmp/x11docker-5.6.0 && /tmp/x11docker-5.6.0/x11docker --install
            popd
        fi
    fi
}



# Install host_setup.sh in itadmin home dir
function InstallHostSetupScript {
    ## FIXME: If this is run from the local itadmin account it will 
    ##        overwrite itself which could corrupt the file
    if [ $USER = 'root' ]
      then
        if [ ! -e /var/host_setup ]
          then
            mkdir /var/host_setup
            chown 0:0 /var/host_setup
            chmod 755 /var/host_setup
        fi
        #if [ -e /var/host_setup/host_setup.sh ]
        #  then
        #    cp /var/host_setup/host_setup.sh /var/host_setup/host_setup.sh.bak
        #fi
        cp /jaunt/groups/it/bin/host_setup.sh /var/host_setup/host_setup.sh
        chown 0:0 /var/host_setup/host_setup.sh
        chmod 755 /var/host_setup/host_setup.sh
    else
        echo "Skipping host_setup.sh install due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

function InstallHostSetupLaunchdPlist {
    # FIXME:  This really should update the Plist file if it has changed,
    #         however it appears that launchctl prevents a agent's plist file 
    #         from being updated when that agent is running
    if [ $USER = 'root' ]
      then
        launch_agent_name="com.jauntvr.host_setup"
        launch_agent_path=/Library/LaunchDaemons/${launch_agent_name}.plist
        launchctl list $launch_agent_name &> /dev/null
        if [ $? != 0 ]
          then
            read -d '' -r plist_template << EndOfPList
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jauntvr.host_setup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>/jaunt/groups/it/bin/host_setup.sh</string>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/host_setup_out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/host_setup_err.log</string>
    <key>StartInterval</key>
    <integer>86400</integer>
</dict>
</plist>
EndOfPList
            result=$(eval echo "'$plist_template'")
            echo "${result}" > $launch_agent_path
            launchctl load $launch_agent_path
        fi
      # To unload, launchctl unload $launch_agent_path
      # or, launchctl unload /Library/LaunchDaemons/com.jauntvr.host_setup.plist
      else
        echo "Skipping launchd config for host_setup due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}


function InstallHostSetupCronJobLinux {
    if [ $USER = 'root' ]
      then
        if [ ! -e /etc/cron.d/host_setup ]
          then
            echo -e "SHELL=/bin/bash\nPATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\n\n0 6 * * * root /var/host_setup/host_setup.sh > /tmp/host_setup-out.log 2>&1" > /etc/cron.d/host_setup
        fi
      else
        echo "Skipping cron setup due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}



# Store Mac address and hostname in host db file
function RecordMacAddresses {
    hostname=`hostname -s`
    if [ `uname -s` = 'Darwin' ]
      then
        networksetup -listallhardwareports > /jaunt/groups/it/logs/hosts/$hostname-networksetup.log
        chmod a+w /jaunt/groups/it/logs/hosts/$hostname-networksetup.log
    fi
    ifconfig > /jaunt/groups/it/logs/hosts/$hostname-ifconfig.log
    chmod a+w /jaunt/groups/it/logs/hosts/$hostname-ifconfig.log
}

# Install FFmpeg
function InstallFFmpegUbuntu14 {
    if [ ! -e /usr/bin/ffmpeg ]
      then
        add-apt-repository -y ppa:mc3man/trusty-media
        apt-get update
        apt-get -y install ffmpeg
    fi
}

# Install Jaunt applications
function InstallJauntApplicationsDarwin {
    if [ $USER = 'root' ]
      then
        if [ ! -e /Applications/Jaunt ]
          then
            mkdir /Applications/Jaunt
        fi
        if [ ! -e /Applications/Jaunt/Dozer.app ] && [ ! -h /Applications/Jaunt/Dozer.app ]
          then
            ln -s /jaunt/apps/dozer/latest/Dozer.app /Applications/Jaunt/Dozer.app
        fi
        if [ ! -e /Applications/Jaunt/Jaunt\ Player.app ] && [ ! -h /Applications/Jaunt/Jaunt\ Player.app ]
          then
            ln -s /jaunt/apps/jaunt-player/latest/Jaunt\ Player.app /Applications/Jaunt/Jaunt\ Player.app
        fi
        if [ ! -e /Applications/RV64.app ] && [ ! -h /Applications/RV64.app ]
          then
            ln -s /jaunt/apps/rv/latest/RV64.app /Applications/RV64.app
        fi
      else
        echo "Skipping installation of application due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Install FileVault key
function InstallFileVaultKey {
    if [ $USER = 'root' ]
      then
        if [ ! -e /Library/Keychains/FileVaultMaster.keychain ]
          then
            cp /jaunt/groups/it/etc/FileVaultMaster.keychain /Library/Keychains
        fi
    fi
}

#~ # Install Jaunt applications
#~ function InstallJauntApplicationsCentOS {
    #~ if [ $USER = 'root' ]
      #~ then
        #~ if [ ! -L /usr/share/applications/Nuke9.0v4.desktop ]
          #~ then
            #~ ln -s /jaunt/apps/nuke/9.0v4jaunt/jaunt-resources/Nuke9.0v4.desktop /usr/share/applications/
        #~ fi
        #~ if [ ! -L /usr/share/applications/NukeAssist9.0v4.desktop ]
          #~ then
            #~ ln -s /jaunt/apps/nuke/9.0v4jaunt/jaunt-resources/NukeAssist9.0v4.desktop /usr/share/applications/
        #~ fi
        #~ if [ ! -L /usr/share/applications/NukePLE9.0v4.desktop ]
          #~ then
            #~ ln -s /jaunt/apps/nuke/9.0v4jaunt/jaunt-resources/NukePLE9.0v4.desktop /usr/share/applications/
        #~ fi
        #~ if [ ! -L /usr/share/applications/NukeStudio9.0v4.desktop ]
          #~ then
            #~ ln -s /jaunt/apps/nuke/9.0v4jaunt/jaunt-resources/NukeStudio9.0v4.desktop /usr/share/applications/
        #~ fi
        #~ if [ ! -L /usr/share/applications/NukeX9.0v4.desktop ]
          #~ then
            #~ ln -s /jaunt/apps/nuke/9.0v4jaunt/jaunt-resources/NukeX9.0v4.desktop /usr/share/applications/
        #~ fi
    #~ fi
#~ }

# Configure additional apt-get repositories
function InstallAptReposUbuntu {
    if [ $USER = 'root' ]
      then
        # No extra repos yet
        # Install additional packages for running jtools
        apt-get -y install libmysqlclient-dev libfreeimage3 python-numpy make libgoogle-glog-dev libarmadillo4 ocl-icd-libopencl1 nvidia-opencl-icd-346 
        # Not these: libcholmod2.1.2 libcxsparse3.1.2
        dpkg -i /jaunt/software/packages/linux/Canonical/pkgs/libarmadillo3_3.900.2+dfsg-1_amd64.deb
        tar xvfz /jaunt/software/packages/Jaunt/OpenCV_3.0rc1_linux.tgz -C /usr
        # Install additional packages for IT
        apt-get -y install gkrellm htop iftop jq ldap-utils screen awscli mhddfs
        # Install additional packages for Production Engineering
        apt-get -y install python-mysqldb mysql-client-core-5.5 openldap-clients
        # Install additional packages for software development
	sudo apt-get -y install git
        # Install additional packages for production
	sudo apt-get -y install tcsh zsh
      else
        echo "Skipping installation of package repos due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

        

# Configure additional RPM repositories
function InstallRPMReposCentOS {
    if [ $USER = 'root' ]
      then
        if [ ! -e /etc/yum.repos.d/elrepo.repo ]
          then
            # Install ElRepo repository
            rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
		 	rpm -Uvh http://www.elrepo.org/elrepo-release-6-5.el6.elrepo.noarch.rpm
#centos7 Fix for elrepo for centos 7 (AS)
	  yum --enablerepo install epel-release
		#	rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
#END centos7 Fix for elrepo for centos 7 (AS)
	    # TODO: Switch from ElRepo to AT RPMs?
            #rpm --import http://packages.atrpms.net/RPM-GPG-KEY.atrpms
            #echo "[atrpms]
#name=Fedora Cora $releasever - $basearch - ATrpms
#baseurl=http://dl.atrpms.net/el$releasever-$basearch/atrpms/stable
#gpgkey=http://ATrpms.net/RPM-GPG-KEY.atrpms
#gpgcheck=1" >> /etc/yum.repos.d/atrpms
            yum -y update
        fi
        # Install additional packages for jtools
        yum -y install blas atlas-sse3
        rpm -i /jaunt/software/packages/linux/CentOS/Fedora\ Project/*
        # Install additional packages for IT
        rpm -i /jaunt/software/packages/linux/CentOS/RepoForge/*
        rpm -i /jaunt/software/packages/linux/RHEL/EPEL/*
        rpm -i /jaunt/software/packages/linux/RHEL/EPEL/*
        yum -y install fuse-devel
        rpm -i /jaunt/software/packages/linux/RHEL/ftp.gwdg.de/*
        yum -y install screen
        # Install additional packages for Production Engineering
        yum -y install xorg-x11-apps gconf-editor python-argparse python-requests openldap-clients pyOpenSSL
        # Install additional packages for software development
        rpm -i /jaunt/software/packages/linux/CentOS/Dag\ Wieers/*
        yum -y install gcc-c++ git cmake
        # Install additional packages for Production
#        These lines install restkit
#        yum -y install python-webob
#        rpm -i /jaunt/software/packages/linux/CentOS/gwdg.de/*
        # install libXp for Maya
        yum -y install libXp
        yum -y install zsh vlc tcsh 
        yum -y install centos-release-SCL
        yum -y install python27
      else
        echo "Skipping installation of RPM repos due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Install NVIDIA Drivers when applicable
function InstallNVIDIADriverUbuntu {
    if [ $USER = 'root' ]
      then
        if lspci | grep -q NVIDIA 
          then
            if [ ! -e /proc/driver/nvidia ]
              then
                if [ "$(lsb_release -r -s | cut -d. -f1)" == "14" ]
                  then
                    # The following line is necessary for AWS hosts only
                    apt-get -y install linux-image-extra-virtual
                    dpkg -i /jaunt/software/packages/linux/NVIDIA/cuda-repo-ubuntu1404-7-5-local_7.5-18_amd64.deb
                    apt-get update
                    apt-get -y install cuda
                elif [ "$(lsb_release -r -s | cut -d. -f1)" == "16" ]
                  then
                    # To list available drivers:  ubuntu-drivers devices
                    # To install default drivers: ubuntu-drivers autoinstall
                    # Or installspecific package: apt install nvidia-driver-390
                    #ubuntu-drivers autoinstall
                    while fuser /var/lib/dpkg/status > /dev/null 2>&1
                      do
                        if [ -z $notified ]
                          then
                            echo -n "Check for unclicked dialog boxes!  Waiting for dpkg lock to be free."
                            notified=1
                        fi
                        echo -n "."
                        sleep 1
                    done
                    add-apt-repository -y ppa:graphics-drivers/ppa
                    apt-get update
                    apt -y install nvidia-384
                    apt -y install nvidia-415
                elif [ "$(lsb_release -r -s | cut -d. -f1)" == "18" ]
                  then
                    add-apt-repository -y ppa:graphics-drivers/ppa
                    apt-get update
                    apt -y install nvidia-driver-410
                fi
            fi
        fi
      else
        echo "Skipping installation of application due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Install NVIDIA Drivers when applicable
function InstallNVIDIADriverCentOS {
    if [ $USER = 'root' ]
      then
        lspci | grep NVIDIA >> /dev/null
        if [ $? = 0 ]
          then
            if [ ! -e /proc/driver/nvidia ]
              then
#                yum -y install nvidia-x11-drv  
#                line above commented out because latest 361.28 driver is broken 
				 yum -y install nvidia-x11-drv-352.79-1.el6.elrepo
                echo "NVIDIA Driver installed.  You will need to reboot to activate the driver."
            fi
        fi
      else
        echo "Skipping installation of application due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}


function registerRVHandler {
    if [ $USER = 'root' ]
      then
        if [ -e /jaunt/apps/rv/latest/bin/rv ]
          then
            if [ `uname -s` = 'Darwin' ]
              then
                /jaunt/apps/rv/latest/bin/rv -registerHandler
              else
                /jaunt/apps/rv/latest/bin/rv.install_handler
            fi
        fi
    fi
}

function InstallGoogleChromeUbuntu {
    if [ $USER = 'root' ]
      then
        if [ ! -e /usr/bin/google-chrome ]
          then
            # Install Google Chrome
            if [ ! -e /etc/apt/sources.list.d/google.list ]
              then
                wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add - 
                sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list'
            fi
            VerifyInstalledPackagesUbuntu google-chrome-stable
        fi
    fi
}

# Install Google Chrome.  Chome on RHEL/CentOS is unsupported by Google
# To update Google Chrome, run "yum update google-chrome-stable" or
# simply re-run this script with "./install_chrome.sh".
# To uninstall Google Chrome and its dependencies added by this script,
# run "yum remove google-chrome-stable chrome-deps-stable" or 
# "./install_chrome.sh -u".
function InstallGoogleChromeCentOS {
    if [ $USER = 'root' ]
      then
        rpm -q google-chrome-stable >/dev/null 2>&1
        if [ $? != 0 ]
          then
            # Get new versions of this script from:
            # wget http://chrome.richardlloyd.org.uk/install_chrome.sh
            # Maybe this script should just do that?
            /jaunt/software/packages/linux/Richard\ Lloyd/install_chrome.sh -f
        fi
      else
        echo "Skipping installation of Chrome due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

# Disable SELinux 
function DisableSELinuxCentOS {
    if [ $USER = 'root' ]
      then
        grep "SELINUX=disabled" /etc/selinux/config >/dev/null 2>&1
        if [ $? != 0 ]
          then
            sed 's/^SELINUX=enforcing$/SELINUX=disabled/' </etc/selinux/config >/tmp/config
            chown root:root /tmp/config
            chmod 644 /tmp/config
            mv /tmp/config /etc/selinux/config
            echo "SELinux disabled.  You will need to reboot to activate the change."
        fi
      else
        echo "Skipping disabling SELinux due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

function ConfigureDeadlineLinux {
    if [ $USER = 'root' ]
      then
        chmod o+x /root
        #~ if [ -e /usr/local/share/applications/deadlinemonitor8.desktop ]
          #~ then
            #~ sed "s/Exec=\/opt\/Thinkbox\/Deadline8\/bin\/deadlinelauncher -monitor/Exec=\/opt\/Thinkbox\/Deadline8\/bin\/deadlinemonitor/" < /usr/local/share/applications/deadlinemonitor8.desktop > /tmp/deadlinemonitor8.desktop
            #~ chown root:root /tmp/deadlinemonitor8.desktop
            #~ chmod 755 /tmp/deadlinemonitor8.desktop
            # mv /tmp/deadlinemonitor7.desktop /usr/local/share/applications/deadlinemonitor8.desktop
        sed "s/\*          soft    nproc     1024/*          soft    nproc     unlimited/" < /etc/security/limits.d/90-nproc.conf > /tmp/90-nproc.conf
        chown root:root /tmp/90-nproc.conf
        chmod 644 /tmp/90-nproc.conf
        mv /tmp/90-nproc.conf /etc/security/limits.d/90-nproc.conf
        # fi
    else
        echo "Skipping configuration of permissions for Deadline due to lack "
        echo "of privileges.  Re-run this script as root to run this module."
fi
}

# Fixes DNS errors in Ubuntu 18.04
function ReconfigureSystemdUbuntu {
    if [ $USER = 'root' ]
      then
        if [ "$(lsb_release -r -s | cut -d. -f1)" == "18" ]
          then
            dpkg-reconfigure systemd
        fi
    fi
}

# Configure an AWS Render Node.  Locks host to this setting when run once.
function DeveloperLaptopHostDarwin() {
    if [ ! -e /etc/host_class ]
      then
        echo "DeveloperLaptopHostDarwin" > /etc/host_class
    fi
      execute CreateITAdminUserDarwin "Configuring the itadmin user"
      execute ConfigureGlobalUmaskDarwin "Configuring global umask settings"
      execute ConfigureSudoersDarwin "Setting up sudoers file"
      execute InstallItadminPasswordlessSSHKeyFileDarwin "Installing SSH Key"
      execute ConfigureItadminProfile "Setting up itadmin user profile"
      execute EnableRemoteLoginDarwin "Enabling remote ssh connections"
      execute ConfigureLDAPDarwin "Configuring LDAP"
      execute ConfigureAutoMasterDarwin "Configuring Automounts"
      execute AutomountMapReloadDarwin "Reloading Automount Maps"
      #execute RemoveDeadAutomountDirectories "Cleaning up Automount Points"
      #execute CreateJauntAppsSymlinkDarwin "Creating /jaunt/apps symlink"
      execute InstallHostSetupScript "Installing host_setup.sh locally"
      execute InstallHostSetupLaunchdPlist "Configuring host_setup in launchd"
      execute RecordMacAddresses "Recording networking information"
#      execute InstallFileVaultKey "Putting FileVault key in place"
      execute SyncSharedAppsLiteDarwin "Copying apps to /jaunt/apps"
      execute InstallJauntApplicationsDarwin "Installing Jaunt applications"
}

# Configure Medusa render service.
function MedusaRender() {
    if [ $USER = 'root' ]
      then
        if [ ! -e /home/web ]
          then
            cd /home && ln -s /jaunt/legacy/data/web
        fi
        if [ ! -e /home/nightly ]
          then
            cd /home && ln -s /jaunt/legacy/data/nightly
        fi
        if [ ! -e /usr/local/bin/ffmpg ]
          then
            cd /usr/local/bin && ln -s /jaunt/apps/ffmpeg/latest/bin/ffmpeg
        fi
        apt-get install -y python-pip python-dev python-numpy
        cd /jaunt/legacy/data/nightly/pancam/medusa && pip install -r /jaunt/legacy/data/nightly/pancam/medusa/requirements.txt
        echo "You can ignore the "SyntaxError: invalid syntax" message above."
        echo "Now manually copy /etc/medusa/config.json to this machine."
      else
        echo "Skipping Medusa render node setup due to lack of privileges."
        echo "Re-run this script as root to run this module."
    fi
}

function WebServerHostUbuntu() {
    if [ ! -e /etc/host_class ]
      then
        echo "WebServerHostUbuntu" > /etc/host_class
    fi
      execute RenameGroupsUbuntu "Updating groups file"
      execute ConfigureGlobalUmaskLinux "Configuring global umask settings"
      execute ConfigureSudoersLinux "Setting up sudoers file"
      execute CreateITAdminUserLinux "Configuring the itadmin user"
      execute InstallItadminPasswordlessSSHKeyFileLinux "Installing SSH Key"
      execute ConfigureItadminProfile "Setting up itadmin user profile"
      execute EnableRemoteLoginUbuntu "Setting up ssh server"
      execute ConfigureAutomountLDAPUbuntu "Configuring LDAP"
      execute ConfigureAutomountUbuntu "Configuring Automounts"
      execute InstallHostSetupScript "Installing host_setup.sh locally"
      execute RecordMacAddresses "Recording networking information"
      execute InstallHostSetupCronJobLinux "Setting up cron run of host_setup"
}

function WebServerHostCentOS() {
    if [ ! -e /etc/host_class ]
      then
        echo "WebServerHostUbuntu" > /etc/host_class
    fi
      execute ActivateEthernetInterfacesCentOS "Activating Ethernet Interfaces"
      execute RenameGroupsCentos "Updating groups file"
      execute ConfigureGlobalUmaskLinux "Configuring global umask settings"
      execute ConfigureSudoersLinux "Setting up sudoers file" # Testme
      execute CreateITAdminUserLinux "Configuring the itadmin user"
      execute InstallItadminPasswordlessSSHKeyFileLinux "Installing SSH Key"
      execute ConfigureItadminProfile "Setting up itadmin user profile"
      execute ConfigureLDAPDarwin "Configuring LDAP"
      execute AutomountConfigureCentOS "Configuring Automounts"
      execute ConfigureDelayedAutomountStartCentOS "Setting Autofs for delayed start"
      execute AutomountMapReloadCentOS "Reloading Automount Maps"
#      execute InstallRPMReposCentOS "Setting up RPM repositories"
#      execute InstallGoogleChromeCentOS "Installing Google Chrome"
      execute DisableSELinuxCentOS "Turning off SELinux"
      execute InstallHostSetupScript "Installing host_setup.sh locally"
      execute InstallHostSetupCronJobLinux "Setting up cron run of host_setup"
      execute RecordMacAddresses "Recording networking information"
}

# Configure an AWS Render Node.  Locks host to this setting when run once.
function AWSMedusaRenderHostUbuntu() {
    if [ ! -e /etc/host_class ]
      then
        echo "AWSMedusaRenderHostUbuntu" > /etc/host_class
    fi
      execute RenameGroupsUbuntu "Updating groups file"
      execute ConfigureGlobalUmaskLinux "Configuring global umask settings"
      execute ConfigureSudoersLinux "Setting up sudoers file"
      execute ConfigureAutomountLDAPUbuntu "Configuring LDAP"
      execute ConfigureAutomountUbuntu "Configuring Automounts"
      execute AutomountMapReloadUbuntu "Reloading Automount Maps"
      execute InstallAptReposUbuntu "Setting up Apt repositories"
      execute InstallNVIDIADriverUbuntu "Checking GPU drivers"
      execute InstallHostSetupScript "Installing host_setup.sh locally"
      execute InstallHostSetupCronJobLinux "Setting up cron run of host_setup"
      execute MedusaRender
}

# Configure an Ubuntu box to be used by the hardware team to compile code targeting the A9SE
function HardwareA9SEBuildUbuntu() {
      execute RenameGroupsUbuntu "Updating groups file"
      execute ConfigureGlobalUmaskLinux "Configuring global umask settings"
      execute ConfigureSudoersLinux "Setting up sudoers file"
      execute EnableRemoteLoginUbuntu "Setting up ssh server"
      execute ConfigureAutomountLDAPUbuntu "Configuring LDAP"
      execute ConfigureAutomountUbuntu "Configuring Automounts"
      execute RemoveDeadProjectDirectories "Cleaning up Project Automount Points"
      execute InstallAptReposUbuntu "Setting up Apt repositories"
      execute InstallHostSetupScript "Installing host_setup.sh locally"
      execute RecordMacAddresses "Recording networking information"
      execute InstallHostSetupCronJobLinux "Setting up cron run of host_setup"
      execute ConfigureS3FSUbuntu "Setting up S3FS Mounts"
}

# Configure an AWS Nuke Node.  Locks host to this setting when run once.
function AWSNukeRenderHostRHEL() {
    if [ ! -e /etc/host_class ]
      then
        echo "AWSMedusaRenderHostRHEL" > /etc/host_class
    fi
      echo "Executing RHEL AWS Setup"
      yum groupinstall "Server with GUI"
      if [ `grep ldap /etc/hosts` = "" ]
        then
          echo "
10.135.1.8  rlm rlm.corp.jauntvr.com groovy groovy.corp.jauntvr.com
10.135.1.9  nas1 nas1.corp.jauntvr.com
10.135.1.10 nas2 nas2.corp.jauntvr.com
10.135.1.14 nas3 nas3.corp.jauntvr.com
10.135.1.20 ldap ldap.corp.jauntvr.com
10.135.1.30 infra01 infra01.corp.jauntvr.com
10.135.130.134 deadlinelic deadinelic.corp.jauntvr.com
" >> /etc/hosts
      fi
      execute RenameGroupsCentos "Updating groups file"
      execute ConfigureGlobalUmaskLinux "Configuring global umask settings"
      execute ConfigureSudoersLinux "Setting up sudoers file" # Testme
      execute CreateITAdminUserLinux "Configuring the itadmin user"
      execute InstallItadminPasswordlessSSHKeyFileLinux "Installing SSH Key"
      execute ConfigureItadminProfile "Setting up itadmin user profile"
      execute LDAPConfigureRHEL "Configuring LDAP"
      execute AutomountConfigureCentOS "Configuring Automounts"
      yum install autofs
#      execute ConfigureDelayedAutomountStartCentOS "Setting Autofs for delayed start"
#      execute AutomountMapReloadCentOS "Reloading Automount Maps"
#      #execute RemoveDeadAutomountDirectories "Cleaning up Automount Points"
#      #execute CreateJauntAppsSymlinkLinux "Creating /jaunt/apps symlink"
#      execute InstallRPMReposCentOS "Setting up RPM repositories"
#      execute InstallNVIDIADriverCentOS "Checking GPU drivers"
      execute InstallGoogleChromeCentOS "Installing Google Chrome"
#      execute DisableSELinuxCentOS "Turning off SELinux"
#      execute ConfigureDeadlineLinux "Setting permissions for Deadline"
#      execute InstallHostSetupScript "Installing host_setup.sh locally"
#      execute InstallHostSetupCronJobLinux "Setting up cron run of host_setup"
#      execute RecordMacAddresses "Recording networking information"
#      execute SyncSharedAppsLinux "Copying apps to /jaunt/apps"
#      execute InstallJauntApplicationsCentOS "Installing Jaunt applications"
}

function execute {
  echo "======Running $1 ($2)======"
  $1
  echo "Done"
}

function RnDUbuntu {
      echo "Executing Ubuntu Setup"
      execute RenameGroupsUbuntu "Updating groups file"
      execute ConfigureGlobalUmaskLinux "Configuring global umask settings"
      execute ConfigureSudoersLinux "Setting up sudoers file"
      execute CreateITAdminUserLinux "Configuring the itadmin user"
      execute InstallItadminPasswordlessSSHKeyFileLinux "Installing SSH Key"
      execute ConfigureItadminProfile "Setting up itadmin user profile"
      execute EnableGreeterManualUsernameLogin "Enabling console login for all users"
      execute EnableRemoteLoginUbuntu "Setting up ssh server"
      execute ConfigureAutomountLDAPUbuntu "Configuring LDAP"
      execute ConfigureAutomountUbuntu "Configuring Automounts"
      execute RemoveDeadProjectDirectories "Cleaning up Project Automount Points"
#      execute InstallAptReposUbuntu16 "Setting up Apt repositories"
#      execute InstallFFmpegUbuntu "Installing FFmpeg"
#      execute InstallNVIDIADriverUbuntu "Checking GPU drivers"
      execute InstallHostSetupScript "Installing host_setup.sh locally"
      execute RecordMacAddresses "Recording networking information"
      execute InstallHostSetupCronJobLinux "Setting up cron run of host_setup"
#      execute ConfigureS3FSUbuntu "Setting up S3FS Mounts"
      execute ConfigureJToolsDependencies "Installing OpenCV and Ceres libraries"
#      execute SyncSharedAppsLinux "Copying apps to /jaunt/apps"
      execute registerRVHandler "Registering RV Handler"
}

function CaptureStation {
      execute InstallCaptureDependenciesUbuntu "Installing Capture Station Dependencies"
      execute InstallVolcapBuildDependencies "Installing Volcap Build Dependencies"
      execute InstallRealSenseDriversUbuntu "Installing Intel RealSense Drivers"
      execute InstallSynergyUbuntu "Installing Synergy for Dave Cazz"
      execute InstallNvtop "Installing NVIDIA Monitor"
      execute InstallUsbTop "Installing USB Monitor"
      execute InstallAnyDeskUbuntu "Installing AnyDesk Remote Desktop"
}

function TrimStation {
      execute InstallCaptureDependenciesUbuntu "Installing Capture Station Dependencies"
      execute InstallVolcapBuildDependencies "Installing Volcap Build Dependencies"
      execute InstallSynergyUbuntu "Installing Synergy for Dave Cazz"
      execute InstallNvtop "Installing NVIDIA Monitor"
      execute InstallUsbTop "Installing USB Monitor"
      execute InstallAnyDeskUbuntu "Installing AnyDesk Remote Desktop"
}

function UpliftStation {
      execute InstallTronBuildDependencies "Installing Tron build dependencies"
      execute InstallNvtop "Installing NVIDIA Monitor"
      execute InstallUsbTop "Installing USB Monitor"
}

function LinkStation {
      execute InstallLinkDependencies "Installing Link Dependencies"
}

function GenericStation {
      UpliftStation
      TrimStation
      LinkStation
}

function executeAll {
 
  if [ `uname -s` = 'Darwin' ]
    then
      echo "Executing Darwin Setup"
      execute CreateITAdminUserDarwin "Configuring the itadmin user"
      execute ConfigureGlobalUmaskDarwin "Configuring global umask settings"
      #execute ConfigureSudoersDarwin "Setting up sudoers file"
      execute InstallItadminPasswordlessSSHKeyFileDarwin "Installing SSH Key"
      #execute ConfigureItadminProfile "Setting up itadmin user profile"
      execute EnableRemoteLoginDarwin "Enabling remote ssh connections"
      execute ConfigureLDAPDarwin "Configuring LDAP"
      execute ConfigureAutoMasterDarwin "Configuring Automounts"
      execute AutomountMapReloadDarwin "Reloading Automount Maps"
      #execute RemoveDeadAutomountDirectories "Cleaning up Automount Points"
      #execute RemoveDeadProjectDirectories "Cleaning up Project Automount Points"
      #execute CreateJauntAppsSymlinkDarwin "Creating /jaunt/apps symlink"
      execute InstallHostSetupScript "Installing host_setup.sh locally"
      execute InstallHostSetupLaunchdPlist "Configuring host_setup in launchd"
      execute RecordMacAddresses "Recording networking information"
      #execute SyncSharedAppsDarwin "Copying apps to /jaunt/apps"
#      execute InstallFileVaultKey "Putting FileVault key in place"
      #execute InstallJauntApplicationsDarwin "Installing Jaunt applications"
      #execute registerRVHandler "Registering RV Handler"
  

  elif [ `lsb_release -i | awk '{print $3}'` = 'Ubuntu' ]
    then
      echo "Executing Ubuntu Setup"
      execute RenameGroupsUbuntu "Updating groups file"
      execute ConfigureGlobalUmaskLinux "Configuring global umask settings"
      execute ConfigureSudoersLinux "Setting up sudoers file"
      execute CreateITAdminUserLinux "Configuring the itadmin user"
      execute InstallItadminPasswordlessSSHKeyFileLinux "Installing SSH Key"
      execute ConfigureItadminProfile "Setting up itadmin user profile"
      execute EnableRemoteLoginUbuntu "Setting up ssh server"
      execute ConfigureDefaultEditorUbuntu "Configuring vim as default editor"
      execute ConfigureAutomountLDAPUbuntu "Configuring Local LDAP"
      execute ConfigureFoxpassUbuntu "Configuring Cloud LDAP"
      execute InstallNVIDIADriverUbuntu "Installing NVIDIA Driver"
#      execute InstallAptReposUbuntu "Setting up Apt repositories"
#      execute InstallFFmpegUbuntu "Installing FFmpeg"
      execute InstallHostSetupScript "Installing host_setup.sh locally"
      execute RecordMacAddresses "Recording networking information"
      execute InstallHostSetupCronJobLinux "Setting up cron run of host_setup"
#      execute ConfigureS3FSUbuntu "Setting up S3FS Mounts"
#      execute ConfigureJToolsDependencies "Installing OpenCV and Ceres libraries"
#      execute SyncSharedAppsLinux "Copying apps to /jaunt/apps"
#      execute registerRVHandler "Registering RV Handler"
      execute InstallDockerUbuntu "Installing Docker"
      execute InstallNVIDIADockerUbuntu "Installing NVIDIA-Docker"
      execute InstallX11DockerUbuntu "Installing X11-Docker"
      execute ReconfigureSystemdUbuntu "Reconfiguring Systemd"
      execute InstallAdminPackagesUbuntu "Installing Administation Packages"
      execute ConfigureGreeterManualLoginUbuntu "Congiuring Manual Greeter"
      execute InstallGoogleChromeUbuntu "Installing Google Chrome"
      execute DisableUpdatePromptUbuntu "Disabling OS Version Upgrade Prompt"


 elif [ `lsb_release -i | awk '{print $3}'` = 'CentOS' ]
    then
      echo "Executing CentOS Setup"
	execute InstallRedhatLsbCore "Installing Redhat Core LSB"
	execute InstallAutoFSandEnable "Installing autofs and enabling"
	execute InstallNFS-Utils "Installing nfs-utils"
      execute ActivateEthernetInterfacesCentOS "Activating Ethernet Interfaces"
      execute RenameGroupsCentos "Updating groups file"
      execute ConfigureGlobalUmaskLinux "Configuring global umask settings"
      execute ConfigureSudoersLinux "Setting up sudoers file" # Testme
      execute CreateITAdminUserLinux "Configuring the itadmin user"
      execute InstallItadminPasswordlessSSHKeyFileLinux "Installing SSH Key"
      execute ConfigureItadminProfile "Setting up itadmin user profile"
      execute LDAPConfigureCentOS "Configuring LDAP"
      execute AutomountConfigureCentOS "Configuring Automounts"
      execute ConfigureDelayedAutomountStartCentOS "Setting Autofs for delayed start"
      execute AutomountMapReloadCentOS "Reloading Automount Maps"
      #execute RemoveDeadAutomountDirectories "Cleaning up Automount Points"
      execute RemoveDeadProjectDirectories "Cleaning up Project Automount Points"
      #execute CreateJauntAppsSymlinkLinux "Creating /jaunt/apps symlink"
      execute InstallRPMReposCentOS "Setting up RPM repositories"
      #execute InstallNVIDIADriverCentOS "Checking GPU drivers"
      execute InstallGoogleChromeCentOS "Installing Google Chrome"
      execute DisableSELinuxCentOS "Turning off SELinux"
      execute ConfigureDeadlineLinux "Setting permissions for Deadline"
      execute InstallHostSetupScript "Installing host_setup.sh locally"
      execute InstallHostSetupCronJobLinux "Setting up cron run of host_setup"
      execute RecordMacAddresses "Recording networking information"
      execute SyncSharedAppsLinux "Copying apps to /jaunt/apps"
      # execute InstallJauntApplicationsCentOS "Installing Jaunt applications"
      execute registerRVHandler "Registering RV Handler"
      execute InstallZsh "Installing Zsh"

  else
    echo "Unable to determine plaform type."
  fi
}


# Main
# Run the shared version if not already and if possible
pushd `dirname $0` > /dev/null
SCRIPTPATH=`pwd`
popd > /dev/null
#if [[ $SCRIPTPATH != "/jaunt/groups/it/bin" ]]
#  then
#    if [ -e /jaunt/groups/it/bin/host_setup.sh ]
#      then
#        echo "Switching to /jaunt/groups/it/bin/host_setup.sh"
#        /jaunt/groups/it/bin/host_setup.sh $@
#        exit 0
#    fi
#fi
if [ -z "$USER" ]
  then
    USER=`id -nu`
fi
if [[ $USER != 'root' && $USER != 'itadmin' &&
      $USER != 'web' && $USER != 'medusa' ]]
  then
    echo "This script must be run by root or by the \"itadmin\" user."
    echo "Currently running as $USER"
    echo "Currently running as $UID"
    exit 1
fi
# If the user specified a single function, execute that one only.
if [ $1 ]
  then
    execute $1
    exit
else
    if [ -e /etc/host_class ]
      then
        echo "Configuring host as `cat /etc/host_class`"
        execute `cat /etc/host_class`
    else
        executeAll
    fi
fi
