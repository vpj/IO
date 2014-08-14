Incoming calls

    callCache = {}
    callCounter = 0

Event handlers

    handlers = {}

    getCallId = ->
     callCounter++
     return callCounter

    defaultHTTPHandler = (req, res) ->
     res.writeHead 200
     res.end "Hello, world!"

    EngineSocket = null

    class SocketResponse
     constructor: (data) ->
      @id = data.id

     progress: (progress, data) ->
      EngineSocket.emit 'message',
       type: 'response'
       id: @id
       status: 'progress'
       progress: progress
       data: data

     success: (data) ->
      EngineSocket.emit 'message',
       type: 'response'
       id: @id
       status: 'success'
       data: data

     fail: (data) ->
      EngineSocket.emit 'message',
       type: 'response'
       id: @id
       status: 'fail'
       data: data

    EngineWorker = null
    class WorkerResponse
     constructor: (data) ->
      @id = data.id

     progress: (progress, data) ->
      EngineWorker.postMessage
       type: 'response'
       id: @id
       status: 'progress'
       progress: progress
       data: data

     success: (data) ->
      EngineWorker.postMessage
       type: 'response'
       id: @id
       status: 'success'
       data: data

     fail: (data) ->
      EngineWorker.postMessage
       type: 'response'
       id: @id
       status: 'fail'
       data: data

    onWorkerMessage = (e) ->
     if e.data.type is 'response'
      return unless callCache[e.data.id]?

      callCache[e.data.id].handle e.data
     else if e.data.type is 'call'
      return unless (typeof handlers[e.data.method]) is 'function'

      res = new WorkerResponse e.data
      handlers[e.data.method] e.data.data, res


    class EngineCall
     constructor: (@method, @data, @callbacks) ->
      @id = getCallId()

     handle: (data) ->
      @callbacks[data.status]? data


     send: (method, data, callbacks) ->
      if (typeof callbacks) is 'function'
       callbacks =
        success: callbacks

      call = new EngineCall method, data, callbacks
      callCache[call.id] = call

      if EngineWorker?
       EngineWorker.postMessage
        type: 'call'
        id: call.id
        method: call.method
        data: call.data
      else if EngineSocket?
       EngineSocket.emit 'message',
        type: 'call'
        id: call.id
        method: call.method
        data: call.data


     addHandler: (method, callback) ->
      handlers[method] = callback


    class Response
     constructor: (data, port) ->
      @id = data.id
      @port = port

     progress: (progress, data) ->
      @port.respond this, 'progress', data, progress: progress
     success: (data) ->
      @port.respond this, 'success', data
     fail: (data) ->
      @port.respond this, 'fail', data

    IO =
     addPort: (name, port) ->
      IO[name] = port

     setup: (options) ->
      options.workers ?= []
      switch options.platform
       when 'ui'
        for worker in options.workers
         IO.addPort worker.name, new WorkerPort worker.js
        for socket in options.sockets
         IO.addPort socket.name, new SocketPort socket.url
       when 'node'
        for socket in options.listenSockets
         IO.addPort socket.name, new SocketListenPort socket.port
        for socket in options.sockets
         IO.addPort socket.name, new SocketPort socket.url
       when 'worker'
        IO.addPort 'UI', new WorkerListenPort _self

    if exports?
     module.exports = IO
    else
     _self.IO = IO

