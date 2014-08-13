Incoming calls

    callCache = {}
    callCounter = 0

Event handlers

    handlers = {}

Copy of self

    _self = self

    getCallId = ->
     callCounter++
     return callCounter

    defaultHTTPHandler = (req, res) ->
     res.writeHead 200
     res.end "Hello, world!"

    EngineSocket = null

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
    onSocketMessage = (data) ->
     if data.type is 'response'
      return unless callCache[data.id]?

      callCache[data.id].handle data
     else if data.type is 'call'
      return unless (typeof handlers[data.method]) is 'function'

      res = new SocketResponse data
      handlers[data.method] data.data, res



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


    @Engine =
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


     setup: (options) ->
      switch options.platform
       when 'ui'
        if options.worker?
         worker = new Worker options.worker

      if TYPE is 'BROWSER'
       if options.worker?
        EngineWorker = new Worker options.worker
        EngineWorker.onmessage = onWorkerMessage
        EngineWorker.onerror = (e) -> throw e
       else if options.socket?
        EngineSocket = socketIO.connect options.socket
        EngineSocket.on 'message', onSocketMessage
      else if TYPE is 'NODE'
       app = require('http').createServer HTTPHandler
       io = require('socket.io').listen app

       app.listen options.port

       io.sockets.on 'connection', (socket) ->
        EngineSocket = socket
        EngineSocket.on 'message', onSocketMessage


    if TYPE is 'WORKER'
     EngineWorker = self
     EngineWorker.onmessage = onWorkerMessage
     EngineWorker.onerror = (e) -> console.error e

    if TYPE is 'NODE'
     module.exports = @Engine

    @Engine.addHandler 'ping', (data, res) ->
     res.success data
