require_relative 'funl-bench'

# Measure the message rate through the sequencer.
class MessageRateBenchmarkTask < BenchmarkTask
  def run make_stream
    n_msg = params[:n_msg] || 10
    n_cli = params[:n_cli] || 2
    
    streams = n_cli.times.map {|i| make_stream[i]}
    threads = n_cli.times.map do |i|
      Thread.new do
        n_msg.times do
          streams[i].read
        end
      end
    end
    
    n_msg.times do |i|
      streams[i % n_cli] <<
        Message[client: "1", local: i, global: nil, delta: nil,
          tags: nil, blob: nil]
    end
    
    threads.each {|th| th.join}
  end
end

if __FILE__ == $0
  bme = BenchmarkEnv.new("msg-rate", tasks: [
    WarmupTask.new("warmup"),
    MessageRateBenchmarkTask.new("msg rate", n_msg: 100, n_cli: 2),
    MessageRateBenchmarkTask.new("msg rate", n_msg: 1000, n_cli: 2),
    MessageRateBenchmarkTask.new("msg rate", n_msg: 1000, n_cli: 10)
  ])
  
  bme.run
end
