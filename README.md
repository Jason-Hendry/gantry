# Gantry

Gantry provides a standard set of tools and shortcuts for managing the development workflow using docker, php, postgres and mysql for 
building PHP applications - focusing on symfony2, wordpress and drupal sites. 

## Requires

* docker
* docker-compose
* docker enviroment variables

### Docker ENV

```sh
# ~/.profile
eval "$(docker-machine env default)"
```

## Usage

Run gantry without arguments for a list of available commands
```sh
gantry
```

### Starting, Stopping and Rebuilding Docker containers
```sh
gantry start
gantry stop
gantry restart
gantry rebuild
```

## Complementary tools

Provide version consistancy amoung developers

```sh
# Run sass command in standalone ruby+sass container
gantry sass --watch sass/file.sass:css/file.css

# Run bower command in standalone node+bower container
gantry bower install angularjs

# Run capistrano command in standalone ruby+cap container
gantry cap install
gantry cap production deploy
```

## TODO
- [ ] Command Validation
- [ ] Auto-Complete
- [ ] Multi enviroment configurations via an INI file
- [ ] Use getopts to parse CLI Arguments

## Tested on

* OSX 10.11
* Ubuntu 14.04

