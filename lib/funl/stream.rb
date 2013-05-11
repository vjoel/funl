require 'object-stream'

module Funl
  # Mixin depends on stream_type, log, client_id, message_class.
  module Stream
    def client_stream_for io, type: stream_type
      ObjectStream.new(io, type: type).tap do |stream|
        stream.write_to_outbox {{"client_id" => client_id}}
          # client_id will be nil in the case of cseq, but that's ok.
      end
    end

    def server_stream_for io, type: stream_type
      ObjectStream.new(io, type: type).tap do |stream|
        stream.consume do |h|
          client_id = h["client_id"]
          stream.peer_name = "client #{client_id}"
          log.info "peer is #{stream.peer_name}"
        end
      end
    end
    
    def message_server_stream_for io, type: stream_type
      ObjectStream.new(io, type: type).tap do |stream|
        stream.consume do |h|
          client_id = h["client_id"]
          stream.peer_name = "client #{client_id}"
          log.info "peer is #{stream.peer_name}"
          stream.expect message_class
        end
      end
    end
  end
end
