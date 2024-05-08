#!/bin/bash

# Sanity check
if [ -z $(which docker) ]
then
	echo "Docker is not installed or in the PATH!"
	exit 1
fi

# Default gitlab home directory
GITLAB_HOME=/srv/gitlab

# If the user doesn't supply a hostname, use the IP instead
CURRENT_IP=
if [ ! -z $(which ip) ]
then
	CURRENT_IP=$(ip -br a | grep $(ip route | grep default | cut -d' ' -f5) 2>/dev/null | sed 's/\(\s\)\s*/\1/g' | cut -d' ' -f3 | cut -d'/' -f1)
fi

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
	printf "\t-d,--dont-publish-ports\tDon't publish any ports from the docker container\n"
	printf "\t-e,--export\t\tExport the image for offline install\n"
	printf "\t-i,--image-file\t\tThe image file to load for an offline installation\n"
	printf "\t   --ssh-port\t\tSpecify the SSH port to publish\n"
	printf "\t   --http-port\t\tSpecify the HTTP port to publish\n"
	printf "\t   --https-port\t\tSpecify the HTTPS port to publish\n"
	printf "\t   --no-ssh\t\tDon't publish the SSH port\n"
	printf "\t   --no-http\t\tDon't publish the HTTP port\n"
	printf "\t   --no-https\t\tDon't publish the HTTPS port\n"
	printf "\t   --fetch-only\t\tFetch the image only, do not run\n"
	printf "\t   --gitlab-home\tSet the gitlab home directory on the HOST\n"
}

DEFAULT_PORTS="yes"

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
		-d|--dont-publish-ports)
			if [[ ! -z $SSH_PORT ]]
			then
				echo "--dont-publish-ports is incompatible with --ssh-port"
				usage
				exit 1
			fi
			if [[ ! -z $HTTP_PORT ]]
			then
				echo "--dont-publish-ports is incompatible with --http-port"
				usage
				exit 1
			fi
			if [[ ! -z $HTTPS_PORT ]]
			then
				echo "--dont-publish-ports is incompatible with --https-port"
				usage
				exit 1
			fi
			DEFAULT_PORTS=
			DONT_PUBLISH="yes"
			SSH_PORT=
			HTTP_PORT=
			HTTPS_PORT=
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
		--ssh-port)
			if [[ ! -z $DONT_PUBLISH ]]
			then
				echo "--ssh-port is incompatible with --dont-publish-ports"
				usage
				exit 1
			fi
			if [[ ! -z $NO_SSH ]]
			then
				echo "--ssh-port is incompatible with --no-ssh"
				usage
				exit 1
			fi
			if [[ ! $# -gt 1 ]]
			then
				echo "Expected argument for $1!"
				usage
				exit 1
			fi
			DEFAULT_PORTS=
			SSH_PORT=$2
			shift
			;;
		--http-port)
			if [[ ! -z $DONT_PUBLISH ]]
			then
				echo "--http-port is incompatible with --dont-publish-ports"
				usage
				exit 1
			fi
			if [[ ! -z $NO_HTTP ]]
			then
				echo "--http-port is incompatible with --no-http"
				usage
				exit 1
			fi
			if [[ ! $# -gt 1 ]]
			then
				echo "Expected argument for $1!"
				usage
				exit 1
			fi
			DEFAULT_PORTS=
			HTTP_PORT=$2
			shift
			;;
		--https-port)
			if [[ ! -z $DONT_PUBLISH ]]
			then
				echo "--https-port is incompatible with --dont-publish-ports"
				usage
				exit 1
			fi
			if [[ ! -z $NO_HTTPS ]]
			then
				echo "--https-port is incompatible with --no-https"
				usage
				exit 1
			fi
			if [[ ! $# -gt 1 ]]
			then
				echo "Expected argument for $1!"
				usage
				exit 1
			fi
			DEFAULT_PORTS=
			HTTPS_PORT=$2
			shift
			;;
		--no-ssh)
			if [[ ! -z $SSH_PORT ]]
			then
				echo "--no-ssh is incompatible with --ssh-port"
				usage
				exit 1
			fi
			DEFAULT_PORTS=
			NO_SSH="yes"
			SSH_PORT=
			;;
		--no-http)
			if [[ ! -z $HTTP_PORT ]]
			then
				echo "--no-http is incompatible with --http-port"
				usage
				exit 1
			fi
			DEFAULT_PORTS=
			NO_HTTP="yes"
			HTTP_PORT=
			;;
		--no-https)
			if [[ ! -z $HTTPS_PORT ]]
			then
				echo "--no-https is incompatible with --https-port"
				usage
				exit 1
			fi
			DEFAULT_PORTS=
			NO_HTTPS="yes"
			HTTPS_PORT=
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

if [[ ! -z $DEFAULT_PORTS ]]
then
	SSH_PORT=22
	HTTP_PORT=80
	HTTPS_PORT=443
fi

# Ensure the publish ports don't conflict
if [[ ! -z $SSH_PORT || ! -z $HTTP_PORT || ! -z $HTTPS_PORT ]]
then
	if [[ -z $(which netstat) ]]
	then
		echo "Netstat is not installed or in the PATH!"
		exit 1
	fi

	LISTENING_PORTS=$(netstat -atn | grep "LISTEN")

	if [[ ! -z $SSH_PORT && ! -z $(echo $LISTENING_PORTS | grep "0.0.0.0:$SSH_PORT") ]]
	then
		echo "Please disable ssh or remap the port with --ssh-port"
		echo "or disable it with --no-ssh or --dont-publish-ports"
		usage
		exit 1
	fi

	if [[ ! -z $HTTP_PORT && ! -z $(echo $LISTENING_PORTS | grep "0.0.0.0:$HTTP_PORT") ]]
	then
		echo "Please disable the service using HTTP or remap the port with --http-port"
		echo "or disable it with --no-http or --dont-publish-ports"
		usage
		exit 1
	fi

	if [[ ! -z $HTTPS_PORT && ! -z $(echo $LISTENING_PORTS | grep "0.0.0.0:$HTTPS_PORT") ]]
	then
		echo "Please disable the service using HTTPS or remap the port with --https-port"
		echo "or disable it with --no-https or --dont-publish-ports"
		usage
		exit 1
	fi
fi

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

	PUBLISH_SSH=
	if [[ ! -z $SSH_PORT ]]
	then
		PUBLISH_SSH="--publish $SSH_PORT:22"
	fi

	PUBLISH_HTTP=
	if [[ ! -z $HTTP_PORT ]]
	then
		PUBLISH_HTTP="--publish $HTTP_PORT:80"
	fi

	PUBLISH_HTTPS=
	if [[ ! -z $HTTPS_PORT ]]
	then
		PUBLISH_HTTPS="--publish $HTTPS_PORT:443"
	fi

	sudo docker run --detach \
	    --hostname $HOSTNAME \
		$PUBLISH_SSH $PUBLISH_HTTP $PUBLISH_HTTPS \
	    --name gitlab \
	    --restart always \
	    --volume $GITLAB_HOME/config:/etc/gitlab \
	    --volume $GITLAB_HOME/logs:/var/log/gitlab \
	    --volume $GITLAB_HOME/data:/var/opt/gitlab \
	    --shm-size 256m \
	    gitlab/gitlab-ce:$VERSION
fi

