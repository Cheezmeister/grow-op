#!/usr/bin/env coffee -l

# Overview

Grow-Op downloads MacOS Applications and stuffs them where they belong.

It is inspired by, and complements, the excellent [Homebrew](http://brew.sh)
project, which explicitly prefers to stick to command-line-land.

It is horrifically untested and might eat your computer. Use at your own 
risk. Don't say I didn't warn you.

## Seeds

A seed is a yaml file.

It lists stuff to download in the form of `AppName: http://some.url/to/hit`
My seed looks something like this:

    """
    BetterTouchTool: "http://bettertouchtool.net/BetterTouchTool.zip"
    Clementine: "https://github.com/clementine-player/Clementine/releases/download/1.2.2/clementine-1.2.2.dmg"
    Enjoyable: "https://yukkurigames.com/enjoyable/Enjoyable-1.2.zip"
    """

## Strains

A strain is a git repository containing this script and a seed. This 
repository is my strain. You are encouraged to fork and share your own.
Show me what I've been missing.

## Usage

Once you've written your seed, `$ grow` should get the job done. If you 
need to get fancy, see [Parameters](#parameters), below.

    usage = """
    Usage: grow [--seedfile=FILE] [--temp-dir=DIR] [--dest=DIR]
    """

## Why?

I prefer to stick to command-line-land, too. However, OSX has this 
annoying habit of omitting basic quality-of-life OS features. The typical
solution to these omissions is to go install some wack third-party GUI
that probably ships as a ZIP, but might be an installer hidden inside 
of a DMG hidden inside a ZIP that can be found in the deepest recesses 
of the internet. Like, too many clicks, man.

# Implementation

`grow` is essentially a thinnish wrapper to `wget` and `7z` though 
you could swap them out for something else if you really wanted.

For that matter, this could have been a shell script. It probably should
have, but I have this soft spot for pretty things.

## Dependencies

For a while I tried to implement this on vanilla Node with no 3rd-party 
modules. That didn't last very long.

Yargs is nice to have. If push came to shove I could probably jettison it
and read parameters from the seed only.

    yargs = require 'yargs'

The seed is technically read in as YAML. Totally feasible to do some 
splitting and cutting for the degenerate format we actually use, but I 
don't really want to deal with that.

    yaml = require 'js-yaml'

I don't know why Node doesn't provide a synchronous exec out of the box.
Doesn't seem likely someone would accidentally use it where they should
have used the (default) async version. C'est la vie.

    shjs = require 'shelljs'
    cp = require 'child_process'

We need to mess with the filesystem, obviously.

    fs = require 'fs'

You probably have `wget` and `7zip` installed already. 
If not, we'll brew it for ya.

    shjs.which "wget" || shjs.exec "brew install wget"
    shjs.which "7z" || shjs.exec "brew install p7zip"

## Syssy

This is a silly little snippet I've taken to calling syssy to save on
typing when hacking out frankenscripts. It's a work in progress.

    _ = console.log
    $ = (str, errorHandler) ->
      result = shjs.exec(str, silent: true)
      result.output.split('\n').map (l) -> _ "> #{l}"
      if (result.code && errorHandler)
        errorHandler(result.code, stdout,)

## Parameters

    args = yargs
      .usage usage

Seed location:

      .alias        's',  'seedfile'
      .default      's',  'seed.yaml'
      .describe     's',  'Specify the seed to use'

Temporary folder:

      .alias        't',  'temp-dir'
      .default      't',  "/tmp/grow#{Date.now()}"
      .describe     't',  'Specify the temp dir'

App Destination:

      .alias        'd',  'dest'
      .default      'd',  '/Applications'
      .describe     'd',  'Destination for Applications'

      .example      '$0 -s ~/.Seedfile',    'Read from .Seedfile in the home directory'
      .argv

    params =
      seedfile: args.seedfile
      tempDir: args.tempDir
      appDestination: args.dest

## Application


The `Gardener` object provides a sort of poor man's promise mechanism
and separates the script into four(ish) steps: 

    Gardener =

* grow, which reads the seed and acts on it
* download, which gets a URL
* findFile, which looks for a single file in a given directory
* processFile, which looks at a file's extension and decides what to do with it

### Read the Seed

      grow: ->
        data = yaml.safeLoad fs.readFileSync "./#{params.seedfile}"
        apps = ({name: key, url: value} for key, value of data)
        apps.map (app) ->
          location = "#{params.tempDir}/#{app.name}"
          Gardener.download app
            
### Download Applications

Download a given app to temp.

Hypothetically I don't need to delegate this part to `wget`. Realistically
it does some nice things that I'm too lazy to implement directly.
For example, it transparently handles HTTP 302 `FOUND`.

This is the only place shell commands are run async. May as well 
parallelize what we can.

      download: (app) ->
        location = "#{params.tempDir}/#{app.name}"
        _ "Fetching #{app.name} from #{app.url} to #{location}"
        cp.exec "wget --directory-prefix='#{location}' #{app.url}", (err) ->
          if err
            _ err
          else
            Gardener.findFile location, app

### Locate the Downloaded File

Because we don't necessarily know the filename until it drops. 
This prevents having to guess.

      findFile: (directory, app) ->
        _ "Reading #{directory}"
        fs.readdir directory, (err, files) ->
          if err
            return _ err
          if files.length == 0
            return _ "Didn't find anything in #{directory}"
          if files.length > 1
            return _ "Got too many files (#{files.length}), ignoring: #{files.join ','}"
          Gardener.processFile "#{directory}/#{files[0]}", app

### Do Stuff with Files

We're pretty dumb and just look at the extension to decide what to do.

I think that's okay.

      processFile: (filename, app) ->
        [..., extension] = filename.split('.')
        _ "#{filename} has extension #{extension}"

        switch (extension)

#### Archives

ZIP files get extracted via 7z, then we look in the directory and repeat
the previous step.

          when 'zip', '7z', 'rar'
            directory = "#{params.tempDir}/#{app.name}/unzipped"
            fs.mkdir directory, ->
              $ "7z x -o#{directory} #{filename}"
              Gardener.findFile directory, app

#### Disk IMaGes

DMGs are weird. Just mount them and hope for the best.

TODO: The `noautoopen` flag seems to be ignored on occasion, 
popping a Finder window all up in yo biz. Obnoxious.

          when 'dmg'
            mountpoint = tempDir + '/' + filename.split('.')[0]
            $ "hdiutil attach -noautoopen #{filename} -mountpoint #{mountpoint}"
            Gardener.findFile mountpoint, app

#### PKG

I wish this could be done silently. Whatev's.

          when 'pkg'
            $ "open #{filename}"

#### Application Bundles

Ultimately, we're looking for a "file" that is really a directory
ending in `.app`. When we finally get it, copy it over to the install
dest and we're done.

          when 'app'
            $ "cp -r #{filename} #{params.appDestination}"

What are you still reading for? This is just an entry point. Go get some
exercise or something.

    Gardener.grow()
