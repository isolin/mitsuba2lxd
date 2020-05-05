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
# Check for OptiX
###########################

OptiXFile=$shared/Setup/NVIDIA-OptiX-SDK-6.5.0-linux64.sh
if ! [ -f "$OptiXFile" ]; then
	echo "Please make sure to save NVIDIA-OptiX-SDK-6.5.0-linux64.sh to $shared/Setup and try again."
	exit
else
	echo "OptiX found."
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
# Prepare a GPU profile
###########################
d=$DISPLAY
searchstring=":"
rest=${d#*$searchstring}
pos=$(( ${#t} - ${#rest} - ${#searchstring} + 1 ))
disp=$(echo "$d" | head -c $pos | tail -c 1)

read -r -d '' MitsubaProfile << EOM
config:
  environment.DISPLAY: :0
  environment.PULSE_SERVER: unix:/home/ubuntu/pulse-native
  nvidia.driver.capabilities: all
  nvidia.runtime: "true"
  user.user-data: |
    #cloud-config
    runcmd:
      - 'sed -i "s/; enable-shm = yes/enable-shm = no/g" /etc/pulse/client.conf'
    packages:
      - x11-apps
      - mesa-utils
      - pulseaudio
description: GUI LXD profile
devices:
  PASocket1:
    bind: container
    connect: unix:/run/user/1000/pulse/native
    listen: unix:/home/ubuntu/pulse-native
    security.gid: "1000"
    security.uid: "1000"
    uid: "1000"
    gid: "1000"
    mode: "0777"
    type: proxy
  X0:
    bind: container
    connect: unix:@/tmp/.X11-unix/X$disp
    listen: unix:@/tmp/.X11-unix/X0
    security.gid: "1000"
    security.uid: "1000"
    type: proxy
  mygpu:
    type: gpu
name: x11
used_by: []
EOM

# add x11 profile enabling GPU access
ProfileExists=$(lxc profile list | grep mitsuba2 | wc -l)
if ! [[ $ProfileExists == 1 ]]; then
	lxc profile create mitsuba2
fi
echo "$MitsubaProfile" | lxc profile edit mitsuba2

###########################
# CONTAINER SETUP at the host
###########################

lxc launch ubuntu-minimal:focal $name --profile default --profile mitsuba2
# this will make the shared folder accessible from inside of the container as well
lxc config device add $name Shared disk source=$shared path=/home/ubuntu/Shared
# Wait for the container to update so that it does not interfere with the next step
UpdateRetry=1
MaxUpdates=10
while [ $(ps aux | grep -i apt | wc -l) -gt 1 ] && [ $UpdateRetry -le $MaxUpdates ]; do
	echo "Waiting for the container to finish updating after launch (Retry $UpdateRetry/$MaxUpdates)"
	UpdateRetry=$UpdateRetry + 1
	sleep 12
done

if [ $UpdateRetry -gt $MaxUpdates ]; then
	echo "Maxiumum number of update retries reached. Please try again, possibly setting a higher count of MaxUpdates."
	exit
fi

###########################
# CONTAINER SETUP internal
###########################

# basic Mitsuba installation requirement
lxc exec $name -- sudo apt-get update
lxc exec $name -- sudo /bin/sh -c "DEBIAN_FRONTEND=noninteractive apt-get install keyboard-configuration apt-utils"
lxc exec $name -- sudo apt-get -y install clang-9 libc++-9-dev libc++abi-9-dev cmake ninja-build libz-dev libpng-dev libjpeg-dev libxrandr-dev libxinerama-dev libxcursor-dev python3-dev python3-distutils python3-setuptools 
# some addional packages you will need
lxc exec $name -- sudo /bin/sh -c "DEBIAN_FRONTEND=noninteractive apt-get -y install git software-properties-common gcc-8 g++-8 python3-sphinx python3-pip"
# it looks like cmake of mitsuba needs pytest as well
lxc exec $name -- sudo --login --user ubuntu sudo /usr/bin/python3.8 -m pip install pytest pytest-xdist

# skipping packages necessary for HTML documentation

# IMPORTANT unbind the graphics driver
lxc stop $name
lxc config set $name nvidia.runtime false
lxc start $name
# Wait for the container to update so that it does not interfere with the next step
UpdateRetry=1
MaxUpdates=10
while [ $(ps aux | grep -i apt | wc -l) -gt 1 ] && [ $UpdateRetry -le $MaxUpdates ]; do
	echo "Waiting for the container to finish updating before CUDA installation (Retry $UpdateRetry/$MaxUpdates)"
	UpdateRetry=$UpdateRetry + 1
	sleep 12
done
sleep 9

# standard CUDA installation
#There is no 20.04 directory yet
lxc exec $name -- wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/cuda-ubuntu1804.pin
lxc exec $name -- sudo mv cuda-ubuntu1804.pin /etc/apt/preferences.d/cuda-repository-pin-600
lxc exec $name -- sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub
lxc exec $name -- sudo add-apt-repository "deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/ /"
lxc exec $name -- sudo apt-get update
lxc exec $name -- sudo apt-get install cuda -y
lxc exec $name -- sudo apt-get autoremove -y

# IMPORTANT bind the graphics driver again
lxc stop $name
lxc config set $name nvidia.runtime true
lxc start $name
# Wait for the container to update so that it does not interfere with the next step
UpdateRetry=1
MaxUpdates=10
while [ $(ps aux | grep -i apt | wc -l) -gt 1 ] && [ $UpdateRetry -le $MaxUpdates ]; do
	echo "Waiting for the container to finish updating after CUDA installation (Retry $UpdateRetry/$MaxUpdates)"
	UpdateRetry=$UpdateRetry + 1
	sleep 12
done

# OptiX installation
lxc exec $name -- sudo --login --user ubuntu cp Shared/Setup/NVIDIA-OptiX-SDK-6.5.0-linux64.sh NVIDIA-OptiX-SDK-6.5.0-linux64.sh
lxc exec $name -- sudo --login --user ubuntu chmod +x ./NVIDIA-OptiX-SDK-6.5.0-linux64.sh
lxc exec $name -- sudo --login --user ubuntu /bin/sh -c "./NVIDIA-OptiX-SDK-6.5.0-linux64.sh --skip-license --include-subdir"

# clone the Mitsuba repo
lxc exec $name -- sudo --login --user ubuntu git clone --recursive https://github.com/mitsuba-renderer/mitsuba2

# select the variants
if [ -f "$ConfigFile" ]; then
	lxc exec $name -- sudo --login --user ubuntu cp $ConfigFile mitsuba2/mitsuba.conf
else
	lxc exec $name -- sudo --login --user ubuntu cp mitsuba2/resources/mitsuba.conf.template mitsuba2/mitsuba.conf
fi

# IMPORTANT prepare GCC for CUDA
lxc exec $name -- sudo --login --user ubuntu sudo ln -s /usr/bin/gcc-8 /usr/local/cuda/bin/gcc
lxc exec $name -- sudo --login --user ubuntu sudo ln -s /usr/bin/g++-8 /usr/local/cuda/bin/g++

# continue with the Mitsuba installation
lxc exec $name -- sudo --login --user ubuntu mkdir mitsuba2/build
lxc exec $name -- sudo --login --user ubuntu /bin/sh -c "export CC=clang-9 && CXX=clang++-9 && CUDACXX=/usr/local/cuda/bin/nvcc && cd mitsuba2/build && cmake -GNinja .. -DMTS_OPTIX_PATH=/home/ubuntu/NVIDIA-OptiX-SDK-6.5.0-linux64"
lxc exec $name -- sudo --login --user ubuntu /bin/sh -c "cd mitsuba2/build && ninja"