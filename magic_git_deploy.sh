#!/bin/bash

REPO=
DEPLOY=
LOG=
BACKGROUND=0
CHECK_FREQUENCY=
USE_PROWL=0

function _log() {

	echo "$(date +"%Y-%m-%d %H:%M:%S") : $1" >> $LOG 2>&1

}

function _prowl() {

	if [ $USE_PROWL -eq 1 ]; then
		prowl 0 "Deployment of $(basename $REPO)" "$1" >> $LOG 2>&1
	fi

}

function _display_help() {

	cat << EOF
Usage:
	--repo            - Deployment Repository
	                     (this is where you’ll be pushing your local Git repo to when you want to automate a deployment)
	--deploy          - Deployment Directory
	                     (the actual directory where your deployment will reside)
	--log             - Logging Directory
	                     (a directory to keep logs)
	--background      - The script should expect to be run in the background, and continue until the process is killed
	--check_frequency - The frequency in minutes where the script should check the build. Only needed if --background is invoked.
	--use_prowl       - Send a Prowl notification on beginning and end of process

For more information and example of usage, please consult the README file or visit:
https://github.com/heliomass/Magic-Git-Deploy

EOF

return $?

}

# Parse command arguments
while [ $# -gt 0 ]; do
	case "$1" in
		--repo)
			REPO=$2
			shift 2
			;;
		--deploy)
			DEPLOY=$2
			shift 2
			;;
		--log)
			LOG=$2
			shift 2
			;;
		--background)
			BACKGROUND=1
			shift
			;;
		--check_frequency)
			CHECK_FREQUENCY=$2
			shift 2
			;;
		--use_prowl)
			USE_PROWL=1
			shift
			;;
		--help|-h|-?)
			_display_help
			exit $?
			;;
		*)
			echo "Unrecognised paramter ${1}. Please use the --help switch to see usage." >&2
			exit 1
			;;
	esac
done

# Check all paramters were supplied.
arg_error=0
if [ -z $REPO ]; then
	echo 'Please supply --repo' >&2
	arg_error=1
fi
if [ -z $DEPLOY ]; then
	echo 'Please supply --deploy' >&2
	arg_error=
fi
if [ -z $LOG ]; then
	echo 'Please supply --log' >&2
	arg_error=1
fi
if [ $BACKGROUND -eq 1 -a -z "$CHECK_FREQUENCY" ]; then
	echo 'For background mode, please supply --check_frequency argument in minutes.'
	exit 1
fi

if [ $arg_error -eq 1 ]; then
	echo 'Please use --help to display info on all the possible arguments.' >&2
	exit 1
fi

# Check the repository actually exists
if [ ! -d "$REPO" ]; then
	echo "Unable to find repository $REPO. Is it really a Git repo?" >&2
	arg_error=1
elif [ ! -f $REPO/refs/heads/master ]; then
	echo "Supplied repository doesn't look like a valid Git repo." >&2
	arg_error=1
fi

# Check the log path supplied is to a directory
if [ "$LOG" != '<<stdout>>' -a ! -d "$LOG" ]; then
	echo 'Supplied logging directory does not exist.' >&2
	arg_error=1
fi

# If we're backgrounding, convert the value of CHECK_FREQUENCY from minutes to seconds
if [ $BACKGROUND -eq 1 ]; then
	CHECK_FREQUENCY=$(echo "$CHECK_FREQUENCY * 60" | bc -l)
fi

# If a prowl server was provided, check prowl is installed
if [ $USE_PROWL -eq 1 ]; then
	which prowl > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo 'Could not find a prowl executable.' >&2
		arg_error=1
	fi
fi

# Override the log file name by appending the date to the end
if [ "$LOG" != '<<stdout>>' ]; then
	LOG="$(echo -n $(echo -n ${LOG} | sed 's|/$||')/$(basename $REPO) | sed 's|.git$||').$(date +%Y%m%d)"
else
	LOG='/dev/stdout'
fi

# Check we can access the log file
touch $LOG
if [ $? -ne 0 ]; then
	echo "Unable to write to log file: $LOG" >&2
	arg_error=1
fi

# We need to remember what the previous hash was
PREV_HASH_FILE="$HOME/.deploy_$(echo $(basename $REPO) | sed 's|.git$||')"
if [ $? -ne 0 ]; then
	echo 'Unable to derive a basename to store the previous hash.' >&2
	arg_error=1
fi

if [ $arg_error -eq 1 ]; then
	exit 1
fi

# Ensure the deploy path ends with a trailing slash
DEPLOY="$(echo -n ${DEPLOY}/ | sed 's|//$|/|')"

_log "Begin."

if [ $BACKGROUND -ne 1 ]; then
	_log "Mode set to cron (we will run only once, and then exit)"
else
	_log "Mode set to background (we will run until the process is killed)"
fi

# We need to ensure we always carry out the loop at least once
first_loop=1

# We loop forever in background mode, otherwise we do it once.
while [ $first_loop -eq 1 -o $BACKGROUND -eq 1 ]; do

	first_loop=0

	# Get current hash of git repo
	current_hash=$(cat $REPO/refs/heads/master)

	# Get last hash of repo
	last_hash=
	if [ -f "$PREV_HASH_FILE" ]; then
		last_hash=$(cat $PREV_HASH_FILE)
	fi

	_log "Current Hash:  $current_hash"
	_log "Previous Hash: $last_hash"

	# Compare
	if [ "$current_hash" != "$last_hash" ]; then

		# We have a new deployment!
		_log "A new deployment has been detected."
		_prowl "A new deployment has been detected: $current_hash"
		echo $current_hash > $PREV_HASH_FILE

		# Create our temporary storage area
		dir_checkout=$(mktemp -d)

		# Clone the repo into the temporary directory
		git clone --local $REPO $dir_checkout >> $LOG 2>&1

		if [ $? -ne 0 ]; then
			_log "Failed to checkout build."
			_prowl "Failed to checkout build."
			exit 1
		fi

		_log "Build checked out successfully."

		# Now get a list of files we need to ignore
		ignore_files=
		if [ -f "${dir_checkout}/.deployignore" ]; then
			while read -r line; do
				ignore_files="$ignore_files --exclude $line "
			done < ${dir_checkout}/.deployignore
		fi

		# Now rsync the checked out build into the deployment directory, ignoring the .git files of course!
		rsync ${dir_checkout}/ $DEPLOY --exclude '.git/' $ignore_files --recursive --delete-after --prune-empty-dirs --human-readable >> $LOG 2>&1

		if [ $? -ne 0 ]; then
			_log "Failed to deploy build."
			_prowl "Failed to deploy build."
			exit 1
		fi

		# Remove the checked out build.
		rm -rf $dir_checkout >> $LOG 2>&1

		_log "Successfully deployed build."
		if [ $USE_PROWL -eq 1 ]; then
			_prowl "Successfully deployed build."
		fi

	else
		_log "No new deployment was detected."
	fi

	# If we're in background mode, sleep for a while
	if [ $BACKGROUND -eq 1 ]; then
		_log "Sleeping for $CHECK_FREQUENCY seconds."
		sleep $CHECK_FREQUENCY
	fi

done

_log "End."
exit 0
