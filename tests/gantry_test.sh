#!/usr/bin/env bash

. ../gantry.sh

function testComposerInit() {
    composer init
    assert "[ -f \"composer.json\" ]" "composer.json file expected"
    assert "[ -d \".composer_cache\" ]" "composer cache dir expected"
    rm -rf composer.json .composer_cache
    assert "[ ! -f \"composer.json\" ]" "Clean up failed"
    assert "[ ! -d \".composer_cache\" ]" "Clean up failed"
}

function testCapInstall() {
    cap install >> test.log
    assert "[ -f \"Capfile\" ]" "Capfile file expected"
    assert "[ -d \"config\" ]" "composer cache dir expected"
    assert "[ -d \"lib\" ]" "composer cache dir expected"
    rm -rf Capfile config lib
    assert "[ ! -f \"Capfile\" ]" "Clean up failed"
    assert "[ ! -d \"config\" ]" "Clean up failed"
    assert "[ ! -d \"lib\" ]" "Clean up failed"
}

function testSass() {
    sass test.scss:test.css
    assert "[ -f \"test.css\" ]" "test.css file expected"
    rm -rf test.css test.css.map .sass-cache
    assert "[ ! -f \"test.css\" ]" "Clean up failed"
}

function testNpmInit() {
    npm init -f >> test.log
    assert "[ -f \"package.json\" ]" "package.json file expected"
    rm -rf package.json
    assert "[ ! -f \"package.json\" ]" "Clean up failed"
}
# Needs interactive prompts
#function testBowerInit() {
#    bower init
#    assert "[ -f \"bower.json\" ]" "bower.json file expected"
#    rm -rf bower.json bower_components
#    assert "[ ! -f \"bower.json\" ]" "Clean up failed"
#    assert "[ ! -d \"bower_components\" ]" "Clean up failed"
#}