    class Port
     constructor: ->
      @handlers = {}
      @callsCache = {}
      @callsCounter = 0

     send: (method, data, callbacks, options = {}) -> null
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
     constructor: (worker) ->
      @worker = worker
      @worker.onmessage = @_onMessage.bind this
      @worker.onerror = @_onError.bind this
      super()

     _send: (data) ->  @worker.postMessage data
     _respond: (data) -> @worker.postMessage data

     _onMessage: (e) ->
      data = e.data
      @handleMessage data

     _onError: (e) -> console.log e

    class SocketPort extends Port
     constructor: (socket) ->
      @socket = socket
      @socket.on 'message', @_onMessage.bind this
      super()

     _send: (data) ->  @socket.emit 'message', data
     _respond: (data) -> @worker.emit 'message', data

     _onMessage: (e) ->
      data = e.data
      @handleMessage data

