require 'logger'
require 'funl/message'
require 'funl/blobber'
require 'object-stream'

module Funl
  # Assigns a unique sequential ids to each message and relays it to its
  # destinations.
  class MessageSequencer
    attr_reader :server
    attr_reader :server_thread
    attr_reader :streams
    attr_reader :tick
    attr_reader :log
    attr_reader :stream_type
    attr_reader :greeting
    
    DEFAULT_GREETING = {
      "blob" => Funl::Blobber::MSGPACK_TYPE
    }

    def initialize server, *conns, log: Logger.new($stderr),
        stream_type: ObjectStream::MSGPACK_TYPE,
        greeting: DEFAULT_GREETING

      @server = server
      @log = log
      @stream_type = stream_type
      @greeting = greeting

      @tick = 0 ## read from file etc.

      @streams = []
      conns.each do |conn|
        try_conn conn
      end
    end

    def try_conn conn
      stream = ObjectStream.new(conn, type: stream_type)
      current_greeting = greeting.merge({"tick" => tick})
      if write_succeeds?(current_greeting, stream)
        log.info "connected #{stream.inspect}"
        
        stream.consume do |h|
          client_id = h["client_id"]
          stream.peer_name = "client #{client_id}"
          log.info "peer is #{stream.peer_name}"
        end
        stream.expect Message
        
        @streams << stream
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
        readables, _ = select [server, *streams]

        readables.each do |readable|
          case readable
          when server
            begin
              conn, addr = readable.accept_nonblock
              log.info "accepted #{conn.inspect} from #{addr.inspect}"
              try_conn conn
            rescue IO::WaitReadable
              next
            end

          else
            log.debug {"readable = #{readable}"}
            begin
              msgs = []
              readable.read do |msg|
                msgs << msg
              end
            rescue => ex #Errno::ECONNRESET, EOFError
              log.debug {"closing #{readable}: #{ex}"}
              @streams.delete readable
              readable.close unless readable.closed?
            else
              log.debug {
                "read #{msgs.size} messages from #{readable.peer_name}"}
            end

            msgs.each do |msg|
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
      @streams.keep_if do |stream|
        write_succeeds? msg, stream
      end
    end

    def write_succeeds? data, stream
      stream << data
      true
    rescue => ex
      log.debug {"closing #{stream}: #{ex}"}
      stream.close unless stream.closed?
      false
    end
  end
end
