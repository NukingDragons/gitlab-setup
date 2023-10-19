# gitlab-setup
A simple bash script to setup a dockerized gitlab-ce instance

# Dependencies

This requies docker, ip, sudo.. and a couple other of normally installed commands

# Usage
```
Usage: gitlab-setup.sh [options]
Options:
	-h,--help		Show this help
	-v,--version		Set the gitlab verion. Defaults to 13.8.6-ce.0
	-H,--hostname		Set the hostname for the gitlab container
	-e,--export		Export the image for offline install
	-i,--image-file		The image file to load for an offline installation
	   --fetch-only		Fetch the image only, do not run
	   --gitlab-home	Set the gitlab home directory on the HOST
```
