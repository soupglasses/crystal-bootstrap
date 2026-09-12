require "compiler/crystal/syntax"

lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def bootstrap_main
  source = "def answer(x : Int32)\n  x + 42\nend\nanswer(1)\n"
  nodes = Crystal::Parser.new(source).parse.as(Crystal::Expressions).expressions
  definition = nodes[0].as(Crystal::Def)
  Probe.emit(nodes.size)
  Probe.emit(definition.args.size)
  Probe.emit(definition.name == "answer" ? 1 : 0)
  Probe.emit(definition.body.as(Crystal::Call).name == "+" ? 1 : 0)
end

bootstrap_main
