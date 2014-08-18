    class Session
     constructor: (port) ->
      @port = port
      @addHandler = @port.addHandler.bind
      @portFunctions =
       _handleCall: @port._handleCall.bind @port
       _handleResponse: @port._handleResponse.bind @port

      @port._handleCall = @_handleCall.bind this
      @port._handleResponse = @_handleRespose.bind this

      @on = @port.on.bind @port
      @onerror = @port.onerror

      @session = null

     send: (method, data, callback, options = {}) ->
      options.session = @session
      @port.send method, data, callback, options

     respond: (response, status, data, options = {}, portOptions = {}) ->
      options.session = @session
      @port.respond respond, status, data, options, portOptions

     _handleCall: (data, options) ->
      if data.method is 'createSession'
       res = new Response data, this, options
       return

      if data.session?
       @portFunctions._handleCall data, options
       return

      if @onerror?
       @onerror 'RPC without session', data: data

      return

     createSession: ->

