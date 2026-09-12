# Compiler entry points without the CLI's tool registration and documentation
# server. Keep upstream implementations of parsing, semantics, macros and LLVM.
# CompilerError accepts the CLI's exit enum even when the CLI is absent.
# Values follow src/compiler/crystal/command.cr; all error categories exit 1.
class Crystal::Command
  enum Exit
    OK = 0
    FAILURE = 1
    USAGE_ERROR = 1
    CODE_ERROR = 1
    SOFTWARE_ERROR = 1
  end
end

require "compiler/crystal/annotatable"
require "compiler/crystal/program"
require "compiler/crystal/compiler"
require "compiler/crystal/config"
require "compiler/crystal/crystal_path"
require "compiler/crystal/error"
require "compiler/crystal/exception"
require "compiler/crystal/formatter"
require "compiler/crystal/loader"
require "compiler/crystal/macros"
require "compiler/crystal/progress_tracker"
require "compiler/crystal/semantic"
require "compiler/crystal/syntax"
require "compiler/crystal/types"
require "compiler/crystal/util"
require "compiler/crystal/warnings"
require "compiler/crystal/tools/dependencies"
require "compiler/crystal/semantic/*"
require "compiler/crystal/macros/*"
require "compiler/crystal/codegen/*"
