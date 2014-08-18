    _self = this

##Response class

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



##Call class

    class Call
     constructor: (@id, @method, @data, @callbacks) -> null

     handle: (data) ->
      if not @callbacks[data.status]?
       throw new Error "No callback registered #{@method} #{data.status}"
      @callback[data.status] data

##Port base class

    class Port
     constructor: (options = {}) ->
      @handlers = options.handlers ? {}
      @callsCache = {}
      @callsCounter = 0

###Send RPC call

     send: (method, data, callbacks, options = {}) ->
      @_send @_createCall method, data, callbacks, options

###Respond to a RPC call

     respond: (response, status, data, options = {}) ->
      @_respond @_createRespose response, status, data, options


###Create Call object
This is a private function

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

###Create Response object

     _createRespose: (response, status, data, options) ->
      params =
       type: 'response'
       id: response.id
       status: status
       data: data

      params[k] = v for k, v of options

      return params

###Add handler

     addHandler: (method, callback) ->
      @handlers[method] = callback

###Handle incoming message

     handleMessage: (data) ->
      if data.type is 'response'
       return unless @callsCache[data.id]?
       @callsCache[data.id].handle data
      else if data.type is 'call'
       return unless @handlers[data.method]?
       @handlers[data.method] data.data, new Response data, this



##WorkerPort class
Used for browser and worker

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



##SocketPort class

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



##ServerSocketPort class

    class ServerSocketPort extends Port
     constructor: (options, server) ->
      super options
      @server = server
      @server.on 'connection', @_onConnection.bind this

     _onConnection: (socket) ->
      new SocketPort handlers: @handlers, socket



##NodeHttpPort class

    class NodeHttpPort extends Port
     constructor: (options, http) ->
      super options
      @host = options.host ? 'localhost'
      @port = options.port ? 80
      @path = options.path ? '/'
      @http = http
      @_createHttpOptions()

     _createHttpOptions: ->
      @httpOptions =
       hostname: @host
       port: @port
       path: @path
       method: 'POST'
       headers:
        accept: 'application/json'

     _send: (data) ->
      data = JSON.stringify data
      options = @httpOptions
      options.headers['content-length'] = data.length

      req = @http.request options, (res) =>
       console.log 'STATUS: ' + res.statusCode
       console.log 'HEADERS: ' + JSON.stringify res.headers
       res.setEncoding 'utf8'
       res.on 'data', (chunk) ->
        console.log 'BODY: ' + chunk
       #console.log 'result', res

      delete options.headers['content-length']
      req.on 'error', (e) ->
       console.log 'error', e

      req.write data
      req.end()



#IO Module

    IO =
     addPort: (name, port) ->
      IO[name] = port

     ports:
      WorkerPort: WorkerPort
      SocketPort: SocketPort
      NodeHttpPort: NodeHttpPort
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

