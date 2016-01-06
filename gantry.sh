#!/usr/bin/env bash

[ -f .gantry ] && . .gantry

[ -z $DOCKER_HTTP_PORT ] && export DOCKER_HTTP_PORT=80

# Start Docker Containers
function start() {
    docker-compose up -d
}
# Stop Docker Containers
function stop() {
    bash -c "DOCKER_HTTP_PORT=80 docker-compose stop"
}
# Restart Docker Containers
function restart() {
    stop
    start
}
# Rebuild Docker Containers
function rebuild() {
    stop
    _build
    start
}
# Open in web browser
function web() {
    open http://$(_dockerHost):$DOCKER_HTTP_PORT
}
# Open terminal console on main docker container
function console() {
    docker exec -it ${COMPOSE_PROJECT_NAME}_$(_mainContainer)_1 bash
}
# Remove all containers and delete volumes
function remove() {
    docker-compose rm -v
}
# Open terminal console on main docker container
function psql() {
    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash -c "PGPASSWORD="\$POSTGRES_PASSWORD" psql -U postgres \$POSTGRES_DB"
}
# Open terminal console on db docker container
function console_db() {
    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash
}

function _mainContainer {
    # Grab the first non-blank line
    cat docker-compose.yml | grep -vE '^\s*$' | head -n1 | tr -d ':'
}
function _dockerHost {
    echo $DOCKER_HOST | sed 's/tcp:\/\///' | sed 's/:.*//'
}
function _build {
    docker-compose build
}

if [ -z $1 ]; then
    echo "Usage $0 [command]"
    echo ""
    echo -n "Commands"
    cat `which $0` | grep -B1 -E "function [a-z]" | tr "\n" ">" | tr "#" "\n" | perl -F'>' -ane '$fun = substr(substr($F[1], 9), 0, -4);printf "  %-15s %s\n", $fun, $F[0]'
    echo ""
    if [ -f .gantry ]; then
      echo -n "Project Commands (.gantry)"
      cat .gantry | grep -B1 -E "function [a-z]" | tr "\n" ">" | tr "#" "\n" | perl -F'>' -ane '$fun = substr(substr($F[1], 9), 0, -4);printf "  %-15s %s\n", $fun, $F[0]'
    fi
    echo ""
    exit;
fi

# Run Command
$1 ${@:2}
