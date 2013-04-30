require 'logger'
require 'object-stream'

module Funl
  # Assigns unique ids to clients.
  class ClientSequencer
    attr_reader :server
    attr_reader :server_thread
    attr_reader :next_id
    attr_reader :log
    attr_reader :stream_type

    def initialize server, *conns, log: Logger.new($stderr),
        stream_type: ObjectStream::MSGPACK_TYPE

      @server = server
      @log = log
      @stream_type = stream_type

      @next_id = 0 ## read from file etc.

      conns.each do |conn|
        handle_conn conn
      end
    end

    def start
      @server_thread = Thread.new do
        run
      end
    end

    def stop
      server_thread.kill if server_thread
    end

    def run
      loop do
        conn = server.accept
        log.debug {"accepted #{conn.inspect}"}
        handle_conn conn
      end
    rescue => ex
      log.error ex
      raise
    end

    def handle_conn conn
      stream = ObjectStream.new(conn, type: stream_type)
      stream << [next_id] # boxed for json
    rescue => ex
      log.error "write error for client #{next_id}: #{ex}"
    else
      log.info "recognized client #{next_id}"
    ensure
      stream.close if stream and not stream.closed?
      @next_id += 1
    end
  end
end
