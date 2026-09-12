lib Probe
  fun emit = probe_emit(value : Int32) : Void
  fun limit = probe_gc_limit(value : Int32) : Void
  fun check = probe_gc_check(value : Int32) : Void
end

class GraphNode
  @next : GraphNode?
  @values : Array(Int32)

  def initialize(value : Int32)
    @values = Array(Int32).new(32768)
    @values << value
    @next = self
  end

  def read
    @values[0]
  end

  def reader
    -> { @next.not_nil!.read }
  end
end

def new_reader(value : Int32)
  GraphNode.new(value).reader
end

def bootstrap_main
  Probe.limit(32)
  readers = Array(Proc(Int32)).new
  readers << new_reader(0)
  i = 0
  while i < 12000
    readers[0] = new_reader(i)
    i = i &+ 1
  end
  Probe.check(1024)
  Probe.emit(readers[0].call)
end

bootstrap_main
