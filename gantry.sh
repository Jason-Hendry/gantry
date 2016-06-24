#!/usr/bin/env bash

export GANTRY_VERSION="1.3"

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

[ -z $GANTRY_PMA_PORT ] && export GANTRY_PMA_PORT=9990
[ -z $GANTRY_PMA_PORT_PROD ] && export GANTRY_PMA_PORT_PROD=9991

export GANTRY_DATA_FILE="$HOME/.gantry/${COMPOSE_PROJECT_NAME}_${GANTRY_ENV}"

## Saves you current state as sourcable variables in bash script
function _save() {
    echo '#!/usr/bin/env bash' > ${GANTRY_DATA_FILE}
    echo "export DOCKER_HTTP_PORT=\"${DOCKER_HTTP_PORT}\"" >> ${GANTRY_DATA_FILE}
    echo "export COMPOSE_PROJECT_NAME=\"${COMPOSE_PROJECT_NAME}\"" >> ${GANTRY_DATA_FILE}
}
# Start Docker Containers
function start() {

    echo "Started (Env: ${APP_ENV})";

    ## If db is not started run build and run main start
    if [ -z "$(docker ps | grep -E "\b${COMPOSE_PROJECT_NAME}_db_1\b")" ]; then
        docker-compose up -d
        _save
        web
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

    docker-compose scale main=2

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
    stop
    start
}
# Open in web browser (or default application for http protocol)
function web() {
    source ${GANTRY_DATA_FILE}
    echo "Opening: http://$(_dockerHost):${DOCKER_HTTP_PORT}"

    # Try Linux xdg-open otherwise OSX open
    xdg-open http://$(_dockerHost):$DOCKER_HTTP_PORT/ 2> /dev/null > /dev/null || \
    open http://$(_dockerHost):$DOCKER_HTTP_PORT// 2> /dev/null > /dev/null
}
# Open terminal console on main docker container
function console() {
    source ${GANTRY_DATA_FILE}
    echo $(_mainContainer)
    docker exec -it $(_mainContainer) bash
}
# Remove all containers and delete volumes (including DB data and uploaded files)
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


# Open PHPMyAdmin
function pma() {
    echo "Open PHPMyAdmin for ${COMPOSE_PROJECT_NAME}_db_1";

    # Try Linux xdg-open otherwise OSX open
    xdg-open http://$(_dockerHost):${GANTRY_PMA_PORT}/ 2> /dev/null > /dev/null || \
    open http://$(_dockerHost):${GANTRY_PMA_PORT}// 2> /dev/null > /dev/null

    docker run --rm \
        --link "${COMPOSE_PROJECT_NAME}_db_1:db" \
        -e "PMA_HOST=db" \
        -e "PMA_PORT=3306" \
        -e "PMA_USER=root" \
        -e "PMA_PASSWORD=${DB_ROOT_PW}" \
        -p $GANTRY_PMA_PORT:80 \
        phpmyadmin/phpmyadmin

}
# Open PHPMyAdmin on prod
function pma-prod() {
    # Try Linux xdg-open otherwise OSX open
    xdg-open http://$(_dockerHost):${GANTRY_PMA_PORT_PROD}/ 2> /dev/null > /dev/null || \
    open http://$(_dockerHost):${GANTRY_PMA_PORT_PROD}// 2> /dev/null > /dev/null

    docker run --rm \
        -e "PMA_HOST=${DB_PROD}" \
        -e "PMA_PORT=3306" \
        -e "PMA_USER=${DB_PROD_USER}" \
        -e "PMA_PASSWORD=${DB_PROD_PASS}" \
        -p $GANTRY_PMA_PORT_PROD:80 \
        phpmyadmin/phpmyadmin
}

# Restore DB from file (filename.sql.gz)
function restore-prod() {
    # TODO: postgres restore
    gunzip -c $1 > data/backup/backup.sql
    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash -c "echo \"drop database IF EXISTS \$MYSQL_DATABASE;create database \$MYSQL_DATABASE\" | mysql -h $DB_PROD -p -u$DB_PROD_USER"
    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash -c "cat /backup/backup.sql | mysql -h $DB_PROD -u$DB_PROD_USER -p \$MYSQL_DATABASE"
    echo "DB Restore using $1"
}
# Create DB backup - gzipped sql (optional filename - no extension)
function backup-prod() {
    # TODO: postgres backup
    [ -z $1 ] && local BU_FILE="backup-$(date +%Y%m%d%H%M)" || local BU_FILE="$1"
    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash -c "mysqldump -h $DB_PROD -p -u$DB_PROD_USER \$MYSQL_DATABASE > /backup/backup.sql"
    cat data/backup/backup.sql > ${BU_FILE}.sql
    gzip ${BU_FILE}.sql
    echo "DB Backup $BU_FILE"
}

# Open mysql client to production (RDS)
function mysql-prod() {
    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash -c "mysql -h $DB_PROD -p -u$DB_PROD_USER"
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

# run sql from file in mysql (filename.sql)
function sql() {
    # TODO: postgres restore
    cat $1 > data/backup/backup.sql
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

# run cap (capistrano) command inside docker container (neolao/capistrano:2.15.5) (extra args passed to cap command)
function cap() {
    [ ! -d "config" ] && mkdir config && chmod 1755 config
    docker run -it --rm \
        -e SSH_AUTH_SOCK=$SSH_AUTH_SOCK \
        -e GANTRY_UID="`id -u`" \
        -e GANTRY_GID="`id -g`" \
        -v $(dirname $SSH_AUTH_SOCK):$(dirname $SSH_AUTH_SOCK) \
        -v $HOME/.ssh:/ssh \
        -v `pwd`:/app \
        -v $SSH_DIR:/ssh \
        rainsystems/cap:3.4.0 $@
}
# run ansible command
function ansible() {
    [ -f "aws.sh" ] && . aws.sh
    docker run -it --rm -v $(dirname $SSH_AUTH_SOCK):$(dirname $SSH_AUTH_SOCK) \
                        -v $HOME/.ssh:/ssh \
                        -v `pwd`:/app \
                        -v $SSH_DIR:/ssh \
                        -e EC2_INV="TRUE" \
                        -e SSH_AUTH_SOCK=$SSH_AUTH_SOCK \
                        -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
                        -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
                        rainsystems/ansible $@
}
# run playbook-playbook command
function playbook() {
    [ -f "aws.sh" ] && . aws.sh
    docker run -it --rm -v $(dirname $SSH_AUTH_SOCK):$(dirname $SSH_AUTH_SOCK) \
                        -v $HOME/.ssh:/ssh \
                        -v `pwd`:/app \
                        -v $SSH_DIR:/ssh \
                        -e PLAYBOOK="TRUE" \
                        -e EC2_INV="TRUE" \
                        -e SSH_AUTH_SOCK=$SSH_AUTH_SOCK \
                        -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
                        -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
                        rainsystems/ansible -c ssh "$@"
}
function ansible-console() {
    [ -z "$EDITOR" ] && export EDITOR='vim'
    [ -f "aws.sh" ] && . aws.sh
    [ -f "config/ec2.py" ] && export EC2='-e EC2_INV="TRUE"'
    docker run -it --rm -v $(dirname $SSH_AUTH_SOCK):$(dirname $SSH_AUTH_SOCK) \
                        -v $HOME/.ssh:/ssh \
                        -v `pwd`:/app \
                        -v $SSH_DIR:/ssh \
                        -e DEBUG="TRUE" \
                        $EC2 \
                        -e SSH_AUTH_SOCK=$SSH_AUTH_SOCK \
                        -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
                        -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
                        -e EDITOR=$EDITOR \
                        rainsystems/ansible "$@"
}
function ansible-vault() {
    [ -z "$EDITOR" ] && export EDITOR='vim'
    [ -f "aws.sh" ] && . aws.sh
    docker run -it --rm -v $(dirname $SSH_AUTH_SOCK):$(dirname $SSH_AUTH_SOCK) \
                        -v $HOME/.ssh:/ssh \
                        -v `pwd`:/app \
                        -v $SSH_DIR:/ssh \
                        -e VAULT="TRUE" \
                        -e EC2_INV="TRUE" \
                        -e SSH_AUTH_SOCK=$SSH_AUTH_SOCK \
                        -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
                        -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
                        rainsystems/ansible "$@"
}
# run composer command
function composer() {
    docker run --rm \
        -e GANTRY_UID="`id -u`" \
        -e GANTRY_GID="`id -g`" \
        -v `pwd`:/app \
        -v $SSH_DIR:/ssh \
        rainsystems/composer $@
}
# run sass command inside docker container (rainsystems/sass:3.4.21) (extra args passed to sass command)
function sass() {
    docker run -it --rm \
        -e GANTRY_UID="`id -u`" \
        -e GANTRY_GID="`id -g`" \
        -v `pwd`:/source \
        rainsystems/sass:3.4.21 $@
}
# run behat command inside docker container (rainsystems/bower:1.7.2) (extra args passed to bower command)
function behat() {
    docker run -it --rm \
        -v $PWD:/app \
        -e GANTRY_UID="`id -u`" \
        -e GANTRY_GID="`id -g`" \
        -e TRAVIS_BUILD_NUMBER=$CI_BUILD_NUMBER \
        -e SAUCE_USERNAME=$SAUCE_USERNAME \
        -e SAUCE_ACCESS_KEY=$SAUCE_ACCESS_KEY \
        rainsystems/behat:3.1.0 $@
}
# wraith
function wraith() {
    docker run -it --rm \
        -e GANTRY_UID="`id -u`" \
        -e GANTRY_GID="`id -g`" \
        -v $PWD:/app \
        wraith $@
}
# run bower command inside docker container (rainsystems/bower:1.7.2) (extra args passed to bower command)
function node() {
    docker run -it --rm \
        -w="/app" \
        --entrypoint node \
        -v `pwd`:/app node:5-slim $@
}
# run bower command inside docker container (rainsystems/bower:1.7.2) (extra args passed to bower command)
function npm() {
    mkdir -p .npm
    mkdir -p .npm_config
    docker run -it --rm -u `id -u`:`id -g` \
        -w="/app" \
        --entrypoint npm \
        -v `pwd`:/app \
        -v `pwd`/.npm:/.npm \
        -v `pwd`/.npm_config:/.config \
        node:5-slim $@
}
# run bower command inside docker container (rainsystems/bower:1.7.2) (extra args passed to bower command)
function bower() {
    [ -d "bower_components" ] || mkdir bower_components
    docker run --rm \
        -e GANTRY_UID="`id -u`" \
        -e GANTRY_GID="`id -g`" \
        -e BOWER_UID="`id -u`" \
        -e BOWER_GID="`id -g`" \
        -v `pwd`:/app \
        rainsystems/bower:1.7.2  \
        --config.analytics=false --allow-root $@
}
# run gulp commands
function gulp() {
    docker run -it --rm \
        -e GANTRY_UID="`id -u`" \
        -e GANTRY_GID="`id -g`" \
        -v `pwd`:/app \
        rainsystems/gulp $@
}

function pull () {
    if [ -n "$1" ]; then
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
    else
        echo "Pulling all gantry images"
        docker pull rainsystems/behat:3.1.0
        docker pull rainsystems/gulp
        docker pull rainsystems/bower:1.7.2
        docker pull rainsystems/sass:3.4.21
        docker pull rainsystems/cap:3.4.0
    fi
}

# Print version
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




##### Symfony Commands #######

# run symfony console (./app/console ...)
function symfony() {
    _exec ./app/console $@
}
# run symfony console (./app/console ...)
function symfony-schema() {
    _exec ./app/console doctrine:schema:update --dump-sql

    if [ "$1" == "-f" ]; then
        _exec ./app/console doctrine:schema:update --force
    else
        read -r -p "Make this changes now? [y/N] " response
        if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]
        then
            _exec ./app/console doctrine:schema:update --force
        fi
    fi
}
# run symfony schema update
function sf-schema() {
    _exec console doctrine:schema:update --dump-sql

    if [ "$1" == "-f" ]; then
        _exec console doctrine:schema:update --force
    else
        read -r -p "Make this changes now? [y/N] " response
        if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]
        then
            _exec console doctrine:schema:update --force
        fi
    fi
}
# run symfony schema update
function sf-entity() {
    _exec console doctrine:generate:entity
}
# run symfony schema update
function sf-crud() {
    _exec console doctrine:generate:crud
}


# tail the logs from the main container
function logs() {
    docker logs -f $(_mainContainer)
}

# create fosUserBundle user (username email password role)
function create-user() {
    _exec console fos:user:create $1 $2 $3
    _exec console fos:user:promote $1 $4
}

# Grab and tare gzip a folder from the main container
function grab() {
    mkdir $2
    docker cp $(_mainContainer):$1 $2
    tar zcvpf $2.tar.gz $2
    rm -rf $2
}
# Put the content of a tar.gz into the main docker container
function put() {
    tar zxvpf $1
    local folderName="`echo $1 | sed 's/\.tar\.gz$//'`"
    docker cp $folderName/. $(_mainContainer):$2
    rm -rf $folderName
}


function cordova() {
    mkdir -p .cordova
    mkdir -p .cordova_config
    mkdir -p .cordova_npm
    docker run \
        --rm -it \
        -u `id -u`:`id -g` \
        -v $PWD:/app \
        -v $PWD/.cordova:/.cordova \
        -v $PWD/.cordova_config:/.config \
        -v $PWD/.cordova_npm:/.npm \
        -w /app \
        beevelop/cordova:latest cordova $@
}

# Pull all the wordpress file and db changes from staging  (Warning Replaces all local changes)
function wp-pull() {
    cat << EOF > /tmp/wp-pull.sh
#!/bin/bash

if [ "\$1" = "cleanup" ]; then
    cd /app/${COMPOSE_PROJECT_NAME}/current
    rm gantry-staging-pull*
    rm /tmp/wp-pull.sh
    exit;
fi;


cd /app/${COMPOSE_PROJECT_NAME}/current && \
    gantry backup gantry-staging-pull && \
    gantry grab /var/www/html/wp-content/uploads gantry-staging-pull-uploads
# Self cleanup
rm /tmp/wp-pull.sh
EOF
    scp /tmp/wp-pull.sh $STAGING_HOST:/tmp/wp-pull.sh && \
        ssh $STAGING_HOST 'bash /tmp/wp-pull.sh' && \
        scp $STAGING_HOST:/app/${COMPOSE_PROJECT_NAME}/current/gantry-staging-pull* ./ && \
        gantry restore gantry-staging-pull.sql.gz && \
        gantry put gantry-staging-pull-uploads.tar.gz /var/www/html/wp-content/uploads/ && \
        ssh $STAGING_HOST 'bash /tmp/wp-pull.sh cleanup'
    rm /tmp/wp-pull.sh
    wp-host
}

# Push all the local wordpress file and db changes to staging (Warning Replaces all staging changes)
function wp-push() {
    wp-host $STAGING_DOMAIN && \
        backup gantry-staging-push &&\
        gantry grab /var/www/html/wp-content/uploads gantry-staging-push-uploads &&\
        scp gantry-staging-push* $STAGING_HOST:/app/${COMPOSE_PROJECT_NAME}/current/

    cat << EOF > /tmp/wp-push.sh
#!/bin/bash

cd /app/${COMPOSE_PROJECT_NAME}/current && \
    gantry restore gantry-staging-pull.sql.gz" && \
    gantry put gantry-staging-pull-uploads.tar.gz /var/www/html/wp-content/uploads

cd /app/${COMPOSE_PROJECT_NAME}/current
rm gantry-staging-push*
rm /tmp/wp-push.sh

EOF
    scp /tmp/wp-push.sh $STAGING_HOST:/tmp/wp-push.sh && \
        ssh $STAGING_HOST 'bash /tmp/wp-push.sh'
    rm /tmp/wp-push.sh gantry-staging-push*

    wp-host

}

# Change the hostname for wordpress
function wp-host() {

    [ -z "$1" ] && local url="$(_dockerHost):${DOCKER_HTTP_PORT}"
    [ -n "$1" ] && local url="$1"

    # TODO: postgres restore
    cat << EOF > data/backup/backup.sql
UPDATE wp_options SET option_value="http://$url/" WHERE option_name="siteurl";
UPDATE wp_options SET option_value="http://$url/" WHERE option_name="home";
EOF

    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash -c "cat /backup/backup.sql | MYSQL_PWD=\$MYSQL_ROOT_PASSWORD mysql -uroot \$MYSQL_DATABASE"
    echo "Set host and site url to http://$url/"
}

# Change the hostname for wordpress
function wp-host-prod() {

    [ -z "$1" ] && local url="$(_dockerHost):${DOCKER_HTTP_PORT}"
    [ -n "$1" ] && local url="$1"

    # TODO: postgres restore
    cat << EOF > data/backup/backup.sql
UPDATE wp_options SET option_value="http://$url/" WHERE option_name="siteurl";
UPDATE wp_options SET option_value="http://$url/" WHERE option_name="home";
EOF

    docker exec -it ${COMPOSE_PROJECT_NAME}_db_1 bash -c "cat /backup/backup.sql | mysql -h$DB_PROD -u$DB_PROD_USER -p $DB_PROD_NAME"
    echo "Set host and site url to http://$url/"
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

# Setup docker / gantry components for symfony 2.x Project
function init-symfony() {
    local PROJECT_NAME="`basename .`"

    docker ps --format "{{.Ports}}-{{.Names}}" | sed 's/0.0.0.0://' | grep '\->' | cut -d\- -f1,3 | sed 's/-/: /'
    read -p "Enter an unused even port between 1000 and 9999: " portNum

cat << 'EOF' > docker-compose.yml
#
main:
  image: rainsystems/symfony
  volumes:
    - $PWD/app:/var/www/app
    - $PWD/src:/var/www/src
    - $PWD/web:/var/www/web
    - $PWD/composer.json:/var/www/composer.json
    - $PWD/composer.lock:/var/www/composer.lock
  container_name: "${COMPOSE_PROJECT_NAME}_main_${DOCKER_HTTP_PORT}"
  ports:
    - "$DOCKER_HTTP_PORT:80"
  links:
    - db
  restart: always
  volumes_from:
    - data_shared
  environment:
    APP_ENV: "$APP_ENV"
    SYMFONY_DATABASE_PASSWORD: "$DB_ROOT_PW"

data_shared:
  image: rainsystems/symfony
  volumes:
    - /var/www/app/cache
    - /var/www/app/sessions
    - /var/www/app/logs
  command: /bin/true

db:
  image: postgres:9.4
  restart: always
  volumes:
    # Required for gantry backup and restore commands
    - $PWD/data/backup:/backup
  volumes_from:
    - data_db
  environment:
    MYSQL_ROOT_PASSWORD: "$DB_ROOT_PW"
    MYSQL_DATABASE: symfony
  expose:
    - 3306
data_db:
  image: postgres:9.4
  volumes:
    - /var/lib/postgresql/data
  command: /bin/true
EOF

cat << EOF > gantry.sh
#!/bin/sh

export COMPOSE_PROJECT_NAME="${PROJECT_NAME}"

# Use unique ports for each project that will run simultansiously, mainly for dev env.
export DOCKER_HTTP_PORT="${portNum}" # These should site behind a nginx reverse proxy/lb

# Set the default App Env
[ -z \$APP_ENV ] && export APP_ENV="prod"

# Database Password for containers
[ -f secrets.sh ] && . secrets.sh
[ -z \$DB_ROOT_PW ] && export DB_ROOT_PW="dev-password-not-secure"

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


function init-wordpress() {

    local PROJECT_NAME="`basename .`"
    docker ps --format "{{.Ports}}-{{.Names}}" | sed 's/0.0.0.0://' | grep '\->' | cut -d\- -f1,3 | sed 's/-/: /'
    read -p "Enter an unused even port between 1000 and 9999: " portNum

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
export DOCKER_HTTP_PORT="${portNum}" # These should site behind a nginx reverse proxy/lb

# Set the default App Env
[ -z \$APP_ENV ] && export APP_ENV="prod"

# Database Password for containers
[ -f secrets.sh ] && . secrets.sh
[ -z \$DB_ROOT_PW ] && export DB_ROOT_PW="dev-password-not-secure"

EOF

    mkdir wordpress
    mkdir data
    # Sticky User
    chmod 1755 wordpress data
}

function _exec() {
    docker exec $_GANTRY_EXEC_OPTION -it $(_mainContainer) $@
}
# Reset permissions to my user
function reset-owner() {
    _exec chown -R `id -u`.`id -g` $1
}

# Convert docker-compose volumes into docker run volumes
function _mainVolumes() {
  cat docker-compose.yml | grep -A 50 -m 1 -E "^main:$" | grep -A50 -m1 'volumes:' | tail -n +2 | grep -B50 -m1 -E '^  [^ ]' | head -n -1 | tr -d ' ' | sed 's/^-/-v /' | tr "\n" ' '
}
function _mainVolumesFrom() {
  cat docker-compose.yml | grep -A 50 -m 1 -E "^main:$" | grep -A50 -m1 'volumes_from:' | tail -n +2 | grep -B50 -m1 -E '^  [^ ]' | head -n -1 | tr -d ' ' |  sed 's/^-/--volumes-from \"\$\{COMPOSE_PROJECT_NAME\}_/' | sed 's/$/_1\"/' | tr "\n" ' '
}
function _mainLinks() {
  _parse_yaml docker-compose.yml "dc_"
  echo $dc_main_links
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


function _parse_yaml() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

# Run Command
$1 ${@:2}
