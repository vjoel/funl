require 'funl/message-sequencer'
require 'socket'
require 'tmpdir'

include Funl

class BenchmarkTask
  attr_reader :name, :params

  def initialize name, **params
    @name = name
    @params = params
  end
  
  def inspect
    ps = params.map{|k,v| "#{k}: #{v}" }
    pstr = ps.empty? ? "" : " " + ps.join(', ')
    "<#{name}#{pstr}>"
  end
end

class WarmupTask < BenchmarkTask
  def run make_stream
    make_stream["1"]
  end
end

# All clients run in the same process; mseq server is in a child process.
class BenchmarkEnv
  attr_reader :name, :dir, :path, :log, :stream_type, :tasks

  def initialize name, tasks: [], stream_type: ObjectStream::MSGPACK_TYPE
    @name = name
    @log = Logger.new($stderr)
    log.level = Logger::WARN
    @stream_type = stream_type
    @tasks = tasks
  end

  def run
    @dir = Dir.mktmpdir "funl-benchmark-#{name}-"
    @path = File.join(dir, "sock")
    svr = UNIXServer.new(path)
    @pid = fork do
      log.progname = "#{name}-mseq"
      mseq = MessageSequencer.new svr, log: log,  stream_type: stream_type
      mseq.start
      sleep
    end

    log.progname = "client"
    printf "%6s %6s | %s\n", "client", "server", "task"
    puts "-"*60
    tasks.each do |task|
      run_task task
    end
  ensure
    close
  end
  
  def run_task task
    t0 = Process.times
    task.run method(:make_stream)
    t1 = Process.times
    time = t1.utime + t1.stime - (t0.utime + t0.stime)
    ctime = t1.cutime + t1.cstime - (t0.cutime + t0.cstime)
    printf "%6.3f %6.3f | %p\n", time, ctime, task
  rescue => ex
    log.error "#{task.inspect}: #{ex}"
  end

  def make_stream client_id = nil ## subscriptions?
    conn = UNIXSocket.new(path)
    stream = ObjectStreamWrapper.new(conn, type: stream_type)
    stream.write_to_outbox({"client_id" => client_id})
    stream.write(Message.control(SUBSCRIBE_ALL))
    global_tick = stream.read["tick"]
    stream.expect Message
    ack = stream.read
    stream
  end

  def close
    Process.kill "TERM", @pid if @pid
    FileUtils.remove_entry dir if dir
  end
end

