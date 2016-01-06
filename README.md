# Gantry

Gantry provides a standard set of tools and shortcuts for managing the development workflow using docker, php, postgres and mysql for 
building symfony2, wordpress and drupal sites. 

## Requires

* docker
* docker-compose
* docker enviroment variables

## Docker ENV

```sh
# 
eval "$(docker-machine env default)"
```

## Usage

Run gantry without arguments for a list of available commands
```
gantry
```

## TODO
- [ ] Command Validation
- [ ] Auto-Complete
- [ ] Multi enviroment configurations via an INI file
- [ ] Use getopts to parse CLI Arguments

## Tested on

* OSX 10.11
* Ubuntu 14.04

