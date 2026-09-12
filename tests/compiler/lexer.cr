require "compiler/crystal/syntax"

lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def bootstrap_main
  lexer = Crystal::Lexer.new("answer = 42\n")
  token = lexer.next_token
  Probe.emit(token.line_number)
  Probe.emit(token.column_number)
  Probe.emit(token.value == "answer" ? 1 : 0)
  lexer.next_token_skip_space
  Probe.emit(token.type.op_eq? ? 1 : 0)
  lexer.next_token_skip_space
  Probe.emit(token.type.number? && token.value == "42" ? 1 : 0)
  Probe.emit(lexer.next_token.type.newline? ? 1 : 0)
  Probe.emit(lexer.next_token.type.eof? ? 1 : 0)
end

bootstrap_main
