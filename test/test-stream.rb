require 'funl/stream'
require 'stringio'
require 'logger'

require 'minitest/autorun'

class TestStream < MiniTest::Unit::TestCase
  include Funl::Stream
  
  attr_reader :client_id
  attr_reader :log
  
  def setup
    @sio = StringIO.new
    @logio = StringIO.new
    @log = Logger.new(@logio)
  end
  
  def test_greeting
    @client_id = 42
    client = client_stream_for @sio, type: ObjectStream::MSGPACK_TYPE
    client.write "message"
    
    @sio.rewind

    server = server_stream_for @sio, type: ObjectStream::MSGPACK_TYPE
    m = server.read
    
    assert_equal "message", m
    assert_equal "client 42", server.peer_name
  end
end
