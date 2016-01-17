module Faye
  class RackStream

    def initialize(supervisor, socket)
      @supervisor    = supervisor
      @socket_object = socket
      @stream_send   = socket.env['stream.send']

      hijack_rack_socket

    end

    def hijack_rack_socket
      return unless @socket_object.env['rack.hijack']

      @socket_object.env['rack.hijack'].call
      @rack_hijack_io = @socket_object.env['rack.hijack_io']

      @supervisor.attach(@rack_hijack_io, self)
    end

    def clean_rack_hijack
      return unless @rack_hijack_io
      @supervisor.detach(@rack_hijack_io, self)
      @rack_hijack_io = nil
    end

    def close
      clean_rack_hijack
    end

    def each(&callback)
      @stream_send ||= callback
    end

    def fail
    end

    def receive(data)
    end

    def write(data)
      return @rack_hijack_io.write(data) if @rack_hijack_io
      return @stream_send.call(data) if @stream_send
    rescue => e
      fail if EOFError === e
    end

  end
end
