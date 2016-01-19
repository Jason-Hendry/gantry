#!/usr/bin/env bash

[ -f .gantry ] && . .gantry
[ -f gantry.sh ] && . gantry.sh

[ -z $DOCKER_HTTP_PORT ] && export DOCKER_HTTP_PORT=80
[ -z $PHPUNIT_CONF_PATH ] && export PHPUNIT_CONF_PATH="app"

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
# Build Docker Containers
function build() {
    docker-compose build
}
# Rebuild Docker Containers
function rebuild() {
    stop
    build
    start
}
# Open in web browser
function web() {
    echo "Opening: http://$(_dockerHost):$DOCKER_HTTP_PORT"
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
# run cap (capistrano) command inside docker container (neolao/capistrano:2.15.5) (extra args passed to phpunit command)
function cap() {
    docker run -it --rm -v .:/source neolao/capistrano:2.15.5 cap $@
}
# run unit tests on app folder (extra args passed to phpunit command)
function test() {
    _exec phpunit -c $PHPUNIT_CONF_PATH $@
}

function _mainContainer {
    # Grab the first non-blank line
    cat docker-compose.yml | grep -vE '^\s*$' | head -n1 | tr -d ':'
}
function _dockerHost {
    if [ -z $DOCKER_HOST ]
    then
        echo localhost;
        exit;
    fi
    echo $DOCKER_HOST | sed 's/tcp:\/\///' | sed 's/:.*//'
}

function _exec() {
    docker exec -it ${COMPOSE_PROJECT_NAME}_$(_mainContainer)_1 $@
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
    if [ -f gantry.sh ]; then
      echo -n "Project Commands (gantry.sh)"
      cat gantry.sh | grep -B1 -E "function [a-z]" | tr "\n" ">" | tr "#" "\n" | perl -F'>' -ane '$fun = substr(substr($F[1], 9), 0, -4);printf "  %-15s %s\n", $fun, $F[0]'
    fi
    echo ""
    exit;
fi

# Run Command
$1 ${@:2}
