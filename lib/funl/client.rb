require 'logger'
require 'object-stream'

module Funl
  class Client
    attr_reader :log
    attr_reader :stream_type
    attr_reader :client_id
    attr_reader :start_tick

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
        @client_id = cseq.read[0]
        log.info "client_id = #{client_id}"
        cseq.close; cseq = nil
      end

      @seq_read_tick = proc do
        @seq_read_tick = nil
        log.info "getting start_tick from seq"
        @start_tick = seq.read[0]
        log.info "seq says start_tick = #{@start_tick}"
      end

      return seq
        # don't keep seq in ivar, in case we are delegating (e.g. to worker)
    end

    def start
      @cseq_read_client_id.call
      yield if block_given? # let client set log.progname
      @seq_read_tick.call
    end

    def stream_for io
      ObjectStream.new(io, type: stream_type).tap do |stream|
        stream.write_to_buffer({"client_id" => client_id})
          # client_id will be nil in the case of cseq, but that's ok
          # because the remote never reads anyway.
      end
    end
  end
end
