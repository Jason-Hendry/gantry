#!/usr/bin/env bash

export GANTRY_VERSION="1.0"

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
# run cap (capistrano) command inside docker container (neolao/capistrano:2.15.5) (extra args passed to cap command)
function cap() {
    docker run -it --rm -v `pwd`:/source -v $HOME/.ssh/id_rsa:/key neolao/capistrano:3.4.0 cap $@
}
# run sass command inside docker container (rainsystems/sass:3.4.21) (extra args passed to sass command)
function sass() {
    docker run -it --rm -v `pwd`:/source rainsystems/sass:3.4.21 sass $@
}
# run bower command inside docker container (rainsystems/bower:1.7.2) (extra args passed to bower command)
function bower() {
    docker run -it --rm -v `pwd`:/source rainsystems/bower:1.7.2 bower --allow-root $@
}
# print version
function version() {
    echo "Gantry v${GANTRY_VERSION} - Author Jason Hendry https://github.com/Jason-Hendry/gantry"
}
# Update gantry
function self-update() {
    if [ -w $0 ]; then
        curl -o $0 https://raw.githubusercontent.com/Jason-Hendry/gantry/master/gantry.sh
        if [ !-x $0 ]; then
            chmod +x $0
        fi
    else
        sudo curl -o $0 https://raw.githubusercontent.com/Jason-Hendry/gantry/master/gantry.sh
        if [ !-x $0 ]; then
            sudo chmod +x $0
        fi
    fi
}

# run unit tests on app folder (extra args passed to phpunit command)
function test() {
    _exec phpunit -c $PHPUNIT_CONF_PATH $@
}
# run symfony console (./app/console ...)
function symfony() {
    _exec ./app/console $@
}
# create fosUserBundle user (username email password role)
function create-user() {
    _exec ./app/console fos:user:create $1 $2 $3
    _exec ./app/console fos:user:promote $1 $4
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
