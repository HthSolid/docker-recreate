#!/bin/bash

# copyright 2024
# created and licensed by Hendrik Thurau Enterprises
# free to use as long as you leave this copyright notice

# Function to check if jq is installed
check_jq_installed() {
    if ! command -v jq &> /dev/null; then
        echo "jq is not installed. It is required for this script to run."
        read -p "Would you like to install jq now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_jq
        else
            echo "jq is required. Exiting."
            exit 1
        fi
    fi
}

# Function to install jq
install_jq() {
    echo "Installing jq..."
    sudo apt-get update && sudo apt-get install -y jq
}

# Function to format capabilities
format_caps() {
    local caps=$1
    local adddrop=$2
    if [[ $caps != "null" ]]; then
        echo $caps | jq -r 'join(" ")' | sed -e 's/^/'"$adddrop"='/g' -e 's/ / '"$adddrop"='/g'
    else
        echo ""
    fi
}

# Check if a container ID or name was provided
if [ $# -eq 0 ]; then
    echo "No container ID or name supplied."
    echo "Usage: $0 [container_id_or_name]"
    exit 1
fi

# Check if jq is installed
check_jq_installed

# Use the first argument as the container ID or name
CONTAINER_ID_OR_NAME="$1"

# Initialize the Docker run command
docker_run_cmd="docker run -d"

# Function to add option if not empty
add_option_if_not_empty() {
    local value=$1
    local option=$2
    local hype=$3
    if [ -n "$value" ]; then
        if [[ "$value" =~ ^[0-9]+$ ]]; then
            if [ "$value" -ne 0 ]; then
                # Handle non-zero numbers
                if [ -n "$hype" ]; then
                    docker_run_cmd+=" $option \"$value\""
                else
                    docker_run_cmd+=" $option $value"
                fi
            fi
        else
            if [ -n "$hype" ]; then
                docker_run_cmd+=" $option \"$value\""
            else
                docker_run_cmd+=" $option $value"
            fi
        fi
    fi
}

# Get Environment Variables
env_vars=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_ID_OR_NAME")
if [ -n "$env_vars" ]; then
    for var in $env_vars; do
        docker_run_cmd+=" -e $var"
    done
fi

# Get Port Bindings
ports=$(docker inspect --format='{{json .NetworkSettings.Ports}}' "$CONTAINER_ID_OR_NAME" | jq -r '. | to_entries[] | select(.value != null) | (if .value[0].HostIp != null then .value[0].HostIp + ":" else "" end) + .value[0].HostPort + ":" + .key')
if [ -n "$ports" ]; then
    for port in $ports; do
        docker_run_cmd+=" -p $port"
    done
fi

# Get Volume Mounts
volumes=$(docker inspect "$CONTAINER_ID_OR_NAME" | jq -r '.[0].Mounts[] | "type=" + .Type + ",source=" + .Source + ",target=" + .Destination + (if .Driver then ",volume-driver=" + .Driver else "" end) + (if .RW == false then ",readonly" else "" end) + " "')
if [ -n "$volumes" ]; then
    for volume in $volumes; do
        docker_run_cmd+=" --mount '$volume'"
    done
fi

# Get Networks
networks=$(docker inspect --format '{{json .NetworkSettings.Networks}}' "$CONTAINER_ID_OR_NAME" | jq -r '. | to_entries[] | select(.value != null) | .key')
if [ -n "$networks" ]; then
    for network in $networks; do
        docker_run_cmd+=" --network='$network'"
    done
fi

# Get Labels
labels=$(docker inspect --format '{{json .Config.Labels}}' "$CONTAINER_ID_OR_NAME" | jq -r '. | to_entries[] | select(.value != null) | "--label " + .key + "=\"" + .value + "\"" + " "')
echo $labels
if [ -n "$labels" ]; then
    docker_run_cmd+=" $labels"
fi

# Get WorkDir
workdir=$(docker inspect --format '{{.Config.WorkingDir}}' "$CONTAINER_ID_OR_NAME")
if [ -n "$workdir" ]; then
    docker_run_cmd+=" --workdir='$workdir'"
fi

# Get capabilities information
caps=$(docker inspect --format '{{json .HostConfig.CapAdd}} {{json .HostConfig.CapDrop}}' "$CONTAINER_ID_OR_NAME")

# Extract CapAdd and CapDrop
cap_add_json=$(docker inspect --format '{{json .HostConfig.CapAdd}}' "$CONTAINER_ID_OR_NAME")
cap_drop_json=$(docker inspect --format '{{json .HostConfig.CapDrop}}' "$CONTAINER_ID_OR_NAME")
caps_cmd=$(format_caps "$cap_add_json" "--cap-add")
caps_cmd+=$(format_caps "$cap_drop_json" "--cap-drop")


# Additional fields
# network_mode=$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$CONTAINER_ID_OR_NAME")
name=$(docker inspect --format '{{.Name}}' "$CONTAINER_ID_OR_NAME")
if [ -n "$name" ]; then
    docker_run_cmd+=" --name=\"$name\""
fi
restart_policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER_ID_OR_NAME")
memory_limit=$(docker inspect --format '{{.HostConfig.Memory}}' "$CONTAINER_ID_OR_NAME")
cpu_shares=$(docker inspect --format '{{.HostConfig.CpuShares}}' "$CONTAINER_ID_OR_NAME")
cpuset_cpus=$(docker inspect --format '{{.HostConfig.CpusetCpus}}' "$CONTAINER_ID_OR_NAME")
user=$(docker inspect --format '{{.Config.User}}' "$CONTAINER_ID_OR_NAME")

entrypoint=$(docker inspect --format '{{json .Config.Entrypoint}}' "$CONTAINER_ID_OR_NAME" | jq -r 'join(" ")')
cmd=$(docker inspect --format '{{json .Config.Cmd}}' "$CONTAINER_ID_OR_NAME" | jq -r 'join("; ")')

image_name=$(docker inspect --format '{{.Config.Image}}' "$CONTAINER_ID_OR_NAME")

#ARGS
privileged=$(docker inspect --format '{{.HostConfig.Privileged}}' "$CONTAINER_ID_OR_NAME")
if [ "$privileged" = "true" ]; then
    docker_run_cmd+="--privileged"
fi

# Add options if they are set
# add_option_if_not_empty "$network_mode" "--network"
add_option_if_not_empty "$restart_policy" "--restart"
add_option_if_not_empty "$memory_limit" "--memory"
add_option_if_not_empty "$cpu_shares" "--cpu-shares"
add_option_if_not_empty "$cpuset_cpus" "--cpuset-cpus"
add_option_if_not_empty "$user" "--user"
add_option_if_not_empty "$entrypoint" "--entrypoint" "true"
add_option_if_not_empty "$caps_cmd" ""

docker_run_cmd+=" $image_name"
add_option_if_not_empty "$cmd" "/bin/bash -c" "true"

# Construct Docker Run Command
echo "$docker_run_cmd"
