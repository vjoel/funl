require 'funl/client'
require 'funl/message-sequencer'
require 'funl/client-sequencer'
require 'socket'
require 'tmpdir'

include Funl

require 'minitest/autorun'

class TestClient < MiniTest::Unit::TestCase
  def setup
    @dir = Dir.mktmpdir "funl-test-client-"
    @cseq_path = File.join(@dir, "cseq")
    @seq_path = File.join(@dir, "seq")
    @logfile = File.join(@dir, "log")
  end
  
  def teardown
    FileUtils.remove_entry @dir
  end
  
  def assert_no_log_errors
    loglines = File.read(@logfile)
    assert_nil(loglines[/^E/], loglines)
  end
  
  def test_client
    log = Logger.new(@logfile)
    
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
    
    # can't interact with seq unless subclass Client and use return
    # value of super in #initialize
    
    assert_no_log_errors
  ensure
    cseq.stop rescue nil
    seq.stop rescue nil
  end
end
