require 'forwardable'

module Faye
  class WebSocket

    class Client
      class FakeSupervisor
        def defer(&block)
          Concurrent.global_io_executor << block
        end
      end

      extend Forwardable
      include API

      DEFAULT_PORTS    = {'http' => 80, 'https' => 443, 'ws' => 80, 'wss' => 443}
      SECURE_PROTOCOLS = ['https', 'wss']

      def_delegators :@driver, :headers, :status

      def initialize(url, protocols = nil, options = {})
        @supervisor = FakeSupervisor.new

        @url = url
        super(options) { ::WebSocket::Driver.client(self, :max_length => options[:max_length], :protocols => protocols) }

        proxy       = options.fetch(:proxy, {})
        endpoint    = URI.parse(proxy[:origin] || @url)
        port        = endpoint.port || DEFAULT_PORTS[endpoint.scheme]
        @secure     = SECURE_PROTOCOLS.include?(endpoint.scheme)
        @origin_tls = options.fetch(:tls, {})
        @socket_tls = proxy[:origin] ? proxy.fetch(:tls, {}) : @origin_tls

        #if proxy[:origin]
        #  @proxy = @driver.proxy(proxy[:origin])
        #  if headers = proxy[:headers]
        #    headers.each { |name, value| @proxy.set_header(name, value) }
        #  end

        #  @proxy.on(:connect) do
        #    uri    = URI.parse(@url)
        #    secure = SECURE_PROTOCOLS.include?(uri.scheme)
        #    @proxy = nil

        #    @stream.start_tls(@origin_tls) if secure
        #    @driver.start
        #  end

        #  @proxy.on(:error) do |error|
        #    @driver.emit(:error, error)
        #  end
        #end

        @stream = Socket.tcp(endpoint.host, port)
        #worker = @proxy || @driver
        worker = @driver
        Concurrent.global_io_executor.post do
          worker.start

          Thread.new do
            Thread.current.abort_on_exception = true
            loop do
              begin
                break if @stream.closed?
                parse @stream.read_nonblock(4096)
              rescue EOFError
                break
              rescue IO::WaitReadable
                IO.select([@stream])
              end
            end

            finalize_close
          end
        end

      rescue => error
        emit_error("Network error: #{url}: #{error.message}")
        finalize_close
      end
    end

  end
end
