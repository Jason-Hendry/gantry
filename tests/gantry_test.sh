#!/usr/bin/env bash

. ../gantry.sh

function testComposerInit() {
    gantry composer init
    assert "[ -f \"composer.json\" ]" "composer.json file expected"
    assert "[ -d \".composer_cache\" ]" "composer cache dir expected"
    rm -rf composer.json .composer_cache
    assert "[ ! -f \"composer.json\" ]" "Clean up failed"
    assert "[ ! -d \".composer_cache\" ]" "Clean up failed"
}

function testCapInstall() {
    gantry cap install
    assert "[ -f \"Capfile\" ]" "Capfile file expected"
    assert "[ -d \"config\" ]" "composer cache dir expected"
    assert "[ -d \"lib\" ]" "composer cache dir expected"
    rm -rf Capfile config lib
    assert "[ ! -f \"Capfile\" ]" "Clean up failed"
    assert "[ ! -d \"config\" ]" "Clean up failed"
    assert "[ ! -d \"lib\" ]" "Clean up failed"
}

