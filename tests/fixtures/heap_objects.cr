lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

class HeapNode
  @next : HeapNode?
  @values : Array(Int32)

  def initialize(value : Int32)
    @values = [value]
    @next = self
  end

  def read
    @values[0]
  end

  def reader
    -> { @next.not_nil!.read }
  end
end

def make_reader(value : Int32)
  HeapNode.new(value).reader
end

def bootstrap_main
  readers = Array(Proc(Int32)).new
  readers << make_reader(17)
  readers << make_reader(29)
  Probe.emit(readers[0].call)
  Probe.emit(readers[1].call)
end

bootstrap_main
