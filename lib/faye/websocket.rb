# API references:
#
# * http://dev.w3.org/html5/websockets/
# * http://dvcs.w3.org/hg/domcore/raw-file/tip/Overview.html#interface-eventtarget
# * http://dvcs.w3.org/hg/domcore/raw-file/tip/Overview.html#interface-event

require 'forwardable'
require 'stringio'
require 'uri'
require 'concurrent'
require 'websocket/driver'

module Faye
  autoload :EventSource, File.expand_path('../eventsource', __FILE__)
  autoload :RackStream,  File.expand_path('../rack_stream', __FILE__)

  class WebSocket
    root = File.expand_path('../websocket', __FILE__)

    autoload :Adapter, root + '/adapter'
    autoload :API,     root + '/api'
    autoload :Client,  root + '/client'
    autoload :Supervisor, root + '/supervisor'

    ADAPTERS = {
      'goliath'  => :Goliath,
      'rainbows' => :Rainbows,
      'thin'     => :Thin
    }

    def self.determine_url(env)
      scheme = secure_request?(env) ? 'wss:' : 'ws:'
      "#{ scheme }//#{ env['HTTP_HOST'] }#{ env['REQUEST_URI'] }"
    end

    def self.load_adapter(backend)
      const = Kernel.const_get(ADAPTERS[backend]) rescue nil
      require(backend) unless const
      path = File.expand_path("../adapters/#{backend}.rb", __FILE__)
      require(path) if File.file?(path)
    end

    def self.secure_request?(env)
      return true if env['HTTPS'] == 'on'
      return true if env['HTTP_X_FORWARDED_SSL'] == 'on'
      return true if env['HTTP_X_FORWARDED_SCHEME'] == 'https'
      return true if env['HTTP_X_FORWARDED_PROTO'] == 'https'
      return true if env['rack.url_scheme'] == 'https'

      return false
    end

    def self.websocket?(env)
      ::WebSocket::Driver.websocket?(env)
    end

    attr_reader :env
    include API

    def self.default_supervisor
      @default_supervisor ||= Supervisor.new
    end

    def initialize(env, protocols = nil, options = {})
      @supervisor = options.delete(:supervisor) || self.class.default_supervisor

      @env = env
      @url = WebSocket.determine_url(@env)

      super(options) { ::WebSocket::Driver.rack(self, :max_length => options[:max_length], :protocols => protocols) }

      @stream = Stream.new(@supervisor, self)

      if callback = @env['async.callback']
        callback.call([101, {}, @stream])
      end
    end

    def start_driver
      return if @driver.nil? || @driver_started
      @driver_started = true
      @supervisor.defer { @driver.start }
    end

    def rack_response
      start_driver
      [ -1, {}, [] ]
    end

    class Stream < RackStream
      def fail
        @socket_object.__send__(:finalize_close)
      end

      def receive(data)
        @socket_object.__send__(:parse, data)
      end
    end

  end
end
