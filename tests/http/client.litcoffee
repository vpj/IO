#!/usr/bin/env coffee

    IO = require '../../io'
    http = require 'http'

    options =
     host: 'localhost'
     port: 8080
     path: '/'

    port = new IO.ports.NodeHttpPort options, http
    IO.addPort 'Server', port
    IO.Server.send 'echo', 'Hello, world!', (data) ->
     console.log "Reply", data

