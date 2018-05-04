dirHub
===
A trackHub configurator with directory structure projection.

dirHub is a too to assist configuration of [trackHub](https://genome.ucsc.edu/goldenpath/help/trackDb/trackDbHub.html) by mapping a directory structure of data files to a layer of tracks. Check [demo server](http://dirHub.herokuapp.com) on Heroku

***Note this is still under development (alpha ver.)***

Usage (web application)
---

installation

```
$ git clone https://github.com/hkawaji/dirHub.git 
$ cd dirHub
$ bundle install --path vendor/bundle
```

launch the web application

```
$ bundle exec ruby dirHub.rb --webapp
```

Now you are ready to access the web interface, for example http://YOURHOST:4567


Usage (command line tool)
---

installation

```
$ git clone ###
$ cd ###
```


basic usage

```
$ cd ${DATA_DIR}
$ ${PROGRAM_DIR}/dirHub.rb --input-trackfiles=. --output-config-dir=.
```

help message

```
$ ${PROGRAM_DIR}/dirHub.rb --help
```


Requirements
---
* ruby (tested in version 2.3)
* trackHub compatible genome browser (tested on the UCSC Genome Browser / trackHub definition v2)


Author, copyright, and license
---
This software is written by Hideya Kawaji. Copyright (c) 2018 RIKEN.
Distributed under Apache License 2.0.