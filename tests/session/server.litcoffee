#!/usr/bin/env coffee

    IO = require '../../io'
    MultiSession = (require '../../io_session').MultiSession

    http = require 'http'

    server = new IO.ports.NodeHttpServerPort port: 8080, http
    server.wrap MultiSession

    IO.addPort 'Client', server

    server.listen()

    IO.Client.on 'echo', (data, res) ->
     console.log data
     res.success 'World listening...'

