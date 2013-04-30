require 'funl/message-sequencer'
require 'socket'
require 'tmpdir'

include Funl

require 'minitest/autorun'

class TestMessageSequencer < MiniTest::Unit::TestCase
  def setup
    @dir = Dir.mktmpdir "funl-test-mseq-"
    @path = File.join(@dir, "sock")
    @logfile = File.join(@dir, "log")
  end
  
  def teardown
    FileUtils.remove_entry @dir
  end
  
  def assert_no_log_errors
    log = File.read(@logfile)
    assert_nil(log[/^E/], log)
  end
  
  def test_initial_conns
    as = []; bs = []
    3.times {a, b = UNIXSocket.pair; as << a; bs << b}
    mseq = MessageSequencer.new nil, *as, log: Logger.new(@logfile)
    bs.each_with_index do |b, i|
      stream = ObjectStream.new(b, type: mseq.stream_type)
      global_tick = stream.read[0]
      assert_equal 0, global_tick
    end
    assert_no_log_errors
  end
  
  def test_later_conns
    stream_type = ObjectStream::MSGPACK_TYPE

    svr = UNIXServer.new(@path)
    pid = fork do
      begin
        mseq = MessageSequencer.new svr, log: Logger.new(@logfile),
          stream_type: stream_type
        mseq.start
        sleep
      rescue => ex
        p ex
        raise
      end
    end
    
    streams = (0..2).map do
      conn = UNIXSocket.new(@path)
      stream = ObjectStream.new(conn, type: stream_type)
      global_tick = stream.read[0]
      assert_equal 0, global_tick
      stream
    end
    
    m1 = Message[
      client: 0, local: 12, global: 34,
      delta: 1, tags: ["foo"], blob: "BLOB"]
    
    send_msg(src: streams[0], message: m1, dst: streams, expected_tick: 1)
    
    m2 = Message[
      client: 1, local: 23, global: 45,
      delta: 4, tags: ["bar"], blob: "BLOB"]
    
    send_msg(src: streams[1], message: m2, dst: streams, expected_tick: 2)
    
    assert_no_log_errors
  ensure
    Process.kill "TERM", pid if pid
  end

  def send_msg(src: nil, message: nil, dst: nil, expected_tick: nil)
    src << message
    
    replies = dst.map do |stream|
      stream.expect Message
      stream.read
    end
    
    replies.each do |r|
      assert_equal(message.client_id, r.client_id)
      assert_equal(message.local_tick, r.local_tick)
      assert_equal(expected_tick, r.global_tick)
      assert_equal(nil, r.delta)
      assert_equal(message.tags, r.tags)
      assert_equal(message.blob, r.blob)
    end
  end
end