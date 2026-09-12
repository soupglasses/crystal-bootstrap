# The bootstrap executable builds one source file using the upstream compiler.
# It intentionally does not dispatch Crystal's developer tools or CLI commands.
require "./compiler"

compiler = Crystal::Compiler.new
compiler.flags = %w(without_interpreter without_mt without_libxml2 without_openssl without_zlib strict_multi_assign preview_overload_order)
compiler.n_threads = 1
compiler.debug = Crystal::Debug::None
compiler.color = false
compiler.cleanup = false
filename = ARGV[0]
output = ARGV[1]
compiler.compile(Crystal::Compiler::Source.new(filename, File.read(filename)), output)
