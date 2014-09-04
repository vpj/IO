    _self = this

##Response class

    class Response
     constructor: (data, port, options) ->
      @id = data.id
      @port = port
      @options = options

     progress: (progress, data) ->
      @port.respond this, 'progress', data, progress: progress, @options

     success: (data) ->
      @port.respond this, 'success', data, {}, @options

     fail: (data) ->
      @port.respond this, 'fail', data, {}, @options



##Call class

    class Call
     constructor: (@id, @method, @data, @callbacks) -> null

     handle: (data, options) ->
      if not @callbacks[options.status]?
       return if options.status is 'progress'
       throw new Error "No callback registered #{@method} #{options.status}"
      @callbacks[options.status] data, options

##Port base class

    class Port
     constructor: ->
      @handlers = {}
      @callsCache = {}
      @callsCounter = 0
      @wrappers =
       send: []
       respond: []
       handleCall: []
       handleResponse: []

     onerror: (msg, options) ->
      console.log msg, options

     wrap: (wrapper) ->
      for key, f of wrapper
       if @wrappers[key]?
        @wrappers[key].push f
       else
        this[key] = f

###Send RPC call

     send: (method, data, callbacks, options = {}) ->
      if (typeof callbacks) is 'function'
       callbacks =
        success: callbacks

      for f in @wrappers.send
       return unless f.apply this, [method, data, callbacks, options]

      @_send @_createCall method, data, callbacks, options

###Respond to a RPC call

     respond: (response, status, data, options = {}, portOptions = {}) ->
      for f in @wrappers.respond
       return unless f.apply this, [response, status, data, options, portOptions]

      @_respond (@_createResponse response, status, data, options), portOptions


###Create Call object
This is a private function

     _createCall: (method, data, callbacks, options) ->
      call = new Call @callsCounter, method, data, callbacks
      @callsCounter++
      @callsCache[call.id] = call

      params =
       type: 'call'
       id: call.id
       method: call.method
       data: call.data

      params[k] = v for k, v of options
      return params

###Create Response object

     _createResponse: (response, status, data, options) ->
      params =
       type: 'response'
       id: response.id
       status: status
       data: data

      params[k] = v for k, v of options

      return params

###Add handler

     on: (method, callback) ->
      @handlers[method] = callback

###Handle incoming message

     _handleMessage: (data, options) ->
      switch data.type
       when 'response'
        @_handleResponse data, options
       when 'call'
        @_handleCall data, options

     _handleCall: (data, options) ->
      for f in @wrappers.handleCall
       return unless f.apply this, arguments
      if not @handlers[data.method]?
       throw new Error "Unknown method: #{data.method}"
      @handlers[data.method] data.data, data, new Response data, this, options

     _handleResponse: (data, options) ->
      for f in @wrappers.handleResponse
       return unless f.apply this, arguments
      if not @callsCache[data.id]?
       throw new Error "Response without call: #{data.id}"
      @callsCache[data.id].handle data.data, data

##WorkerPort class
Used for browser and worker

    class WorkerPort extends Port
     constructor: (worker) ->
      super()
      @worker = worker
      @worker.onmessage = @_onMessage.bind this
      @worker.onerror = @_onError.bind this

     _send: (data) ->  @worker.postMessage data
     _respond: (data) -> @worker.postMessage data

     _onMessage: (e) ->
      data = e.data
      @_handleMessage data

     _onError: (e) -> console.log e



##SocketPort class

    class SocketPort extends Port
     constructor: (socket) ->
      super()
      @socket = socket
      @socket.on 'message', @_onMessage.bind this

     _send: (data) ->  @socket.emit 'message', data
     _respond: (data) -> @worker.emit 'message', data

     _onMessage: (e) ->
      data = e.data
      @_handleMessage data



##ServerSocketPort class

    class ServerSocketPort extends Port
     constructor: (server) ->
      super()
      @server = server
      @server.on 'connection', @_onConnection.bind this

     _onConnection: (socket) ->
      new SocketPort handlers: @handlers, socket



##NodeHttpPort class

    class NodeHttpPort extends Port
     constructor: (options, http) ->
      super()
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
       'content-type': 'application/json'


     _onRequest: (res) ->
      data = ''
      #console.log 'STATUS: ' + res.statusCode
      #console.log 'HEADERS: ' + JSON.stringify res.headers
      res.setEncoding 'utf8'
      res.on 'data', (chunk) ->
       data += chunk
      #console.log 'result', res
      res.on 'end', =>
       try
        jsonData = JSON.parse data
       catch e
        console.log 'ParseError', e
        return

       @_handleMessage jsonData, response: res

     _respond: (data, options) ->
      data = JSON.stringify data
      res = options.response
      res.setHeader 'content-length', data.length
      res.write data
      res.end()


     _send: (data) ->
      data = JSON.stringify data
      options = @httpOptions
      options.headers['content-length'] = data.length

      req = @http.request options, @_onRequest.bind this
      delete options.headers['content-length']
      req.on 'error', (e) ->
       console.log 'error', e

      req.write data
      req.end()



##NodeHttpServerPort class

    class NodeHttpServerPort extends Port
     constructor: (options, http) ->
      super()
      @port = options.port
      @http = http

     _onRequest: (req, res) ->
      data = ''
      res.setHeader 'content-type', 'application/json'

      req.on 'data', (chunk) ->
       data += chunk
      req.on 'end', =>
       try
        jsonData = JSON.parse data
       catch e
        console.log 'ParseError', e
        return

       @_handleMessage jsonData, response: res

     _respond: (data, options) ->
      data = JSON.stringify data
      res = options.response
      res.setHeader 'content-length', data.length
      res.write data
      res.end()

     listen: ->
      @server = @http.createServer @_onRequest.bind this
      @server.listen @port


#IO Module

    IO =
     addPort: (name, port) ->
      IO[name] = port

     ports:
      WorkerPort: WorkerPort
      SocketPort: SocketPort
      NodeHttpPort: NodeHttpPort
      NodeHttpServerPort: NodeHttpServerPort
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

