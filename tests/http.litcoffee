#!/usr/bin/env coffee

    IO = require '../io'

    options =
     host: 'localhost'
     port: 8080
     path: '/'

    port = new IO.ports.NodeHttpPort options, require 'http'

    port._send method: 'ping', id: 123, type: 'call', data: {}

