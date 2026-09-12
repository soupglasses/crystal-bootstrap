lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def bootstrap_main
  Probe.emit(0_u8.leading_zeros_count)
  Probe.emit(1_u8.leading_zeros_count)
  Probe.emit(0_i64.trailing_zeros_count)
  Probe.emit(256_i64.trailing_zeros_count)
  Probe.emit(-1_i16.popcount)
end

bootstrap_main
