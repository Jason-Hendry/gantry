#!/usr/bin/env bash

export GANTRY_VERSION="1.1"

[ -z $COMPOSE_PROJECT_NAME ] && export COMPOSE_PROJECT_NAME="$(basename $(pwd))"
[ -z $GANTRY_ENV ] && export GANTRY_ENV="prod"

[ -f .gantry ] && . .gantry
[ -f gantry.sh ] && . gantry.sh

[ -z $DOCKER_HTTP_PORT ] && export DOCKER_HTTP_PORT=80
[ -z $PHPUNIT_CONF_PATH ] && export PHPUNIT_CONF_PATH="app"

[ -z $SSH_DIR ] && export SSH_DIR="$HOME/.ssh"
[ -z $BOWER_VOL ] && export BOWER_VOL="`pwd`/bower_components"
[ -z $BOWER_MAP ] && export BOWER_MAP="$BOWER_VOL:/source/bower_components"

[ -d "${HOME}/.gantry" ] || mkdir -p "${HOME}/.gantry"
export GANTRY_DATA_FILE="$HOME/.gantry/${COMPOSE_PROJECT_NAME}_${GANTRY_ENV}"



## Saves you current state as sourcable variables in bash script
function _save() {
    echo '#!/usr/bin/env bash' > ${GANTRY_DATA_FILE}
    echo "export DOCKER_HTTP_PORT=\"${DOCKER_HTTP_PORT}\"" >> ${GANTRY_DATA_FILE}
    echo "export COMPOSE_PROJECT_NAME=\"${COMPOSE_PROJECT_NAME}\"" >> ${GANTRY_DATA_FILE}
}
# Start Docker Containers
function start() {

    ## If db is not started run build and run main start
    if [ -z "$(docker ps | grep -E "\b${COMPOSE_PROJECT_NAME}_db_1\b")" ]; then
        docker-compose up -d
        _save
        exit 0
    fi

    export DOCKER_HTTP_PORT1="$DOCKER_HTTP_PORT";
    export DOCKER_HTTP_PORT2=$(echo "$DOCKER_HTTP_PORT+1" | bc);

    # Get Port Number
    if [ "$(docker ps | grep ${COMPOSE_PROJECT_NAME}_main | tr ' ' "\n" | grep tcp)" == "0.0.0.0:$DOCKER_HTTP_PORT1->80/tcp" ]; then
      export DOCKER_HTTP_PORT="$DOCKER_HTTP_PORT2"
      export STOP_DOCKER_HTTP_PORT="$DOCKER_HTTP_PORT1"
    else
      export DOCKER_HTTP_PORT="$DOCKER_HTTP_PORT1"
      export STOP_DOCKER_HTTP_PORT="$DOCKER_HTTP_PORT2"
    fi

    # Build
    build || exit 1

    # Ensure only 1 copy
    if [ -n "$(docker ps | grep -E "\b${COMPOSE_PROJECT_NAME}_main_${DOCKER_HTTP_PORT}\b")" ]; then
        docker stop ${COMPOSE_PROJECT_NAME}_main_${DOCKER_HTTP_PORT}
    fi
    if [ -n "$(docker ps -a | grep -E "\b${COMPOSE_PROJECT_NAME}_main_${DOCKER_HTTP_PORT}\b")" ]; then
        docker rm -v ${COMPOSE_PROJECT_NAME}_main_${DOCKER_HTTP_PORT}
    fi

    # Start
    docker-compose start main
#    docker run -d -p ${DOCKER_HTTP_PORT}:80 \
#      --name ${COMPOSE_PROJECT_NAME}_main_${DOCKER_HTTP_PORT} \
#      -v $PWD/src:/var/www/src \
#      -v $PWD/data/logs:/var/www/app/logs \
#      --restart always \
#      --volumes-from ${COMPOSE_PROJECT_NAME}_data_shared_1 \
#      --link ${COMPOSE_PROJECT_NAME}_db_1:db \
#      -e APP_ENV=${APP_ENV} \
#      ${COMPOSE_PROJECT_NAME}_main || exit 1
#          -v $PWD/app:/var/www/app \
      # --link ${COMPOSE_PROJECT_NAME}_memcached_1:memcached \
      # --link ${COMPOSE_PROJECT_NAME}_elasticsearch_1:elasticsearch \

    # Wait for port to open
    echo "Waiting for http://$(_dockerHost):$DOCKER_HTTP_PORT";
    until $(curl --output /dev/null --silent --head --fail http://$(_dockerHost):${DOCKER_HTTP_PORT}); do
        printf '.'
        sleep 1
    done

    # Stop and remove old container
    # docker stop ${COMPOSE_PROJECT_NAME}_main_${STOP_DOCKER_HTTP_PORT}
    docker rm -f -v ${COMPOSE_PROJECT_NAME}_main_${STOP_DOCKER_HTTP_PORT}

    _save
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
    build
    start
}
# Open in web browser
function web() {
    source ${GANTRY_DATA_FILE}
    echo "Opening: http://$(_dockerHost):$DOCKER_HTTP_PORT"
    hash xdg-open && xdg-open http://$(_dockerHost):$DOCKER_HTTP_PORT || open http://$(_dockerHost):$DOCKER_HTTP_PORT
}
# Open terminal console on main docker container
function console() {
    source ${GANTRY_DATA_FILE}
    docker exec -it ${COMPOSE_PROJECT_NAME}_$(_mainContainer)_${DOCKER_HTTP_PORT} bash
}
# Remove all containers and delete volumes
function remove() {
    docker-compose rm -v
}
# Open psql client on db docker container
function psql() {
    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash -c "PGPASSWORD="\$POSTGRES_PASSWORD" psql -U postgres \$POSTGRES_DB"
}
# Open mysql client on db docker container
function mysql() {
    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash -c "MYSQL_PWD=\${MYSQL_ROOT_PASSWORD} mysql -uroot \${MYSQL_DATABASE}"
}
# Open terminal console on db docker container
function console_db() {
    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash
}

# Restore DB from file (filename.sql.gz)
function restore() {
    # TODO: postgres restore
    gunzip -c $1 > data/backup/backup.sql
    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash -c "echo \"drop database \$MYSQL_DATABASE;create database \$MYSQL_DATABASE\" | MYSQL_PWD=\$MYSQL_ROOT_PASSWORD mysql -uroot"
    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash -c "cat /backup/backup.sql | MYSQL_PWD=\$MYSQL_ROOT_PASSWORD mysql -uroot \$MYSQL_DATABASE"
    echo "DB Restore using $1"
}
# Create DB backup - gzipped sql (optional filename - no extension)
function backup() {
    # TODO: postgres backup
    [ -z $1 ] && local BU_FILE="backup-$(date +%Y%m%d%H%M)" || local BU_FILE="$1"
    docker exec ${COMPOSE_PROJECT_NAME}_db_1 bash -c "MYSQL_PWD=\$MYSQL_ROOT_PASSWORD mysqldump -uroot \$MYSQL_DATABASE > /backup/backup.sql"
    cat data/backup/backup.sql > ${BU_FILE}.sql
    gzip ${BU_FILE}.sql
    echo "DB Backup $BU_FILE"
}

function _join { local IFS="$1"; shift; echo "$*"; }

# run cap (capistrano) command inside docker container (neolao/capistrano:2.15.5) (extra args passed to cap command)
function cap() {
    local CMDS="cp -r /ssh /root/.ssh; chmod 0700 -R /root/.ssh; chown -R root.root /root/.ssh; cap $@";
    docker run -it --rm -v `pwd`:/source -v $SSH_DIR:/ssh neolao/capistrano:3.4.0 bash -i -c "$(echo $CMDS)"
}
# run cap (capistrano) command inside docker container (neolao/capistrano:2.15.5) (extra args passed to cap command)
function deploy() {
    docker run -it --rm -v `pwd`:/source -v $SSH_DIR:/ssh neolao/capistrano:3.4.0 bash -i -v -c "cp -r /ssh /root/.ssh; chmod 0700 -R /root/.ssh; chown -R root.root /root/.ssh; cap $1 deploy"
}
# run sass command inside docker container (rainsystems/sass:3.4.21) (extra args passed to sass command)
function sass() {
    docker run -it --rm -v `pwd`:/source rainsystems/sass:3.4.21 $@
}
# run bower command inside docker container (rainsystems/bower:1.7.2) (extra args passed to bower command)
function bower() {
    docker run -it --rm -v `pwd`:/source -v $BOWER_MAP rainsystems/bower:1.7.2  --config.analytics=false --allow-root $@
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

# tail the logs from the main container
function logs() {
    docker logs -f ${COMPOSE_PROJECT_NAME}_$(_mainContainer)_${DOCKER_HTTP_PORT}
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

function init() {


cat << 'EOF' > docker-compose.yml
#
main:
# build: .
# image: rainsystems/symfony
  volumes:
    - ./app:/var/www/app
    - ./src:/var/www/src
    - ./web:/var/www/web
    - ./composer.json:/var/www/composer.json
    - ./composer.lock:/var/www/composer.lock
  container_name: "${COMPOSE_PROJECT_NAME}_main_${DOCKER_HTTP_PORT}"
  ports:
    - "$DOCKER_HTTP_PORT:80"
  links:
    - db
  restart: always
  volumes_from:
    - data_shared
  environment:
  #
  # APP_ENV: "$APP_ENV"
data_shared:
#  image: php:5.4-apache
#  image: php:5.4-nginx
  volumes:
    - /var/www/app/cache
    - /var/www/app/sessions
    - /var/www/app/logs
  command: true
db:
# Uncomment your preferred DB
# image: mysql:5.7
# image: postgres:9.4
  restart: always
  volumes_from:
    - data_db
  environment:
    MYSQL_ROOT_PASSWORD: 62X05uX71rZlD2I
    MYSQL_DATABASE: symfony
  expose:
    - 3306
data_db:
# Uncomment matching DB from above
# image: mysql:5.7
# image: postgres:9.4
  volumes:
#    - /var/lib/mysql
#    - /var/lib/postgresql/data
  command: true


EOF

cat << EOF > gantry.sh
#!/bin/sh

export COMPOSE_PROJECT_NAME="project_name"

# Use unique ports for each project that will run simultansiously, mainly for dev env.
export DOCKER_HTTP_PORT="1090" # These should site behind a nginx reverse proxy/lb

# Set the default App Env
[ -z $APP_ENV ] && export APP_ENV="prod"
EOF

cat << EOF > entrypoint.sh
#!/usr/bin/env bash

## Build Project
## Symfony 2.*
# rm -rf app/cache/*
# composer install
# ./app/console assetic:dump
# rm -rf app/cache/*
# chown -R www-data.www-data app/cache app/logs app/var/sessions

# Start HTTP Server
apache2-foreground
EOF

}
# End of init()

function _exec() {
    docker exec -it ${COMPOSE_PROJECT_NAME}_$(_mainContainer)_${DOCKER_HTTP_PORT} $@
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
