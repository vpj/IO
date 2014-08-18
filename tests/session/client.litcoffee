#!/usr/bin/env coffee

    IO = require '../../io'
    SingleSession = (require '../../io_session').SingleSession

    http = require 'http'

    options =
     host: 'localhost'
     port: 8080
     path: '/'

    port = new IO.ports.NodeHttpPort options, http
    port.wrap SingleSession
    IO.addPort 'Server', port
    IO.Server.newSession (session) ->
     console.log session
     IO.Server.send 'echo', 'Hello, world!', (data, options) ->
      console.log "Reply", data, options
     IO.Server.send 'echo', 'Hello, world2!', (data, options) ->
      console.log "Reply", data, options

