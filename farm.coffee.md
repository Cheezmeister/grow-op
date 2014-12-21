#!/usr/bin/env coffee -l

# Overview

The farmer downloads MacOS Applications and stuffs them where they belong.

## The Farmfile

It lists stuff to download in the form of `AppName: http://some.url/to/hit`
An example farmfile might be:

    """
    """

# Implementation

`farm` is essentially a thinnish wrapper to `wget`. It uses `7z` to extract
stuff, though you could swap it out for something else if you really wanted.

There is an implicit dependency on [Homebrew](http://brew.sh). You were
using that already, right?

## Syssy

This is a silly little snippet I've taken to calling syssy, that simplifies 
embedding system commands. It's a work in progress.

    cp = require 'child_process'
    exec = cp.exec
    spawn = cp.spawn

    _ = console.log
    $ = (str, errorHandler) ->
      exec str, (error, stdout, stderr) ->
        _ "$ #{stdout}"
        if (error && errorHandler)
          errorHandler(error, stdout, stderr)


## Parameters

TODO: Use commandline args

    params =
      farmfile: 'Farmfile'
      tempDir: '/tmp/farm'
      appDestination: '~/Farm'

    farmfile = 'Farmfile'
    tempDir = '/tmp/farm'

## Initialization

Farmer uses `wget` and `7zip` which really ought to be installed. 
If not, we'll brew it for ya.

    $ "which wget || brew install wget"
    $ "which 7z || brew install p7zip"

## Application

We need to read from the filesystem, obviously.

    fs = require 'fs'

The `Farmer` object provides a sort of poor man's promise mechanism
and separates the logic flow into four(ish) steps: 

* farm, which reads the farmfile and acts on it
* download, which gets a URL
* findFile, which looks for a single file in a given directory
* processFile, which looks at a file's extension and decides what to do with it

    Farmer =

### Read the Farmfile

      farm: ->
        $ "mkdir -p #{params.tempDir}"
        fs.readFile farmfile, 'utf8', (err, data) ->
          if err or !data then throw err
          apps = data.trim().split('\n').map (x) -> {name: x.split(':')[0], url: x.split(':')[1] }
          apps.map (app) ->
            # Farmer.download app
            location = "#{tempDir}/#{app.name}"
            Farmer.download app
            
### Download Applications

Download a given app to temp.

Hypothetically I don't need to delegate this part to `wget`. Realistically
it does a lot of nice things for us that I'm too lazy to implement directly.
For example, it transparently handles HTTP 302.

      download: (app) ->
        location = "#{tempDir}/#{app.name}"
        _ "Fetching #{app.name} from #{app.url}"
        exec "wget --directory-prefix='#{location}' #{app.url}", (err) ->
          if err then _ err
          Farmer.findFile location, app unless err

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
          Farmer.processFile "#{directory}/#{files[0]}", app

### Do Stuff with Files

We're pretty dumb and just look at the extension to decide what to do.

I think that's okay.

      processFile: (filename, app) ->
        [..., extension] = filename.split('.')
        _ "#{filename} has extension #{extension}"
        switch (extension)

ZIP files get extracted via 7z, then we look in the directory and repeat
the previous step.

          when 'zip', '7z', 'rar'
            directory = "#{tempDir}/#{app.name}/unzipped"
            fs.mkdir directory, ->
              exec "7z x -o#{directory} #{filename}", (err) ->
                Farmer.findFile directory, app

DMGs are weird. Just mount them and hope for the best.

TODO: The `noautoopen` flag seems to be busted in mavericks, the finder
window always opens itself. Obnoxious.

          when 'dmg'
            $ "hdiutil attach -noautoopen #{filename}"

I haven't come across PKG files I need to install. Whatev's.

          when 'pkg'
            _ ">>> open #{filename}"

Ultimately, we're looking for a "file" that is really a directory
ending in `.app`. When we finally get it, copy it over to the install
dest and we're done.

          when 'app'
            $ "cp -r #{filename} #{params.appDestination}"

    Farmer.farm()


