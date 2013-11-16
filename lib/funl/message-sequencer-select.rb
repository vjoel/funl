require 'logger'
require 'funl/message-sequencer'

module Funl
  class MessageSequencerSelect < MessageSequencer
    attr_reader :streams
    
    def init_selector
      @streams = []
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

    def accept_conn
      conn, addr = server.accept_nonblock
      log.debug {"accepted #{conn.inspect} from #{addr.inspect}"}
      try_conn conn
    rescue IO::WaitReadable
    end
    private :accept_conn

    def read_conn readable
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
          handle_message msg, readable
        end
      end
    end
    private :read_conn

    def run
      loop do
        readables, _ = select [server, *streams]

        readables.each do |readable|
          case readable
          when server
            accept_conn
          else
            read_conn readable
          end
        end
      end
    rescue => ex
      log.error ex
      raise
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
end
