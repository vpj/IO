    _self = this

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

    class Call
     constructor: (@id, @method, @data, @callbacks) -> null

     handle: (data) ->
      if not @callbacks[data.status]?
       throw new Error "No callback registered #{@method} #{data.status}"
      @callback[data.status] data

    class Port
     constructor: (options = {}) ->
      @handlers = options.handlers ? {}
      @callsCache = {}
      @callsCounter = 0

     send: (method, data, callbacks, options = {}) ->
      @_send @_createCall method, data, callbacks, options

     respond: (response, status, data, options = {}) ->
      @_respond @_createRespose response, status, data, options


     _createCall: (method, data, callbacks, options) ->
      #TODO other params via options
      if (typeof callbacks) is 'function'
       callbacks =
        success: callbacks

      call = new Call @callsCounter, method, data, callbacks
      @callsCounter++
      @callsCache[call.id] = call

      params =
       type: 'call'
       id: call.id
       mehtod: call.method
       data: call.data

      return params

     _createRespose: (response, status, data, options) ->
      params =
       type: 'response'
       id: response.id
       status: status
       data: data

      params[k] = v for k, v of options

      return params

     addHandler: (method, callback) ->
      @handlers[method] = callback

     handleMessage: (data) ->
      if data.type is 'response'
       return unless @callsCache[data.id]?
       @callsCache[data.id].handle data
      else if data.type is 'call'
       return unless @handlers[data.method]?
       @handlers[data.method] data.data, new Response data, this

    class WorkerPort extends Port
     constructor: (options, worker) ->
      super options
      @worker = worker
      @worker.onmessage = @_onMessage.bind this
      @worker.onerror = @_onError.bind this

     _send: (data) ->  @worker.postMessage data
     _respond: (data) -> @worker.postMessage data

     _onMessage: (e) ->
      data = e.data
      @handleMessage data

     _onError: (e) -> console.log e

    class SocketPort extends Port
     constructor: (options, socket) ->
      super options
      @socket = socket
      @socket.on 'message', @_onMessage.bind this

     _send: (data) ->  @socket.emit 'message', data
     _respond: (data) -> @worker.emit 'message', data

     _onMessage: (e) ->
      data = e.data
      @handleMessage data

    class ServerSocketPort extends Port
     constructor: (options, server) ->
      super options
      @server = server
      @server.on 'connection', @_onConnection.bind this

     _onConnection: (socket) ->
      new SocketPort handlers: @handlers, socket


    IO =
     addPort: (name, port) ->
      IO[name] = port

     ports:
      WorkerPort: WorkerPort
      SocketPort: SocketPort
      ServerSocketPort: ServerSocketPort

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

