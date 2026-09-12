lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

abstract class Term
  def initialize(@offset : Int32)
  end
end

class LiteralTerm < Term
  def value
    @offset &+ 1
  end
end

class OtherTerm < Term
  def value
    @offset &+ 2
  end
end

def choose_term(flag : Bool)
  flag ? LiteralTerm.new(10) : OtherTerm.new(20)
end

def bootstrap_main
  Probe.emit(choose_term(true).value)
  Probe.emit(choose_term(false).value)
end

bootstrap_main
