    SingleSession =
     session: null
     send: (method, data, callback, options) ->
      options.session = @session
      return true

     respond: (response, status, data, options, portOptions) ->
      if not portOptions.session?
       throw new Error 'RPC without session'

      options.session = portOptions.session
      return true

     handleCall: (data, options) ->
      if data.method is 'newSession'
       @session = Math.random() * 1000 // 1000
       options.session = @session
       @respond id: data.id, 'success', 'newSession', {}, options
       return false

      if not data.session?
       @onerror 'RPC without session', data: data
       return false

      options.session = data.session
      return true

     handleResponse: (data, options) ->
      if not data.session?
       @onerror 'RPC without session', data: data
       return false

      return true

     _onSession: (data, options) ->
      @session = options.session
      @onSession? @session

     createSession: (callback) ->
      @onSession = callback
      @send 'newSession', null, (@_onSession.bind this)


    MultiSession =
     session: null
     send: ->
      throw new Error 'MultiSession port cannot send messages'
      return false

     handleCall: SingleSession.handleCall
     handleResponse: SingleSession.handleResponse

