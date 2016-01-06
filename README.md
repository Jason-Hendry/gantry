# Gantry

Gantry provides a standard set of tools and shortcuts for managing the development workflow using docker, php, postgres and mysql for 
building symfony2, wordpress and drupal sites. 

## Requires

* docker
* docker-compose
* docker enviroment variables

## Docker ENV

```sh
# ~/.profile
eval "$(docker-machine env default)"
```

## Usage

Run gantry without arguments for a list of available commands
```sh
gantry
```

### Starting, Stopping and rebuilding Docker containers
```sh
gantry start
gantry stop
gantry restart
gantry rebuild
```

## TODO
- [ ] Command Validation
- [ ] Auto-Complete
- [ ] Multi enviroment configurations via an INI file
- [ ] Use getopts to parse CLI Arguments

## Tested on

* OSX 10.11
* Ubuntu 14.04

