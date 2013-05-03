require 'logger'
require 'object-stream'

module Funl
  class Client
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

      seq = stream_for(seq)
      cseq = stream_for(cseq)

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

    def start
      @cseq_read_client_id.call
      yield if block_given? # let client set log.progname
      @seq_read_greeting.call
    end

    def stream_for io
      ObjectStream.new(io, type: stream_type).tap do |stream|
        stream.write_to_object_buffer {{"client_id" => client_id}}
          # client_id will be nil in the case of cseq, but that's ok.
      end
    end

    def server_stream_for io
      ObjectStream.new(io, type: stream_type).tap do |stream|
        stream.consume do |h|
          client_id = h["client_id"]
          stream.peer_name = "client #{client_id}"
          log.info "peer is #{stream.peer_name}"
        end
      end
    end
  end
end
