require 'logger'
require 'funl/stream'
require 'funl/message'
require 'funl/blobber'

module Funl
  # Assigns a unique sequential ids to each message and relays it to its
  # destinations.
  class MessageSequencer
    include Funl::Stream

    attr_reader :server
    attr_reader :server_thread
    attr_reader :streams
    attr_reader :tick
    attr_reader :log
    attr_reader :stream_type
    attr_reader :message_class
    attr_reader :blob_type
    attr_reader :greeting
    attr_reader :subscribers
    
    def initialize server, *conns, log: Logger.new($stderr),
        stream_type: ObjectStream::MSGPACK_TYPE,
        message_class: Message,
        blob_type: Blobber::MSGPACK_TYPE,
        tick: 0

      @server = server
      @log = log
      @stream_type = stream_type
      @message_class = message_class
      @blob_type = blob_type
      @greeting = default_greeting
      @tick = tick

      @streams = []
      conns.each do |conn|
        try_conn conn
      end
      
      @subscribers_to_all = [] # [conn, ...]
      @subscribers = Hash.new {|h, tag| h[tag] = []} # tag => [conn, ...]
      @tags = Hash.new {|h, conn| h[conn] = []} # conn => [tag, ...]
    end

    def default_greeting
      {
        "blob" => blob_type
      }.freeze # can't change after initial conns read it
    end

    def try_conn conn
      stream = message_server_stream_for(conn)
      current_greeting = greeting.merge({"tick" => tick})
      if write_succeeds?(current_greeting, stream)
        log.debug {"connected #{stream.inspect}"}
        streams << stream
      end
    end
    private :try_conn

    def start
      @server_thread = Thread.new do
        run
      end
    end

    def stop
      server_thread.kill if server_thread
    end

    def wait
      server_thread.join
    end

    def run
      loop do
        readables, _ = select [server, *streams]

        readables.each do |readable|
          case readable
          when server
            begin
              conn, addr = readable.accept_nonblock
              log.debug {"accepted #{conn.inspect} from #{addr.inspect}"}
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
            rescue IOError, SystemCallError => ex
              log.debug {"closing #{readable}: #{ex}"}
              reject_stream readable
            else
              log.debug {
                "read #{msgs.size} messages from #{readable.peer_name}"}
            end

            msgs.each do |msg|
              if msg.control?
                handle_control readable, *msg.control_op
              else
                handle_message msg
              end
            end
          end
        end
      end
    rescue => ex
      log.error ex
      raise
    end

    def handle_control stream, op_type, tags = nil
      log.debug {"#{stream} #{op_type} #{tags}"}

      case op_type
      when SUBSCRIBE_ALL
        @subscribers_to_all += [stream]
        ack = Message.control(op_type)
        ack.global_tick = tick
        write_succeeds?(ack, stream)
      
      when SUBSCRIBE
        tags.each do |tag|
          @subscribers[tag] += [stream]
        end
        @tags[stream] += tags
        ack = Message.control(op_type, tags)
        ack.global_tick = tick
        write_succeeds?(ack, stream)

      when UNSUBSCRIBE_ALL
        @subscribers_to_all.delete stream

      when UNSUBSCRIBE
        tags.each do |tag|
          @subscribers[tag].delete stream
        end
        @tags[stream] -= tags

      else
        log.error "bad operation: #{op_type.inspect}"
        return
      end
    end

    def handle_message msg
      log.debug {"handling message #{msg.inspect}"}

      @tick += 1
      msg.global_tick = tick
      msg.delta = nil

      tags = msg.tags
      dest_streams =
        if !tags or (tags.empty? rescue true)
          @subscribers_to_all.dup
        else
          tags.inject(@subscribers_to_all) {|a,tag| a + @subscribers[tag]}
        end

      dest_streams.each do |stream|
        write_succeeds? msg, stream
      end
    end
    private :handle_message

    def write_succeeds? data, stream
      stream << data
      true
    rescue IOError, SystemCallError => ex
      log.debug {"closing #{stream}: #{ex}"}
      reject_stream stream
      false
    end
    private :write_succeeds?
  end

  def reject_stream stream
    stream.close unless stream.closed?
    if streams.include? stream
      streams.delete stream
      @subscribers_to_all.delete stream
      tags = @tags.delete stream
      if tags
        tags.each do |tag|
          @subscribers[tag].delete stream
        end
      end
    end
  end
end
