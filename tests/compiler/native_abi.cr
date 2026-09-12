lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

lib NativeSort
  fun qsort(base : Void*, count : LibC::SizeT, size : LibC::SizeT,
            compare : (Void*, Void*) -> Int32) : Void
end

def bootstrap_main
  values = StaticArray[42, -3, 7, 7]
  NativeSort.qsort(values.to_unsafe, values.size, sizeof(Int32), ->(a : Void*, b : Void*) {
    a.as(Int32*).value <=> b.as(Int32*).value
  })
  values.each { |value| Probe.emit(value) }
end

bootstrap_main
