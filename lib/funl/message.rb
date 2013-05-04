module Funl
  class Message
    # Unique (per funl instance) sequential id of client who sent message.
    attr_accessor :client_id

    # Client's sequential id of message, unique only in client scope.
    attr_accessor :local_tick

    # Global sequential id of message, unique in scope of funl instance.
    # In client request to funl, this means last ack-ed global tick.
    # Assummed to be 64 bits, to avoid rollover errors.
    attr_accessor :global_tick

    # In client request, how far ahead of ack this message is. When
    # messages are pipelined, delta > 1.
    attr_accessor :delta

    attr_accessor :tags

    # Application-dependent payload data. See blobber.rb.
    attr_accessor :blob
    
    def initialize(*args)
      @client_id, @local_tick, @global_tick, @delta, @tags, @blob = *args
    end
    
    def self.[](
      client: nil, local: nil, global: nil, delta: nil, tags: nil, blob: nil)
      new client, local, global, delta, tags, blob
    end

    def inspect
      d = delta ? "+#{delta}" : nil
      t = tags ? " #{tags}" : nil
      s = [
        "client #{client_id}",
        "local #{local_tick}",
        "global #{global_tick}#{d}"
      ].join(", ")
      "<Message: #{s}#{t}>"
    end
    
    def to_a
      [@client_id, @local_tick, @global_tick, @delta, @tags, @blob]
    end

    def == other
      other.kind_of? Message and
        @client_id = other.client_id and
        @local_tick = other.local_tick and
        @global_tick = other.global_tick and
        @delta = other.delta and
        @tags = other.tags and
        @blob = other.blob
    end
    alias eql? ==
    
    def hash
      @client_id.hash ^ @local_tick.hash ^ @global_tick.hash
    end
    
    # Call with Packer, nil, or IO. If +pk+ is nil, returns string. If +pk+ is
    # a Packer, returns the Packer, which will need to be flushed. If +pk+ is
    # IO, returns nil.
    def to_msgpack(pk = nil)
      case pk
      when MessagePack::Packer
        pk.write_array_header(6) ## redundant, unless omit delta / tags
        pk.write @client_id
        pk.write @local_tick
        pk.write @global_tick
        pk.write @delta
        pk.write @tags
        pk.write @blob
        return pk
      
      else # nil or IO
        MessagePack.pack(self, pk)
      end
    end
    
    def to_json
      to_a.to_json
    end

    def self.from_serialized ary
      new *ary
    end

    def self.from_msgpack(src) ## not used by ObjectStream
      case src
      when MessagePack::Unpacker
        new(*src.read) ## do this without allocating array?
      
      when IO, StringIO
        from_msgpack(MessagePack::Unpacker.new(src))
      
      else # String
        from_msgpack(MessagePack::Unpacker.new.feed(src))
      end
    end
  end
end
