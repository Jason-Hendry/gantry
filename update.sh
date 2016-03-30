#!/usr/bin/env bash

export EDITOR=vim
INSTALL_PREFIX="/usr/local/bin"

if [ -n "$(git status)" ]; then
    git commit -a
    git push
fi

if [ -n "$(which gantry)" ]; then
    sudo cp gantry.sh `which gantry`
    sudo chmod +x `which gantry`
else
    sudo cp gantry.sh ${INSTALL_PREFIX}/gantry
    sudo chmod +x ${INSTALL_PREFIX}/gantry
fi

