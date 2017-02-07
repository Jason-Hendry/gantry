#!/usr/bin/env bash

docker run --rm \
        -e "PMA_HOST=us-cdbr-azure-southcentral-f.cloudapp.net" \
        -e "PMA_PORT=3306" \
        -e "PMA_USER=b720e1666c8258" \
        -e "PMA_PASSWORD=b65e5b60" \
        -p 9992:80 \
        phpmyadmin/phpmyadmin