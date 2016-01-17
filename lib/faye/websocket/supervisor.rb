require 'nio'

module Faye
  class WebSocket
    class Supervisor
      def initialize
        @nio = NIO::Selector.new
        @map = {}
        @stopping = false
        @todo = Queue.new

        Thread.new do
          Thread.current.abort_on_exception = true
          run
        end
      end

      def attach(io, stream)
        @todo << [:_attach, io, stream]
        @nio.wakeup
      end

      def detach(io, stream)
        @todo << [:_detach, io, stream]
        @nio.wakeup
      end

      def stop
        @stopping = true
        @nio.wakeup
      end

      def _attach(io, stream)
        @map[io] = stream
        @nio.register(io, :r)
      end

      def _detach(io, stream)
        @nio.deregister(io)
        @map.delete io
      end

      def run
        loop do
          if @stopping
            @nio.close
            break
          end

          until @todo.empty?
            send(*@todo.pop(true))
          end

          if monitors = @nio.select
            monitors.each do |monitor|
              io = monitor.io
              stream = @map[io]

              begin
                stream.receive io.read_nonblock(4096)
              rescue IO::WaitReadable
                next
              rescue EOFError
                stream.fail
                stream.close
              end
            end
          end
        end
      end

      def defer(&block)
        Concurrent.global_io_executor << block
      end
    end
  end
end
