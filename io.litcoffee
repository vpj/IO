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


    class Port
     constructor: ->
      @handlers = {}
      @callsCache = {}
      @callsCounter = 0

     send: (method, data, callbacks) -> null

     addHandler: (method, callback) ->
      @handlers[method] = callback

     handleMessage: (data) ->
      if data.type is 'response'
       return unless @callsCache[data.id]?
       @callsCache[data.id].handle data
      else if data.type is 'call'
       return unless @handlers[data.method]?
       @handlers[data.method] data.data, new Response data, this

     respond: (id, status, data, progress) -> null

    class WorkerPort extends Port
     constructor: (js) ->
      @worker = new Worker js
      @worker.onmessage = @onMessage
      @worker.onerror = @onError
      super()

     send: (method, data, callbacks) -> null
      if (typeof callbacks) is 'function'
       callbacks =
        success: callbacks

      call = new Call method, data, callbacks
      @callsCache[call.id] = call
      @worker.postMessage
       type: 'call'
       id: call.id
       mehtod: call.method
       data: call.data


    class Response
     constructor: (data, port) ->
      @id = data.id
      @port = port

     progress: (progress, data) ->
      @port.respond @id, 'progress', data, progress
     success: (data) ->
      @port.respond @id, 'success', data
     fail: (data) ->
      @port.respond @id, 'fail', data

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

