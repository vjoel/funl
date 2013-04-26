require 'logger'
require 'msgpack'

module Funl
  # Assigns unique ids to clients.
  class ClientSequencer
    attr_reader :server
    attr_reader :server_thread
    attr_reader :next_id
    attr_reader :log

    def initialize server, *conns, log: Logger.new($stderr)
      @server = server
      @log = log

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
      MessagePack.pack next_id, conn
    rescue => ex
      log.error "write error for client #{next_id}: #{ex}"
    else
      log.info "recognized client #{next_id}"
    ensure
      conn.close unless conn.closed?
      @next_id += 1
    end
  end
end
