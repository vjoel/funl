require 'logger'
require 'funl/stream'
require 'funl/message'
require 'funl/blobber'

module Funl
  # Generic client base class. Manages the setup and handshake on the streams
  # to the client sequencer and the message sequencer.
  class Client
    include Funl::Stream

    attr_reader :seq
    attr_reader :cseq
    attr_reader :arc
    attr_reader :log
    attr_reader :stream_type
    attr_reader :message_class
    attr_reader :client_id
    attr_reader :greeting
    attr_reader :start_tick
    attr_reader :blob_type
    attr_reader :blobber

    def initialize(seq: seq!, cseq: cseq!, arc: nil,
          log: Logger.new($stderr),
          stream_type: ObjectStream::MSGPACK_TYPE,
          message_class: Message)

      @log = log
      @stream_type = stream_type ## discover this thru connections
      @message_class = message_class

      @seq = client_stream_for(seq)
      @cseq = client_stream_for(cseq)
      @arcio = arc
    end

    # Handshake with both cseq and seq. Does not start any threads--that is left
    # to subclasses. Yields after getting client id so that caller can set
    # log.progname, for example.
    def start
      cseq_read_client_id
      yield if block_given?
      seq_read_greeting
    end

    def subscribe tags
      seq << Message.control("subscribe", tags)
      ## wait for ack which has tick, ask arc for older messages
    end

    def subscribe_all
      seq << Message.control("subscribe_all")
      ## wait for ack which has tick, ask arc for older messages
    end

    def unsubscribe tags
      seq << Message.control("unsubscribe", tags)
    end

    def unsubscribe_all
      seq << Message.control("unsubscribe_all")
    end

    def cseq_read_client_id
      log.debug "getting client_id from cseq"
      @client_id = cseq.read["client_id"]
      log.info "client_id = #{client_id}"
      cseq.close rescue nil
      @cseq = nil
    end

    def seq_read_greeting
      log.debug "getting greeting from seq"
      @greeting = seq.read
      @start_tick = greeting["tick"]
      log.info "start_tick = #{start_tick}"
      @blob_type = greeting["blob"]
      log.info "blob_type = #{blob_type}"
      @blobber = Blobber.for(blob_type)
      seq.expect message_class

      @arc = @arcio && client_stream_for(@arcio, type: blob_type)
        # note: @arc is nil when client is the archiver itself
    end

    def arc_server_stream_for io
      server_stream_for(io, type: blob_type)
        # note: blob_type, not stream_type, since we are sending bare objects
    end
  end
end
