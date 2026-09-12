require "compiler/requires"
require "./frontend"
require "./emitter"
require "./inventory"

begin
  output_dir = nil
  functions_per_unit = 200
  if index = ARGV.index("--output-dir")
    ARGV.delete_at(index)
    raise ArgumentError.new("--output-dir requires a path") unless ARGV[index]?
    output_dir = ARGV.delete_at(index)
  end
  if index = ARGV.index("--functions-per-unit")
    ARGV.delete_at(index)
    raise ArgumentError.new("--functions-per-unit requires a positive integer") unless ARGV[index]?
    functions_per_unit = ARGV.delete_at(index).to_i
    raise ArgumentError.new("--functions-per-unit must be positive") unless functions_per_unit > 0
  end
  bootstrap = !!ARGV.delete("--bootstrap")
  whole_program = !!ARGV.delete("--program")
  inventory = !!ARGV.delete("--inventory")
  flags = ARGV.select(&.starts_with?("-D"))
  flags.each { |flag| ARGV.delete(flag) }
  unless ARGV.size == 1
    STDERR.puts "usage: crystal-to-cpp [--inventory | --program] [--output-dir PATH] [--functions-per-unit N] [-Dflag] INPUT.cr"
    exit 2
  end
  raise ArgumentError.new("--inventory cannot publish source or run program mode") if inventory && (whole_program || output_dir)
  filename = File.expand_path(ARGV[0])
  compiler = Crystal::Compiler.new
  compiler.no_codegen = true
  compiler.flags << "without_mt"
  flags.each { |flag| compiler.flags << flag.lchop("-D") }
  result = compiler.compile(Crystal::Compiler::Source.new(filename, File.read(filename)), "unused")
  # Buffer the complete translation so unsupported code cannot leave a plausible
  # partial snapshot on stdout.
  print inventory ? Seed::Inventory.report(result.node, result.program) : Seed::Emitter.new(filename, bootstrap).generate(result.node, whole_program ? result.program : nil, output_dir, functions_per_unit)
rescue ex : ArgumentError
  STDERR.puts "usage error: #{ex.message}"
  exit 2
rescue ex : Seed::Unsupported
  STDERR.puts "unsupported: #{ex.message}"
  exit 1
rescue ex : Crystal::CodeError
  STDERR.puts ex
  exit 1
end
