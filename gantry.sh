#!/usr/bin/env bash

export GANTRY_VERSION="1.2"

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

    DOCKER_RUN_CMD="$(echo docker run -d -p ${DOCKER_HTTP_PORT}:80 \
      --name ${COMPOSE_PROJECT_NAME}_main_${DOCKER_HTTP_PORT} \
      $(_mainVolumes) \
      --restart always \
      $(_mainVolumesFrom) \
      $(_mainLinks) \
      $(_mainEnv) \
      ${COMPOSE_PROJECT_NAME}_main)"

    # Start
    eval "$DOCKER_RUN_CMD" || exit 1

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
    echo $(_mainContainer)
    docker exec -it $(_mainContainer) bash
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
    docker run -it --rm -v $(dirname $SSH_AUTH_SOCK):$(dirname $SSH_AUTH_SOCK) -e SSH_AUTH_SOCK=$SSH_AUTH_SOCK -v `pwd`:/app -v $SSH_DIR:/ssh rainsystems/cap:3.4.0 $@
}
# run composer command
function composer() {
    docker run -it --rm -v `pwd`:/app -v $SSH_DIR:/ssh composer/composer $@
}
# run cap (capistrano) command inside docker container (neolao/capistrano:2.15.5) (extra args passed to cap command)
function deploy() {
    docker run -it --rm -v `pwd`:/source -v $SSH_DIR:/ssh neolao/capistrano:3.4.0 bash -i -v -c "cp -r /ssh /root/.ssh; chmod 0700 -R /root/.ssh; chown -R root.root /root/.ssh; cap $1 deploy"
}
# run sass command inside docker container (rainsystems/sass:3.4.21) (extra args passed to sass command)
function sass() {
    docker run -it --rm -v `pwd`:/source rainsystems/sass:3.4.21 $@
}
# run behat command inside docker container (rainsystems/bower:1.7.2) (extra args passed to bower command)
function behat() {
    docker run -it --rm -v $PWD:/app -e TRAVIS_BUILD_NUMBER=$CI_BUILD_NUMBER -e SAUCE_USERNAME=$SAUCE_USERNAME -e SAUCE_ACCESS_KEY=$SAUCE_ACCESS_KEY rainsystems/behat:3.1.0 $@
}
# wraith
function wraith() {
    docker run -it --rm -v $PWD:/app wraith $@
}
# run bower command inside docker container (rainsystems/bower:1.7.2) (extra args passed to bower command)
function node() {
    docker run -it --rm -w="/app" --entrypoint node -v `pwd`:/app node:5-slim $@
}
# run bower command inside docker container (rainsystems/bower:1.7.2) (extra args passed to bower command)
function npm() {
    docker run -it --rm -w="/app" --entrypoint npm -v `pwd`:/app node:5-slim $@
}
# run bower command inside docker container (rainsystems/bower:1.7.2) (extra args passed to bower command)
function bower() {
    docker run -it --rm -v `pwd`:/app -v $BOWER_MAP rainsystems/bower:1.7.2  --config.analytics=false --allow-root $@
}
# run gulp commands
function gulp() {
    docker run -it --rm -v `pwd`:/app rainsystems/gulp $@
}

function pull () {
    case $1 in
        'behat')
            docker pull rainsystems/behat:3.1.0
        ;;
        'gulp')
            docker pull rainsystems/gulp
        ;;
        'bower')
            docker pull rainsystems/bower:1.7.2
        ;;
        'sass')
            docker pull rainsystems/sass:3.4.21
        ;;
        'cap')
            docker pull rainsystems/cap:3.4.0
        ;;
    esac
}

# print version
function version() {
    echo "Gantry v${GANTRY_VERSION} - Author Jason Hendry https://github.com/Jason-Hendry/gantry"
}
# Update gantry
function self-update() {
    # replace gantry file with github master copy
    sudo curl -o `which gantry` https://raw.githubusercontent.com/Jason-Hendry/gantry/master/gantry.sh
}
:
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
    docker logs -f $(_mainContainer)
}

# create fosUserBundle user (username email password role)
function create-user() {
    _exec ./app/console fos:user:create $1 $2 $3
    _exec ./app/console fos:user:promote $1 $4
}

function _mainContainerId {
    cat docker-compose.yml | grep -vE '^\s*$' | head -n1 | tr -d ':'
}
function _mainContainer {
    source ${GANTRY_DATA_FILE}
    echo ${COMPOSE_PROJECT_NAME}_main_${DOCKER_HTTP_PORT}
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
# image: wordpress:4.5.0-apache
  volumes:
#    WordPress Volumes
#    - $PWD/wordpress:/var/www/html
#    Symfony Volumes
#    - $PWD/app:/var/www/app
#    - $PWD/src:/var/www/src
#    - $PWD/web:/var/www/web
#    - $PWD/composer.json:/var/www/composer.json
#    - $PWD/composer.lock:/var/www/composer.lock
  container_name: "${COMPOSE_PROJECT_NAME}_main_${DOCKER_HTTP_PORT}"
  ports:
    - "$DOCKER_HTTP_PORT:80"
  links:
    - db
# Wordpress
#    - db:mysql
  restart: always
#  volumes_from:
#    - data_shared
  environment:
  # APP_ENV: "$APP_ENV"
  # SYMFONY_DATABASE_PASSWORD: "$DB_ROOT_PW"

#data_shared:
#  image: php:5.4-apache
#  image: php:5.4-nginx
#  volumes:
#    - /var/www/app/cache
#    - /var/www/app/sessions
#    - /var/www/app/logs
#  command: /bin/true

db:
# Uncomment your preferred DB
# image: mysql:5.7
# image: postgres:9.4
  restart: always
  volumes:
    # Required for gantry backup and restore commands
    - $PWD/data/backup:/backup
  volumes_from:
    - data_db
  environment:
    MYSQL_ROOT_PASSWORD: "$DB_ROOT_PW"
#    MYSQL_DATABASE: symfony
#    MYSQL_DATABASE: wordpress
  expose:
    - 3306
data_db:
# Uncomment matching DB from above
# image: mysql:5.7
# image: postgres:9.4
  volumes:
#    - /var/lib/mysql
#    - /var/lib/postgresql/data
  command: /bin/true

EOF

cat << EOF > gantry.sh
#!/bin/sh

export COMPOSE_PROJECT_NAME="project_name"

# Use unique ports for each project that will run simultansiously, mainly for dev env.
export DOCKER_HTTP_PORT="1090" # These should site behind a nginx reverse proxy/lb

# Set the default App Env
[ -z $APP_ENV ] && export APP_ENV="prod"

# Database Password for containers
[ -f secrets.sh ] && . secrets.sh
[ -z $DB_ROOT_PW ] && export DB_ROOT_PW="dev-password-not-secure"

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


function wordpress() {

    local PROJECT_NAME="`basename .`"
    local RAND_PORT="`cat /dev/urandom | tr -dc '0-9' | fold -w 4 | head -n 1`"
#    $ [ $((rand_port%2)) -eq 0 ] && echo "even"
    exit;

cat << EOF > docker-compose.yml
#
main:
  image: wordpress:4.5.0-apache
  volumes:
    - \$PWD/wordpress:/var/www/html
  container_name: "\$\{COMPOSE_PROJECT_NAME}_main_\$\{DOCKER_HTTP_PORT}"
  ports:
    - "\$DOCKER_HTTP_PORT:80"
  links:
    - db:mysql
  restart: always

db:
  image: mysql:5.7
  restart: always
  volumes:
    # Required for gantry backup and restore commands
    - \$PWD/data/backup:/backup
  volumes_from:
    - data_db
  environment:
    MYSQL_ROOT_PASSWORD: "\$DB_ROOT_PW"
    MYSQL_DATABASE: wordpress
  expose:
    - 3306
data_db:
  image: mysql:5.7
  volumes:
    - /var/lib/mysql
  command: /bin/true

EOF

cat << EOF > gantry.sh
#!/bin/sh

export COMPOSE_PROJECT_NAME="${PROJECT_NAME}"

# Use unique ports for each project that will run simultansiously, mainly for dev env.
export DOCKER_HTTP_PORT="1090" # These should site behind a nginx reverse proxy/lb

# Set the default App Env
[ -z $APP_ENV ] && export APP_ENV="prod"

# Database Password for containers
[ -f secrets.sh ] && . secrets.sh
[ -z $DB_ROOT_PW ] && export DB_ROOT_PW="dev-password-not-secure"

EOF

    mkdir wordpress
    mkdir data
    # Sticky User
    chmod 1755 wordpress data
}

function _exec() {
    docker exec -it $(_mainContainer) $@
}
# Convert docker-compose volumes into docker run volumes
function _mainVolumes() {
  cat docker-compose.yml | grep -A 50 -m 1 -E "^main:$" | grep -A50 -m1 'volumes:' | tail -n +2 | grep -B50 -m1 -E '^  [^ ]' | head -n -1 | tr -d ' ' | sed 's/^-/-v /' | tr "\n" ' '
}
function _mainVolumesFrom() {
  cat docker-compose.yml | grep -A 50 -m 1 -E "^main:$" | grep -A50 -m1 'volumes_from:' | tail -n +2 | grep -B50 -m1 -E '^  [^ ]' | head -n -1 | tr -d ' ' |  sed 's/^-/--volumes-from \"\$\{COMPOSE_PROJECT_NAME\}_/' | sed 's/$/_1\"/' | tr "\n" ' '
}
function _mainLinks() {
  cat docker-compose.yml | grep -A 50 -m 1 -E "^main:$" | grep -A50 -m1 'links:' | tail -n +2 | grep -B50 -m1 -E '^  [^ ]' | head -n -1 | tr -d ' ' |  sed 's/^-/--link \"\$\{COMPOSE_PROJECT_NAME\}_/' | sed -E "s/\}_(.*)$/\}_\1_1:\1\"/" | tr "\n" ' '
}
function _mainEnv() {
  cat docker-compose.yml | grep -A 50 -m 1 -E "^main:$" | grep -A50 -m1 'environment:' | tail -n +2 | grep -B50 -m1 -E '^  [^ ]' | head -n -2 | tr -d ' ' | tr ':' '=' | sed 's/^/-e /' | tr "\n" ' '
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
