require 'funl/client-sequencer'
require 'socket'
require 'tmpdir'
require 'stringio'

require 'minitest/autorun'

class TestClientSequencer < MiniTest::Unit::TestCase
  def setup
    @dir = Dir.mktmpdir "funl-test-cseq-"
    @path = File.join(@dir, "sock")
    @sio = StringIO.new
  end
  
  def teardown
    FileUtils.remove_entry @dir
  end
  
  def assert_no_log_errors
    @sio.rewind
    log = @sio.read
    assert_nil(log[/^E/], log)
  end
  
  def test_initial_conns
    as = []; bs = []
    3.times {a, b = UNIXSocket.pair; as << a; bs << b}
    cseq = Funl::ClientSequencer.new nil, *as, log: Logger.new(@sio)
    bs.each_with_index do |b, i|
      stream = ObjectStream.new(b, type: cseq.stream_type)
      client_id = stream.read[0]
      assert_equal i, client_id
    end
    assert_no_log_errors
  end
  
  def test_later_conns
    svr = UNIXServer.new(@path)
    cseq = Funl::ClientSequencer.new svr, log: Logger.new(@sio)
    cseq.start
    3.times do |i|
      conn = UNIXSocket.new(@path)
      stream = ObjectStream.new(conn, type: cseq.stream_type)
      client_id = stream.read[0]
      assert_equal i, client_id
    end
    assert_no_log_errors
  ensure
    cseq.stop rescue nil
  end
end
