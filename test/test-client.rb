require 'funl/client'
require 'funl/blobber'
require 'funl/message-sequencer'
require 'funl/client-sequencer'
require 'socket'
require 'tmpdir'

include Funl

require 'minitest/autorun'

class TestClient < Minitest::Test
  attr_reader :log

  def setup
    @dir = Dir.mktmpdir "funl-test-client-"
    @cseq_path = File.join(@dir, "cseq")
    @seq_path = File.join(@dir, "seq")
    @log = Logger.new($stderr)
    log.level = Logger::WARN
  end
  
  def teardown
    FileUtils.remove_entry @dir
  end
  
  def test_client
    cseq_sock = UNIXServer.new(@cseq_path)
    cseq = ClientSequencer.new cseq_sock, log: log
    cseq.start
    
    seq_sock = UNIXServer.new(@seq_path)
    seq = MessageSequencer.new  seq_sock, log: log
    seq.start
    
    client = Client.new(
      seq: UNIXSocket.new(@seq_path),
      cseq: UNIXSocket.new(@cseq_path),
      log: log)
    
    client.start
    
    assert_equal(0, client.client_id)
    assert_equal(0, client.start_tick)
    assert_equal(Funl::Blobber::MSGPACK_TYPE, client.blob_type)
  ensure
    cseq.stop rescue nil
    seq.stop rescue nil
  end
end
