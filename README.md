# docker-recreate
Docker run bash script for linux to recreate a container based on docker inspect information

To run this script:

1. Save it to a file, e.g., docker_recreate.sh.
2. Make it executable: chmod +x docker_recreate.sh.
3. Run the script with your container ID or name: ./docker_recreate.sh your_container_id_or_name

Make sure to have jq installed or install it during the run automatically

It returns you a command to recreate a container, so you can edit all basic commands to recreate a container of your choice.

If you need additional commands or arguments let me know and I will implement them.
