require 'logger'
require 'funl/stream'

module Funl
  # Generic client base class. Manages the setup and handshake on the streams
  # to the client sequencer and the message sequencer.
  class Client
    include Funl::Stream

    attr_reader :log
    attr_reader :stream_type
    attr_reader :client_id
    attr_reader :greeting
    attr_reader :start_tick
    attr_reader :blob_type

    # Returns +seq+, a stream to the sequencer. Child class must define an
    # initialize method that calls super and uses this return value.
    def initialize(seq: seq!, cseq: cseq!,
          log: Logger.new($stderr),
          stream_type: ObjectStream::MSGPACK_TYPE)

      @log = log
      @stream_type = stream_type ## discover this thru connections

      seq = client_stream_for(seq)
      cseq = client_stream_for(cseq)

      @cseq_read_client_id = proc do
        @cseq_read_client_id = nil
        log.info "getting client_id from cseq"
        @client_id = cseq.read["client_id"]
        log.info "client_id = #{client_id}"
        cseq.close rescue nil; cseq = nil
      end

      @seq_read_greeting = proc do
        @seq_read_greeting = nil
        log.info "getting greeting from seq"
        @greeting = seq.read
        @start_tick = greeting["tick"]
        log.info "start_tick = #{start_tick}"
        @blob_type = greeting["blob"]
        log.info "blob_type = #{blob_type}"
      end

      return seq
        # don't keep seq in ivar, in case we are delegating (e.g. to worker)
    end

    # Handshake with both cseq and seq. Does not start any threads--that is left
    # to subclasses. Yields after getting client id so that caller can set
    # log.progname, for example.
    def start
      @cseq_read_client_id.call
      yield if block_given?
      @seq_read_greeting.call
    end
  end
end
