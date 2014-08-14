    class Port
     constructor: ->
      @handlers = {}
      @callsCache = {}
      @callsCounter = 0

     send: (method, data, callbacks, options = {}) -> null


     _createCall: (method, data, callbacks, options) ->
      #TODO other params via options
      if (typeof callbacks) is 'function'
       callbacks =
        success: callbacks

      call = new Call method, data, callbacks
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

     respond: (id, status, data, progress) -> null

    class WorkerPort extends Port
     constructor: (js) ->
      @worker = new Worker js
      @worker.onmessage = @onMessage
      @worker.onerror = @onError
      super()

     send: (method, data, callbacks, options = {}) ->
      @worker.postMessage @_createCall method, data, callbacks, options

     respond: (response, status, data, options = {}) ->
      @worker.postMessage @_createRespose response, status, data, options



