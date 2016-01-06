#!/usr/bin/env bash

export EDITOR=vim
INSTALL_PREFIX="/usr/local/sbin"

if [ -n "$(git status)" ]; then
    git commit -a
    git push
fi

cp gantry.sh ${INSTALL_PREFIX}/gantry