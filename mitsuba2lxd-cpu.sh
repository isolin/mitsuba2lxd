#!/bin/bash

echo "MITSUBA 2 in LXD script, v 1.0"
echo ""

###########################
# Check LXD installation
###########################

LxcLocation=$(which lxc)
if ! [[ $LxcLocation == *"snap"* ]]; then
	if [ -z $LxcLocation ]; then
    sudo apt-get update
		sudo apt-get install snapd -y
		sudo snap install lxd
	else
	  ContainersCount=$(lxc list | grep "RUNNING\|STOPPED" | wc -l)
		if [[ $ContainersCount == 0 ]]; then
			sudo apt-get update
			sudo apt-get purge lxd -y
			sudo apt-get install snapd -y
			sudo snap install lxd
		else
			echo "This script requires the LXD to be installed via snap to ensure it is always up to date. It seems you have some containers in your DEB/PPA installation. Please install the LXD snap package and migrate them manually."
			exit
		fi
	fi
fi

###########################
# Container name
###########################

read -p "New container name [mitsuba2]: " name
name=${name:-mitsuba2}

ContainerExists=$(lxc list | grep $name | wc -l)
if [ $ContainerExists == 1 ]; then
	read -p "A container with the same name already exists. Delete and recreate it [Y/n]? " OverwriteContainer
	OverwriteContainer=${OverwriteContainer:-Y}
	case "$OverwriteContainer" in
		[Nn]*)
			echo "Please try again with a different container name."
			exit ;;
		[Yy]*)
			echo "Ok."
			lxc stop $name
			lxc delete $name ;;
		*)
			echo "Invalid option, aborting.";;
	esac
fi

###########################
# Shared folder name
###########################

read -p "Path to the folder the host will share with the container [~]: " shared
shared=${shared:-~}
if ! [[ "$shared" = // ]]; then
	shared=$(pwd)/$shared
fi
echo "Shared folder selected: $shared"

if ! [ -d "$shared" ]; then
	echo "Please make sure that the shared folder exists and try again. "
	exit
fi

###########################
# Check for a custom Mitsuba config file
###########################

ConfigFile=$shared/Setup/mitsuba.conf
if ! [ -f "$ConfigFile" ]; then
	read -p "Use the default mitsuba config file (CPU only) [Y/n]? " CustomConfig
	CustomConfig=${CustomConfig:-Y}
	case "$CustomConfig" in
		[Nn]*)
			echo "Please make sure to save the mitsuba config file to $shared/Setup/mitsuba.conf and try again."
			exit ;;
		[Yy]*)
			echo "Ok." ;;
		*)
			echo "Invalid option, aborting.";;
	esac
else
	echo "Using the custom mitsuba.conf provided in $shared/Setup/mitsuba.conf."
fi


###########################
# CONTAINER SETUP at the host
###########################

lxc launch ubuntu-minimal:focal $name
# Wait for the container to update so that it does not interfere with the next step
while [ $(ps aux | grep -i apt | wc -l) -gt 1 ] && [ $UpdateRetry -le $MaxUpdates ]; do
	echo "Waiting for the container to finish updating after launch ..."
	sleep 9
done
# this will make the shared folder accessible from inside of the container as well
lxc config device add $name Shared disk source=$shared path=/home/ubuntu/Shared

###########################
# CONTAINER SETUP internal
###########################

# basic Mitsuba installation requirements and a few other handy packages
read -r -d '' BasicSetup << EOM
	sudo apt-get update;
	sudo apt-get -y install apt-utils git;
	sudo apt-get -y install clang-9 libc++-9-dev libc++abi-9-dev cmake ninja-build libz-dev libpng-dev libjpeg-dev libxrandr-dev libxinerama-dev libxcursor-dev python3-dev python3-distutils python3-setuptools;
EOM

# skipping packages necessary for HTML documentation

lxc exec $name -- /bin/bash -c "$BasicSetup"

# Checkout the repository and copy the configuration file
read -r -d '' GitClone << EOM
	git clone --recursive https://github.com/mitsuba-renderer/mitsuba2;
	if [ -f "Shared/Setup/mitsuba.conf" ]; then
		cp Shared/Setup/mitsuba.conf mitsuba2/mitsuba.conf;
	else
		cp mitsuba2/resources/mitsuba.conf.template mitsuba2/mitsuba.conf;
	fi;
EOM

# continue with the Mitsuba installation
read -r -d '' MitsubaBuild << EOM
	mkdir mitsuba2/build;
	export CC=clang-9;
	export CXX=clang++-9;
	cd mitsuba2/build;
	cmake -GNinja ..
	ninja;

	echo 'source ~/mitsuba2/setpath.sh' >>~/.profile;
	sudo apt-get -y autoremove;
EOM

lxc exec $name -- sudo --login --user ubuntu /bin/bash -c "$GitClone $MitsubaBuild"
