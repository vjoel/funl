require 'logger'
require 'msgpack'
require 'funl/message'

module Funl
  # Assigns a unique sequential ids to each message and relays it to its
  # destinations.
  class MessageSequencer
    attr_reader :server
    attr_reader :server_thread
    attr_reader :conns
    attr_reader :tick
    attr_reader :log

    def initialize server, *conns, log: Logger.new($stderr)
      @server = server
      @log = log

      @tick = 0 ## read from file etc.

      @conns = conns.select do |conn|
        write_succeeds? tick, conn and
          log.info "connected #{conn.inspect}"
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
        readables, _ = select [server, *@conns]

        readables.each do |readable|
          case readable
          when server
            begin
              conn, addr = readable.accept_nonblock
              log.info "accepted #{conn.inspect} from #{addr.inspect}"
              if write_succeeds? tick, conn
                @conns << conn
              end
            rescue IO::WaitReadable
              next
            end

          else
            log.debug {"readable = #{readable.inspect}"}
            begin
              msg = Message.from_msgpack(readable)
            rescue => ex #Errno::ECONNRESET, EOFError
              log.debug {"closing #{readable.inspect}: #{ex}"}
              @conns.delete readable
              readable.close unless readable.closed?
            else
              handle_message msg
            end
          end
        end
      end
    rescue => ex
      log.error ex
      raise
    end

    def handle_message msg
      log.debug {"handling message #{msg.inspect}"}
      @tick += 1
      msg.global_tick = tick
      msg.delta = nil
      @conns.keep_if do |conn|
        write_succeeds? msg, conn
      end
    end

    def write_succeeds? data, conn
      MessagePack.pack data, conn
      true
    rescue => ex
      log.debug {"closing #{conn.inspect}: #{ex}"}
      conn.close unless conn.closed?
      false
    end
  end
end
