require 'funl/message-sequencer'
require 'socket'
require 'tmpdir'

include Funl

require 'minitest/autorun'

class TestMessageSequencer < Minitest::Test
  def setup
    @dir = Dir.mktmpdir "funl-test-mseq-"
    @path = File.join(@dir, "sock")
    @logfile = File.join(@dir, "log")
    @n_clients = 3
  end
  
  def teardown
    FileUtils.remove_entry @dir
  end
  
  def assert_no_log_errors
    loglines = File.read(@logfile)
    assert_nil(loglines[/^E/], loglines)
  end
  
  def test_initial_conns
    as = []; bs = []
    @n_clients.times {a, b = UNIXSocket.pair; as << a; bs << b}
    mseq = MessageSequencer.new nil, *as, log: Logger.new(@logfile)
    bs.each_with_index do |b, i|
      stream = ObjectStream.new(b, type: mseq.stream_type)
      stream.write_to_outbox({"client_id" => "test_initial_conns #{i}"})
      global_tick = stream.read["tick"]
      assert_equal 0, global_tick
    end
    assert_no_log_errors
  end
  
  def test_later_conns
    stream_type = ObjectStream::MSGPACK_TYPE
    log = Logger.new(@logfile)
    ## should be easier to turn this on:
    #log = Logger.new($stderr)
    #log.level = Logger::DEBUG

    svr = UNIXServer.new(@path)
    pid = fork do
      log.progname = "mseq"
      mseq = MessageSequencer.new svr, log: log,  stream_type: stream_type
      mseq.start
      sleep
    end
    
    log.progname = "client"
    streams = (0...@n_clients).map do
      conn = UNIXSocket.new(@path)
      stream = ObjectStream.new(conn, type: stream_type)
      stream.write_to_outbox{{"client_id" => "test_later_conns"}}
      global_tick = stream.read["tick"]
      assert_equal 0, global_tick
      stream
    end
    
    m1 = Message[
      client: 0, local: 12, global: 34,
      delta: 1, tags: ["foo"], blob: "BLOB"]
    send_msg(src: streams[0], message: m1, dst: streams, expected_tick: 1)
    
    if @n_clients > 1
      m2 = Message[
        client: 1, local: 23, global: 45,
        delta: 4, tags: ["bar"], blob: "BLOB"]
      send_msg(src: streams[1], message: m2, dst: streams, expected_tick: 2)
    end
    
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
    
    assert_equal @n_clients, replies.size

    replies.each do |r|
      assert_equal(message.client_id, r.client_id)
      assert_equal(message.local_tick, r.local_tick)
      assert_equal(expected_tick, r.global_tick)
      assert_equal(nil, r.delta)
      assert_equal(message.tags, r.tags)
      assert_equal(message.blob, r.blob)
    end
  end

  def test_persist
    saved_tick = 0
    n_write = 0
    3.times do |i|
      assert_equal n_write, saved_tick

      path = "#{@path}-#{i}"
      svr = UNIXServer.new(path)
      mseq = Funl::MessageSequencer.new svr, log: Logger.new(@logfile),
        tick: saved_tick
      mseq.start

      conn = UNIXSocket.new(path)
      stream = ObjectStream.new(conn, type: mseq.stream_type)
      stream.write_to_outbox{{"client_id" => "test_persist"}} # not needed
      tick = stream.read["tick"]
      assert_equal n_write, tick

      stream.write Message.new
      stream.read
      n_write += 1

      mseq.stop
      mseq.wait
      saved_tick = mseq.tick
    end

    assert_no_log_errors
  ensure
    mseq.stop rescue nil
  end
end
