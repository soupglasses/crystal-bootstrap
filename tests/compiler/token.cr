require "compiler/crystal/syntax"

lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def bootstrap_main
  token = Crystal::Token.new
  token.type = Crystal::Token::Kind::NUMBER
  token.value = "123"
  Probe.emit(token.type == Crystal::Token::Kind::NUMBER ? 1 : 0)
  Probe.emit(token.value.as(String) == "123" ? 1 : 0)
end

bootstrap_main
