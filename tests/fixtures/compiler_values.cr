lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

class CustomError < Exception
  def initialize(message : String)
    Probe.emit(17)
    super(message)
  end
end

def capture(&block : Int32 -> Int32)
  block
end

def bootstrap_main
  values = Array(Int32).new(2, 1)
  Probe.emit(values.size)
  Probe.emit(values[1])
  Probe.emit(capture { |value| value &+ 1 }.call(2))
  wide = 1_i128 << 100
  Probe.emit(((wide + 42) - wide).to_i32)
  begin
    raise CustomError.new("custom")
  rescue error : CustomError
    Probe.emit(error.message == "custom" ? 1 : 0)
  end
  Probe.emit((-42_i128).to_s == "-42" ? 1 : 0)
  Probe.emit("??)".to_unsafe[0] == 63 ? 1 : 0)
end

bootstrap_main
