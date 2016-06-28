#!/usr/bin/env bash

[ -f "bash_unit" ] || curl -o bash_unit  https://raw.githubusercontent.com/pgrange/bash_unit/master/bash_unit

./bash_unit gantry_test.sh

