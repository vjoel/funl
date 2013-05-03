module Funl
  module Blobber
    MARSHAL_TYPE  = "marshal"
    YAML_TYPE     = "yaml"
    JSON_TYPE     = "json"
    MSGPACK_TYPE  = "msgpack"
    
    # Returns something which responds to #dump(obj) and #load(str).
    def self.for type
      case type
      when MARSHAL_TYPE
        Marshal
      when YAML_TYPE
        require 'yaml'
        YAML
      when JSON_TYPE
        require 'yajl'
        require 'yajl/json_gem'
        ## would 'json' conflict with yajl required from other libs?
        JSON
      when MSGPACK_TYPE
        require 'msgpack'
        MessagePack
      else
        raise ArgumentError, "unknown type: #{type.inspect}"
      end
    end
  end
end
