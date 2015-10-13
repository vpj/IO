    _self = this

    if console?.log?
     LOG = console.log.bind console
    else
     LOG = -> null

    if console?.error?
     ERROR_LOG = console.error.bind console
    else
     ERROR_LOG = -> null


    POLL_TYPE =
     progress: true

##Response class

    class Response
     constructor: (data, port, options) ->
      @id = data.id
      @port = port
      @options = options
      @queue = []
      @fresh = true

     progress: (progress, data, callback) ->
      @queue.push
       method: 'progress'
       data: data
       options: {progress: progress}
       callback: callback
      @_handleQueue()

     success: (data) ->
      @queue.push method: 'success', data: data, options: {}
      @_handleQueue()

     fail: (data) ->
      @queue.push method: 'fail', data: data, options: {}
      @_handleQueue()

     setOptions: (options) ->
      @options = options
      @fresh = true
      @_handleQueue()

     _multipleResponse: ->
      responseList = []
      callbacks = []
      for d in @queue
       responseList.push
        status: d.method
        data: d.data
        options: d.options
       if d.callback?
        callbacks.push d.callback

      done = ->
       for callback in callbacks
        callback()

      if @port.isStreaming
       @port.respondMultiple this, responseList, @options, done
      else if @fresh
       @port.respondMultiple this, responseList, @options, done
       @fresh = false

      @queue = []


     _handleQueue: ->
      return unless @queue.length > 0
      return if not @queue.isStreaming and not @fresh

      if @queue.length > 1
       return @_multipleResponse()


      d = @queue[0]

      if @port.isStreaming
       @port.respond this, d.method, d.data, d.options, @options, d.callback
      else if @fresh
       @port.respond this, d.method, d.data, d.options, @options, d.callback
       @fresh = false

      @queue = []

##Call class

    class Call
     constructor: (@id, @method, @data, @callbacks, @options) -> null

     handle: (data, options) ->
      if not @callbacks[options.status]?
       return if options.status is 'progress'
       #Handled by caller
       throw new Error "No callback registered #{@method} #{options.status}"
      self = this
      setTimeout (-> self.callbacks[options.status] data, options), 0

      if POLL_TYPE[options.status]?
       return false
      else
       return true

##Port base class

    class Port
     constructor: ->
      @handlers = {}
      @callsCache = {}
      @callsCounter = 0
      @id = parseInt Math.random() * 1000
      @responses = {}
      @wrappers =
       send: []
       respond: []
       handleCall: []
       handleResponse: []

     isStreaming: true

     onCallError: (msg, options) ->
      for id, call of @callsCache
       if not call.callbacks.fail?
        ERROR_LOG 'fail callback not registered', call.method, call.data
       else
        call.callbacks.fail error: 'connectionError', msg: msg, options: options, {}

      @callsCache = {}

      @errorCallback msg, options

     onHandleError: (msg, data, options) ->
      @errorCallback msg, data
      response = new Response data, this, options
      response.fail msg

     errorCallback: (msg, options) ->
      ERROR_LOG msg, options

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

      params = @_createCall method, data, callbacks, options
      @_send params, callbacks

###Respond to a RPC call

     respond: (response, status, data, options = {}, portOptions = {}, callback = null) ->
      if not POLL_TYPE[status]?
       delete @responses[response.id]

      for f in @wrappers.respond
       return unless f.apply this, [response, status, data, options, portOptions]

      @_respond (@_createResponse response, status, data, options), portOptions, callback

     respondMultiple: (response, list, portOptions = {}, callback = null) ->
      for d in list
       if not POLL_TYPE[d.status]?
        delete @responses[response.id]
        break

      data = []
      for d in list
       cancel = false
       d.options ?= {}
       for f in @wrappers.respond
        r = f.apply this, [response, d.status, d.data, d.options, portOptions]
        if not r
         cancel = true
         break

        continue if cancel

       data.push @_createResponse response, d.status, d.data, d.options

      return if data.length is 0

      data =
       type: 'list'
       list: data

      @_respond data, portOptions, callback



###Create Call object
This is a private function

     _createCall: (method, data, callbacks, options) ->
      call = new Call "#{@id}-#{@callsCounter}", method, data, callbacks, options
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

     _handleMessage: (data, options, last = true) ->
      switch data.type
       when 'list'
        for d, i in data.list
         @_handleMessage d, options, (last and i + 1 is data.list.length)
       when 'response'
        @_handleResponse data, options, last
       when 'call'
        @_handleCall data, options, last
       when 'poll'
        @_handlePoll data, options, last

     _handleCall: (data, options) ->
      for f in @wrappers.handleCall
       return unless f.apply this, arguments
      if not @handlers[data.method]?
       @onHandleError "Unknown method: #{data.method}", data, options
       return
      @responses[data.id] = new Response data, this, options
      @handlers[data.method] data.data, data, @responses[data.id]

     _handleResponse: (data, options) ->
      for f in @wrappers.handleResponse
       return unless f.apply this, arguments
      if not @callsCache[data.id]?
       #Cannot reply
       @errorCallback "Response without call: #{data.id}", data
       return
      try
       if @callsCache[data.id].handle data.data, data
        delete @callsCache[data.id]
      catch e
       @errorCallback e.message, data
       delete @callsCache[data.id]

     _handlePoll: (data, options) ->
      @onHandleError "Poll not implemented", data, options

##WorkerPort class
Used for browser and worker

    class WorkerPort extends Port
     constructor: (worker) ->
      super()
      @worker = worker
      @worker.onmessage = @_onMessage.bind this
      #@worker.onerror = @onCallError.bind this

     _send: (data) ->
      @worker.postMessage data

     _respond: (data, options, callback) ->
      @worker.postMessage data
      callback?()

     _onMessage: (e) ->
      data = e.data
      @_handleMessage data



##SocketPort class

    class SocketPort extends Port
     constructor: (socket) ->
      super()
      @socket = socket
      @socket.on 'message', @_onMessage.bind this

     _send: (data) ->  @socket.emit 'message', data
     _respond: (data, options, callback) ->
      @worker.emit 'message', data
      callback?()

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



##AJAX class

    class AjaxHttpPort extends Port
     constructor: (options) ->
      super()
      @protocol = options.protocol
      @host = options.host
      @port = options.port
      @path = options.path ? '/'
      @url = @path
      if @protocol?
       if @host? and not @port?
        @url = "#{@protocol}://#{@host}#{@path}"
       else if @host? and @port?
        @url = "#{@protocol}://#{@host}:#{@port}#{@path}"
      else
       if @host? and not @port?
        @url = "//#{@host}#{@path}"
       else if @host? and @port?
        @url = "//#{@host}:#{@port}#{@path}"

     isStreaming: false

     _onRequest: (xhr) ->
      return unless xhr.readyState is 4
      status = xhr.status
      if ((not status and xhr.responseText? and xhr.responseText != '') or
          (status >= 200 and status < 300) or
          (status is 304))
       try
        jsonData = JSON.parse xhr.responseText
       catch e
        @onCallError 'ParseError', e
        return

       @_handleMessage jsonData, xhr: xhr
      else
       @onCallError 'Cannot connect to server'

     _respond: (data, options, callback) ->
      @errorCallback 'AJAX cannot respond', data
      callback?()

     _send: (data) ->
      data = JSON.stringify data
      xhr = new XMLHttpRequest
      xhr.open 'POST', @url
      xhr.onreadystatechange = =>
       @_onRequest xhr
      xhr.setRequestHeader 'Accept', 'application/json'
      #xhr.setRequestHeader 'Content-Type', 'application/json'
      xhr.send data

     _handleResponse: (data, options, last = true) ->
      for f in @wrappers.handleResponse
       return unless f.apply this, arguments
      if not @callsCache[data.id]?
       @errorCallback "Response without call: #{data.id}", data
       return
      call = @callsCache[data.id]
      try
       if call.handle data.data, data
        delete @callsCache[data.id]
       else if last
        params =
         type: 'poll'
         id: call.id
        params[k] = v for k, v of call.options
        @_send params
      catch e
       @errorCallback e.message, data
       delete @callsCache[data.id]



##NodeHttpPort class

    class NodeHttpPort extends Port
     constructor: (options, http) ->
      super()
      @host = options.host ? 'localhost'
      @port = options.port ? 80
      @path = options.path ? '/'
      @http = http
      @_createHttpOptions()

     isStreaming: false

     _createHttpOptions: ->
      @httpOptions =
       hostname: @host
       port: @port
       path: @path
       method: 'POST'
       agent: false
       headers:
        accept: 'application/json'
       'content-type': 'application/json'


     _onRequest: (res) ->
      data = ''
      #LOG 'STATUS: ' + res.statusCode
      #LOG 'HEADERS: ' + JSON.stringify res.headers
      res.setEncoding 'utf8'
      res.on 'data', (chunk) ->
       data += chunk
      #LOG 'result', res
      res.on 'end', =>
       try
        jsonData = JSON.parse data
       catch e
        @onCallError 'ParseError', e
        return

       @_handleMessage jsonData, response: res

     _respond: (data, options, callback) ->
      data = JSON.stringify data
      res = options.response
      res.setHeader 'content-length', Buffer.byteLength data, 'utf8'
      if callback?
       res.once 'finish', ->
        callback()
       res.once 'close', ->
        callback()

      res.write data
      res.end()

     _send: (data, callbacks) ->
      data = JSON.stringify data
      options = @httpOptions
      options.headers['content-length'] = Buffer.byteLength data, 'utf8'

      req = @http.request options, @_onRequest.bind this
      delete options.headers['content-length']
      req.on 'error', (e) ->
       callbacks.fail? e

      req.write data
      req.end()

     _handleResponse: (data, options, last = true) ->
      for f in @wrappers.handleResponse
       return unless f.apply this, arguments
      if not @callsCache[data.id]?
       @errorCallback "Response without call: #{data.id}", data
       return
      call = @callsCache[data.id]
      if not call.handle data.data, data
       return if not last
       params =
        type: 'poll'
        id: call.id
       params[k] = v for k, v of call.options
       @_send params, call.callbacks



##NodeHttpServerPort class

    class NodeHttpServerPort extends Port
     constructor: (options, http, zlib = null) ->
      super()
      @port = options.port
      @http = http
      @zlib = zlib
      @allowOrigin = options.allowOrigin

     isStreaming: false

     _onRequest: (req, res) ->
      data = ''
      res.setHeader 'content-type', 'application/json'

      req.on 'data', (chunk) ->
       data += chunk
      req.on 'end', =>
       try
        jsonData = JSON.parse data
       catch e
        @errorCallback 'ParseError', e
        return

       @_handleMessage jsonData, response: res, request: req

     _respond: (data, options, callback) ->
      if @allowOrigin?
       options.response.setHeader 'Access-Control-Allow-Origin', @allowOrigin

      accept = options.request.headers['accept-encoding']
      accept ?= ''
      if not @zlib?
       accept = ''

      data = JSON.stringify data
      buffer = new Buffer data, 'utf8'
      if accept.match /\bdeflate\b/
       options.response.setHeader 'content-encoding', 'deflate'
       @zlib.deflate buffer, (err, result) =>
        if err?
         return @errorCallback 'DeflateError', e
        @_sendBuffer result, options.response, callback
      else if accept.match /\bgzip\b/
       options.response.setHeader 'content-encoding', 'gzip'
       @zlib.gzip buffer, (err, result) =>
        if err?
         return @errorCallback 'GZipeError', e
        @_sendBuffer result, options.response, callback
      else
       @_sendBuffer buffer, options.response, callback

     _sendBuffer: (buf, res, callback) ->
       res.setHeader 'content-length', buf.length
       if callback?
        res.once 'finish', ->
         callback()
        res.once 'close', ->
         callback()

       res.write buf
       res.end()

     listen: ->
      @server = @http.createServer @_onRequest.bind this
      @server.listen @port

     _handlePoll: (data, options) ->
      for f in @wrappers.handleCall
       return unless f.apply this, arguments
      if not @responses[data.id]?
       @onHandleError "Poll without response: #{data.id}", data, options
       return
      @responses[data.id].setOptions options

##NodeHttpsServerPort class

    class NodeHttpsServerPort extends NodeHttpServerPort
     constructor: (options, http) ->
      super options, http
      @_key = options.key
      @_cert = options.cert

     listen: ->
      options =
       key: @_key
       cert: @_cert

      @server = @http.createServer options, @_onRequest.bind this
      @server.listen @port


#IO Module

    IO =
     addPort: (name, port) ->
      IO[name] = port

     ports:
      WorkerPort: WorkerPort
      SocketPort: SocketPort
      AjaxHttpPort: AjaxHttpPort
      NodeHttpPort: NodeHttpPort
      NodeHttpServerPort: NodeHttpServerPort
      NodeHttpsServerPort: NodeHttpsServerPort
      ServerSocketPort: ServerSocketPort

     Helpers:
      progress: (from, to, func) ->
       (progress, data) ->
        func? progress * (to - from) + from, data

     setup_____: (options) ->
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

