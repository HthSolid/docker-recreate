#!/bin/bash

# copyright 2024
# created and licensed by Hendrik Thurau Enterprises
# https://hendrikthurau.enterprises
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

docker_id=$(docker inspect --format '{{.Id}}' "$CONTAINER_ID_OR_NAME")
json_data=$(curl --unix-socket /var/run/docker.sock -X GET "http://localhost/containers/$docker_id/json")
if [ $? -ne 0 ]; then
    echo "Failed to fetch data from container: $CONTAINER_ID_OR_NAME"
    exit 1
fi
# echo "$json_data"

delete_key() {
    local key_to_delete=$1
    json_data=$(echo "$json_data" | jq "del(.$key_to_delete)")
}
delete_key "Id"
delete_key "Created"
delete_key "State"
delete_key "GraphDriver"
delete_key "ResolvConfPath"
delete_key "HostnamePath"
delete_key "HostsPath"
delete_key "LogPath"
delete_key "RestartCount"

move_json_keys() {
    local key_to_move="$1"
    local new_location="$2"

    local arr_ktm=$(echo "$key_to_move" | sed 's/\./\n/g')
    local arr_nl=$(echo "$new_location" | sed 's/\./\n/g')

    local ktm_str=""
    local nl_str=""

    local ktm_len=$(echo "$arr_ktm" | grep -c '^')
    local nl_len=$(echo "$arr_nl" | grep -c '^')

    local ktm_last=""
    local nl_last=""

    for ktm in $arr_ktm; do
        ktm_str="$ktm_str[\"$ktm\"]"
        ktm_last=$ktm
    done
    # echo "ktm_str $ktm_str"
    local keyval=$(echo "$json_data" | jq -c ".$ktm_str")
    # echo "keyval $keyval"

    local i=1
    for nl in $arr_nl; do
        if [ "$i" -eq "$nl_len" ]; then
            nl_last=$nl
        else
            nl_str="$nl_str[\"$nl\"]"
        fi
        ((i++))
    done
    # echo "nl_last $nl_last"
    # echo "nl_str $nl_str"
    
    if [ -n "$nl_str" ]; then
        # echo "1"
        json_data=$(echo "$json_data" | jq ".$nl_str += {\"$nl_last\": $keyval} | del(.$ktm_str)")
    else
        # echo "0"
        json_data=$(echo "$json_data" | jq ". += {\"$new_location\": $keyval} | del(.$ktm_str)")
    fi
}

move_json_keys "Config.Hostname" "Hostname"
move_json_keys "Config.Domainname" "Domainname"
move_json_keys "Config.User" "User"
move_json_keys "Config.AttachStdin" "AttachStdin"
move_json_keys "Config.AttachStdout" "AttachStdout"
move_json_keys "Config.AttachStderr" "AttachStderr"
move_json_keys "Config.ExposedPorts" "ExposedPorts"
move_json_keys "Config.Tty" "Tty"
move_json_keys "Config.OpenStdin" "OpenStdin"
move_json_keys "Config.StdinOnce" "StdinOnce"
move_json_keys "Config.Env" "Env"
move_json_keys "Config.Cmd" "Cmd"
move_json_keys "Config.Image" "Image"
move_json_keys "Config.WorkingDir" "WorkingDir"
move_json_keys "Config.Entrypoint" "Entrypoint"
move_json_keys "Config.OnBuild" "OnBuild"
move_json_keys "Config.Labels" "Labels"

move_json_keys "NetworkSettings.MacAddress" "MacAddress"
move_json_keys "NetworkSettings.Networks" "NetworkingConfig.EndpointsConfig"

# move_json_keys "Mounts" "HostConfig.Mounts"
# json_data=$(echo "$json_data" | jq '.HostConfig.Mounts |= map(
#     with_entries(
#         if .key == "Destination" then .key = "Target"
#         elif .key == "RW" then .key = "ReadOnly" | .value |= not
#         else .
#         end
#     )
# )')
volumes=$(echo "$json_data" | jq -r '.Mounts[] | (if .Name then .Name else .Source end) + ":" + .Destination + (if .RW == false then ":ro" else "" end) + " "')
for vol in $volumes; do
    json_data=$(echo "$json_data" | jq ".[\"HostConfig\"][\"Binds\"] += [\"$vol\"]")
done
delete_key "Mounts"

echo "$json_data" | jq .

# Function to edit a string or array value
edit_value() {
    local key=$1
    local value=$(echo "$json_data" | jq ".$key // \"null\"")
    echo "Current value of $key: $value"
    read -p "Enter new value for $key (or leave blank to keep current value): " new_value
    if [ -n "$new_value" ]; then
        if [[ "$new_value" =~ ^-?[0-9]+([.][0-9]+)?$ || "$new_value" =~ ^(\[|\{) || "$new_value" == "null" || "$new_value" == "true" || "$new_value" == "false" ]]; then
            # Directly use the value as it is a valid JSON literal, array, or object
            json_data=$(echo "$json_data" | jq ".$key = $new_value")
        else
            # Treat as a string and add quotes
            json_data=$(echo "$json_data" | jq ".$key = \"$new_value\"")
        fi
    fi
}

# Function to process array
process_array() {
    local parent_path=$1
    local current_data=$2
    local length=$(echo "$current_data" | jq 'length')

    echo "Select an index to edit (0 to $(($length - 1))):"
    for ((i=0; i<$length; i++)); do
        echo "[$i] $(echo "$current_data" | jq ".[$i]")"
    done

    read -p "Enter index (or 'b' to go back): " index
    if [[ "$index" == 'b' ]]; then
        return
    elif [[ "$index" =~ ^[0-9]+$ ]] && [ "$index" -ge 0 ] && [ "$index" -lt "$length" ]; then
        local entry_type=$(echo "$current_data" | jq -r ".[$index] | type")
        if [ "$entry_type" == "object" ]; then
            process_keys "$parent_path[$index]." "$(echo "$current_data" | jq ".[$index]")"
        else
            edit_value "$parent_path[$index]"
        fi
    else
        echo "Invalid index."
    fi
}

# Function to process JSON keys
continue_editing=true
process_keys() {
    local parent_path=$1
    local current_data=$2

    while $continue_editing; do
        local keys=$(echo "$current_data" | jq -r 'keys[]')

        echo "Select a key to edit at path $parent_path:"
        select key in $keys "Go Back" "Finish"; do
            if [[ "$key" == "Finish" ]]; then
                echo "Final JSON data:"
                echo "$json_data"
                continue_editing=false
                return
            elif [[ "$key" == "Go Back" ]]; then
                return
            elif [ -n "$key" ]; then
                local key_type=$(echo "$current_data" | jq -r ".[\"$key\"] | type")

                case $key_type in
                    object)
                        # Recursive call for nested structure
                        if [ "$(echo "$current_data" | jq -r ".[\"$key\"] | keys | length")" -gt 0 ]; then
                            # echo "Has keys (non-empty object)"
                            process_keys "$parent_path\"$key\"." "$(echo "$current_data" | jq ".[\"$key\"]")"
                        else
                            # echo "Has No Keys Empty object"
                            edit_value "$parent_path\"$key\""
                        fi
                        ;;
                    array)
                        process_array "$parent_path\"$key\"" "$(echo "$current_data" | jq ".[\"$key\"]")"
                        ;;
                    string|null)
                        # Edit value if it's a string or array
                        edit_value "$parent_path\"$key\""
                        ;;
                    *)
                        echo "Unsupported type: $key_type"
                        ;;
                esac
            else
                echo "Invalid selection. Please try again."
            fi
            break
        done
    done
}

process_keys "" "$json_data"

container_new=""
echo "Do you want to CREATE the new container?"
select choice in "Yes" "No"; do
    if [[ "$choice" == "Yes" ]]; then
        json_string=$(echo "$json_data" | jq -c .)
        echo "$json_string"
        temp_file=$(mktemp)
        echo "$json_string" > "$temp_file"

        #validate the name
        container_name=$(echo "$json_data" | jq -r ".Name")
        if [[ $container_name == /* ]]; then
            container_name="${container_name:1}"
        fi
        regex_name="^/?[a-zA-Z0-9][a-zA-Z0-9_.-]+$"
        if [[ $container_name =~ $regex_name ]]; then
            echo "Name is valid."
        else
            read -p "Name is invalid $container_name, please input a new name: " new_name
            if [ -n "$new_value" ]; then
                container_name=$new_name
            else
                echo "Name is invalid, exiting"
                exit 1 # Exit the script if the query parameter is invalid
            fi
        fi

        container_new=$(curl --unix-socket /var/run/docker.sock -X POST -H "Content-Type: application/json" -d @"$temp_file" "http://localhost/containers/create?name=$container_name")
        rm "$temp_file"
        message=$(echo "$container_new" | jq ".message")
        # echo "$container_new"
        if [ -n "$message" ]; then
            echo "ERROR: $message"
            echo "exiting..."
            exit 0
        fi

        new_id=$(echo "$container_new" | jq ".Id")
        echo "New Container: $new_id"

        echo "Do you want to START the new container?"
        select choice in "Yes" "No"; do
            if [[ "$choice" == "Yes" ]]; then                
                docker_start=$(curl --unix-socket /var/run/docker.sock -X POST "http://localhost/containers/$new_id/start")
                echo "$docker_start"
                break
            elif [[ "$choice" == "No" ]]; then
                break
            fi
        done

        break
    elif [[ "$choice" == "No" ]]; then
        break
    fi
done

