require 'funl/message-sequencer'
require 'socket'

include Funl

require 'minitest/autorun'

class TestSubscribe < Minitest::Test
  attr_reader :log, :mseq

  def setup
    @log = Logger.new($stderr)
    log.level = Logger::WARN
    
    client_socks = []
    server_socks = []
    2.times do
      cl, sv = UNIXSocket.pair
      client_socks << cl
      server_socks << sv
    end
    
    dummy, _ = UNIXSocket.pair

    @mseq = MessageSequencer.new dummy, *server_socks, log: log
    mseq.start
    
    @streams = client_socks.each_with_index.map do |s,i|
      stream = ObjectStreamWrapper.new(s, type: mseq.stream_type)
      stream.write_to_outbox({"client_id" => "client #{i}"})
      global_tick = stream.read["tick"]
      stream.expect Message
      stream
    end
  end
  
  def teardown
    mseq.stop rescue nil
  end

  def test_single_tag
    snd, rcv = @streams
    rcv << Message.control(SUBSCRIBE, ["foo"])
    ack = rcv.read
    assert ack.control?
    assert_equal 0, ack.global_tick
    
    snd << Message[
      client: 0, local: 0, global: 0, delta: 1,
      tags: ["bar"], blob: ""]
    snd << Message[
      client: 0, local: 0, global: 0, delta: 2,
      tags: ["foo"], blob: ""]
    
    m = rcv.read
    assert_equal 2, m.global_tick
    assert_equal ["foo"], m.tags
  end
  
  def test_multiple_tag
    snd, rcv = @streams
    rcv << Message.control(SUBSCRIBE, ["foo", "bar"])
    ack = rcv.read
    assert ack.control?
    assert_equal 0, ack.global_tick
    
    snd << Message[
      client: 0, local: 0, global: 0, delta: 1,
      tags: ["bar"], blob: ""]
    snd << Message[
      client: 0, local: 0, global: 0, delta: 2,
      tags: ["foo"], blob: ""]
    
    m = rcv.read
    assert_equal 1, m.global_tick
    assert_equal ["bar"], m.tags
    m = rcv.read
    assert_equal 2, m.global_tick
    assert_equal ["foo"], m.tags
  end
  
  def test_multiple_receiver
    snd, rcv = @streams
    @streams.each do |stream|
      stream << Message.control(SUBSCRIBE, ["foo"])
      ack = stream.read
      assert ack.control?
      assert_equal 0, ack.global_tick
    end
    
    snd << Message[
      client: 0, local: 0, global: 0, delta: 1,
      tags: ["foo"], blob: ""]
    
    @streams.each do |stream|
      m = stream.read
      assert_equal 1, m.global_tick
      assert_equal ["foo"], m.tags
    end
  end

  def test_unsubscribe
    snd, rcv = @streams
    rcv << Message.control(SUBSCRIBE, ["foo"])
    ack = rcv.read
    assert ack.control?
    assert_equal 0, ack.global_tick
    
    snd << Message[
      client: 0, local: 0, global: 0, delta: 1,
      tags: ["foo"], blob: ""]
    
    m = rcv.read
    assert_equal 1, m.global_tick
    assert_equal ["foo"], m.tags

    rcv << Message.control(UNSUBSCRIBE, ["foo"])
    Thread.pass
    
    snd << Message[
      client: 0, local: 0, global: 0, delta: 1,
      tags: ["foo"], blob: ""]
    Thread.pass
    
    rcv << Message.control(SUBSCRIBE, ["foo"])
    ack = rcv.read
    assert ack.control?
    assert_equal 2, ack.global_tick
    
    snd << Message[
      client: 0, local: 0, global: 0, delta: 1,
      tags: ["foo"], blob: ""]
    
    m = rcv.read
    assert_equal 3, m.global_tick
    assert_equal ["foo"], m.tags
  end
  
  def test_subscribe_all
    snd, rcv = @streams
    rcv << Message.control(SUBSCRIBE_ALL)
    ack = rcv.read
    assert ack.control?
    assert_equal 0, ack.global_tick
    
    snd << Message[
      client: 0, local: 0, global: 0, delta: 1,
      tags: ["foo"], blob: ""]
    
    m = rcv.read
    assert_equal 1, m.global_tick
    assert_equal ["foo"], m.tags

    rcv << Message.control(UNSUBSCRIBE_ALL)
    Thread.pass
    
    snd << Message[
      client: 0, local: 0, global: 0, delta: 1,
      tags: ["foo"], blob: ""]
    Thread.pass
    
    rcv << Message.control(SUBSCRIBE_ALL)
    ack = rcv.read
    assert ack.control?
    assert_equal 2, ack.global_tick
    
    snd << Message[
      client: 0, local: 0, global: 0, delta: 1,
      tags: ["foo"], blob: ""]
    
    m = rcv.read
    assert_equal 3, m.global_tick
    assert_equal ["foo"], m.tags
  end
end
