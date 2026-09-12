lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

# A deliberately small generic collection exposes specialization and value
# layout without substituting a native container for Crystal's implementation.
struct PairBuffer(T)
  def initialize(@first : T, @second : T)
  end

  def first : T
    @first
  end

  def second : T
    @second
  end

  def map(transform : T -> U) forall U
    PairBuffer(U).new(transform.call(@first), transform.call(@second))
  end
end

def bootstrap_main
  pair = PairBuffer(Int32).new(2, 3)
  offset = 4
  mapped = pair.map(->(value : Int32) { value &+ offset })
  Probe.emit(pair.first)
  Probe.emit(mapped.first)
  Probe.emit(mapped.second)
  flags = pair.map(->(value : Int32) { value > 2 })
  Probe.emit(flags.first ? 1 : 0)
  Probe.emit(flags.second ? 1 : 0)
end

bootstrap_main
