lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def bootstrap_main
  builder = String::Builder.new
  builder << "A\0" << 'é'
  value = builder.to_s
  Probe.emit(value.bytesize)
  Probe.emit(value.size)
  Probe.emit(value == "A\0é" ? 1 : 0)
  reader = Char::Reader.new(value)
  Probe.emit(reader.current_char.ord)
  Probe.emit(reader.next_char.ord)
  Probe.emit(reader.next_char.ord)
  Probe.emit(reader.pos)
  Probe.emit(reader.current_char_width)
  Probe.emit(reader.next_char.ord)
  Probe.emit(reader.has_next? ? 1 : 0)
end

bootstrap_main
