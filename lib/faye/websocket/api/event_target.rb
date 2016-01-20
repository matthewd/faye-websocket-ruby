module Faye::WebSocket::API
  module EventTarget

    include ::WebSocket::Driver::EventEmitter
    events = %w[open message error close]

    events.each do |event_type|
      define_method "on#{event_type}=" do |handler|
        @supervisor.defer do
          flush(event_type, handler)
          instance_variable_set("@on#{event_type}", handler)
        end
      end
    end

    def add_event_listener(event_type, listener, use_capture = false)
      add_listener(event_type, &listener)
    end

    def add_listener(event_type, callable = nil, &block)
      listener = callable || block
      @supervisor.defer do
        flush(event_type, listener)
        super(event_type, &listener)
      end
    end

    def remove_event_listener(event_type, listener, use_capture = false)
      remove_listener(event_type, &listener)
    end

    def dispatch_event(event)
      event.target = event.current_target = self
      event.event_phase = Event::AT_TARGET

      listener = instance_variable_get("@on#{ event.type }")
      count    = listener_count(event.type)

      unless listener or count > 0
        @buffers ||= Hash.new { |k,v| k[v] = [] }
        @buffers[event.type].push(event)
      end

      listener.call(event) if listener
      emit(event.type, event)
    end

  private

    def flush(event_type, listener)
      if buffer = defined?(@buffers) && @buffers && @buffers.delete(event_type.to_s)
        buffer.each { |event| listener.call(event) }
      end
    end

  end
end
