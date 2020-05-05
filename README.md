# mitsuba2lxd
Launch an [LXD](https://linuxcontainers.org/) container with [Mitsuba2](https://github.com/mitsuba-renderer/mitsuba2) inside

## Introduction
This script checks your LXD installation and launches a new [Ubuntu Minimal 20.04 Focal Fossa](https://cloud-images.ubuntu.com/minimal/releases/focal/release/) container.

Inside of the container it installs all necessary packages including [CUDA](https://developer.nvidia.com/cuda-downloads) 10.2, so make sure to have a compatible GPU and drivers installed on the host machine.

This script is designed for Ubuntu/Debian. If you're interested to make it work in other distros, feel free to submit a pull request.

## Preparation
1. If you have used a deb/ppa installation of LXD on your host machine, please install the [Snap version](https://snapcraft.io/lxd), migrate all your containers and remobe the deb/ppa packages manually before running this script.
2. Prepare an empty folder on your host which will be shared with the container. Let's call it `Shared`.
3. Download and save the [NVidia OptiX 6.5](https://developer.nvidia.com/designworks/optix/download) installation script to `Shared/Setup`. You will need a developer registration at NVidia for that. As of May 2020 Mitsuba2 does not work with Optix 7.0 or higher.
4. If you wish to compile Mitsuba with [non-default variants](https://mitsuba2.readthedocs.io/en/latest/src/getting_started/variants.html) (incl. all the interesting stuff like GPU) grab the `mitsuba.conf.template` file from the Mitsuba2 repository and save a customized copy to `Shared/Setup/mitsuba.conf`.

## Installation
* Download the script or clone this repository
* Make it executable: `chmod +x mitsuba2lxd.sh`

**Be aware that this script may lead to damaging your hardware, data loss or other issues. Please check its code before running it and watch its progress. Abort in case of any errors.** The license terms attached in this repository apply.

Run the script `./mitsuba2lxd.sh` and wait for the setup to finish. It can take up to an hour.

## Usage
Once the container is ready, you can get in using following shell command. Make sure to substitute `<container-name>` for the name of your Mitsuba2 container you selected right after starting the script.
```sh
lxc exec <container-name> -- sudo --login --user ubuntu
```


