#!/bin/bash

# Default gitlab home directory
GITLAB_HOME=/srv/gitlab

# If the user doesn't supply a hostname, use the IP instead
CURRENT_IP=$(ip -br a | grep $(ip route | grep default | cut -d' ' -f5) 2>/dev/null | sed 's/\(\s\)\s*/\1/g' | cut -d' ' -f3 | cut -d'/' -f1)
HOSTNAME=$CURRENT_IP

# 13.8.6-ce.0 is vulnerable to CVE-2021-22205
# Assume latest version unless user specifies
VULN_VERSION=latest
VERSION=$VULN_VERSION

function usage()
{
	printf "Usage: gitlab-setup.sh [options]\n"
	printf "Options:\n"
	printf "\t-h,--help\t\tShow this help\n"
	printf "\t-v,--version\t\tSet the gitlab version\n"
	printf "\t-H,--hostname\t\tSet the hostname for the gitlab container\n"
	printf "\t-e,--export\t\tExport the image for offline install\n"
	printf "\t-i,--image-file\t\tThe image file to load for an offline installation\n"
	printf "\t   --fetch-only\t\tFetch the image only, do not run\n"
	printf "\t   --gitlab-home\tSet the gitlab home directory on the HOST\n"
}

while [[ $# -gt 0 ]]
do
	case $1 in
		-h|--help)
			usage
			exit 0
			;;
		-v|--version)
			if [[ ! $# -gt 1 ]]
			then
				echo "Expected argument for $1!"
				usage
				exit 1
			fi
			VERSION=$2
			shift
			;;
		-H|--hostname)
			if [[ ! $# -gt 1 ]]
			then
				echo "Expected argument for $1!"
				usage
				exit 1
			fi
			HOSTNAME=$2
			shift
			;;
		-e|--export)
			EXPORT="yes"
			;;
		-i|--image-file)
			if [[ ! $# -gt 1 ]]
			then
				echo "Expected argument for $1!"
				usage
				exit 1
			fi
			IMAGE_FILE=$2
			shift
			;;
		--fetch-only)
			FETCH_ONLY="yes"
			;;
		--gitlab-home)
			if [[ ! $# -gt 1 ]]
			then
				echo "Expected argument for $1!"
				usage
				exit 1
			fi
			GITLAB_HOME=$2
			shift
			;;
		*)
			echo "Unknown argument \"$1\""
			usage
			exit 1
			;;
	esac
	shift
done

if [[ -z $CURRENT_IP && -z $HOSTNAME ]]
then
	echo "Failed to grab default hostname!"
	echo "Please supply a hostname via --hostname"
	exit 1
fi

if [[ ! -z $IMAGE_FILE ]]
then
	echo "Attempting to load $IMAGE_FILE"
	sudo docker load -i $IMAGE_FILE
	echo "Pulling version from image file"
	VERSION=$(sudo docker images | head -2 | tail +2 | sed 's/\(\s\)\s*/\1/g' | cut -d' ' -f2)
	echo "Checking if image was loaded correctly"
	if [[ -z "$(sudo docker image ls | grep gitlab-ce | grep $VERSION)" ]]
	then
		echo "Failed to import image!"
		exit 1
	fi
else
	echo "Checking if version is already installed..."
	if [[ -z "$(sudo docker image ls | grep gitlab-ce | grep $VERSION)" ]]
	then
		echo "Attempting to pull the image"
		sudo docker pull gitlab/gitlab-ce:$VERSION
	fi
	echo "Checking if version was installed correctly"
	if [[ -z "$(sudo docker image ls | grep gitlab-ce | grep $VERSION)" ]]
	then
		echo "Failed to pull image!"
		exit 1
	fi
fi

echo "Hostname set to: \"$HOSTNAME\""
echo "Version set to: \"$VERSION\""
echo "Gitlab home set to: \"$GITLAB_HOME\""

# Optionally export the image
if [[ ! -z $EXPORT ]]
then
	if [[ "$EXPORT" == "yes" ]]
	then
		echo "Saving gitlab-ce $VERSION to ./gitlab-ce-$VERSION.docker"
		sudo docker save -o $(pwd)/gitlab-ce-$VERSION.docker gitlab/gitlab-ce:$VERSION
		sudo chown $USER:$USER $(pwd)/gitlab-ce-$VERSION.docker
	fi
fi

# Run if fetch-only wasn't supplied
if [[ -z $FETCH_ONLY ]]
then
	echo "Starting gitlab"
	sudo docker run --detach \
	    --hostname $HOSTNAME \
	    --publish 443:443 --publish 80:80 --publish 22:22 \
	    --name gitlab \
	    --restart always \
	    --volume $GITLAB_HOME/config:/etc/gitlab \
	    --volume $GITLAB_HOME/logs:/var/log/gitlab \
	    --volume $GITLAB_HOME/data:/var/opt/gitlab \
	    --shm-size 256m \
	    gitlab/gitlab-ce:$VERSION
fi

