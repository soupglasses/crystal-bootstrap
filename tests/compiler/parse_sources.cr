# Parse real compiler inputs without retaining their complete ASTs.
require "compiler/crystal/syntax"
ARGV.each do |filename|
  parser = Crystal::Parser.new(File.read(filename))
  parser.filename = filename
  parser.parse
end
puts ARGV.size
