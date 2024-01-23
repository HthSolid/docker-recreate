# docker-recreate
Docker run bash script for linux to recreate a container based on docker inspect information

# docker_recreate.sh
To run the shell script that creates a docker run command:

1. Save docker_recreate.sh to a file, e.g., docker_recreate.sh.
2. Make it executable: chmod +x docker_recreate.sh.
3. Run the script with your container ID or name: ./docker_recreate.sh your_container_id_or_name

Make sure to have jq installed or install it during the run automatically

It returns you a command to recreate a container, so you can edit all basic commands to recreate a container of your choice.

# docker_recreate_interactive.sh
To run the shell script that lets you interactively change the values of a docker container and let's you create a new container and run it:

1. Save docker_recreate_interactive.sh to a file, e.g., docker_recreate_interactive.sh.
2. Make it executable: chmod +x docker_recreate_interactive.sh.
3. Run the script with your container ID or name: ./docker_recreate_interactive.sh your_container_id_or_name

Make sure to have jq installed or install it during the run automatically

It will let you interactively change everything from the docker container and ask you at the end if you want to create the container with the values that you created, it will also give you the json string for creating the docker container
It uses docker api to create a new container and to read all data from the given container

If you need additional commands or arguments let me know and I will implement them
