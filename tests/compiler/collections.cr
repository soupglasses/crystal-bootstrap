# Compiler scope sets rely on independent copies of hash backing storage.
require "set"
set = Set(String).new
100.times do |i|
  set << "key#{i}"
  raise "missing" unless set.includes?("key#{i}")
end
copy = set.dup
100.times do |i|
  raise "missing copy" unless copy.includes?("key#{i}")
  set.delete("key#{i}")
end
puts copy.size
puts set.size

name = "outside"
pairs = {"first" => 1, "second" => 2}
count = pairs.count { |(name, _)| !name.empty? }
raise "wrong count" unless count == 2
puts name

# Method overload lists mix prepending with appending records containing pointers.
record Entry, key : Int32, size : Int32, seen : Bool, label : String
entries = [] of Entry
100.times do |i|
  entries.unshift(Entry.new(-i, i + 1, true, (-i).to_s))
  entries << Entry.new(i, i + 1, true, i.to_s)
end
entries.each_with_index do |entry, index|
  expected = index < 100 ? index - 99 : index - 100
  raise "corrupt entry" unless entry.key == expected && entry.size == expected.abs + 1 && entry.seen && entry.label == expected.to_s
end
puts entries.size
