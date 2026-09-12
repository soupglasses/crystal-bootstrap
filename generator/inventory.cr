require "json"

module Seed
  # Follow resolved definitions once, including constants and foreign callbacks.
  # A work queue avoids recursing through the compiler's recursive call graph.
  class Inventory < Crystal::Visitor
    @seen = Set(UInt64).new
    @constants = Set(UInt64).new
    @pending = [] of Crystal::Def
    @nodes = Hash(String, Int32).new(0)
    @primitives = Hash(String, Int32).new(0)
    @types = Hash(String, Set(String)).new { |hash, key| hash[key] = Set(String).new }
    @dynamic_calls = Hash(String, Int32).new(0)
    @sources = Hash(String, Int32).new(0)

    def enqueue(definition : Crystal::Def)
      return unless @seen.add?(definition.object_id)
      @pending << definition
    end

    def record(node : Crystal::ASTNode)
      @nodes[node.class.to_s] += 1
      if type = node.type?
        @types[type.class.to_s] << type.to_s
      end
      true
    end

    def visit(node : Crystal::ASTNode)
      record(node)
      true
    end

    def visit(node : Crystal::Def)
      false
    end

    def visit(node : Crystal::Call)
      record(node)
      if expanded = node.expanded
        expanded.accept(self)
        return false
      end
      if targets = node.target_defs
        @dynamic_calls[node.name] += 1 if targets.size > 1
        targets.each { |definition| enqueue(definition) }
      end
      true
    end

    def visit(node : Crystal::ProcLiteral)
      record(node)
      enqueue(node.def)
      false
    end

    def visit(node : Crystal::Path)
      record(node)
      if constant = node.target_const
        if @constants.add?(constant.object_id)
          constant.value.accept(self)
        end
      end
      false
    end

    def visit(node : Crystal::Primitive)
      record(node)
      @primitives[node.name] += 1
      true
    end

    def self.report(node : Crystal::ASTNode, program : Crystal::Program) : String
      new.report(node, program)
    end

    def report(node : Crystal::ASTNode, program : Crystal::Program) : String
      node.accept(self)
      program.const_initializers.each do |constant|
        constant.value.accept(self) if @constants.add?(constant.object_id)
      end
      program.class_var_initializers.each { |initializer| initializer.node.accept(self) }
      index = 0
      while index < @pending.size
        definition = @pending[index]
        index += 1
        @sources[File.basename(definition.location.try(&.original_filename).to_s)] += 1
        definition.body.accept(self)
        definition.args.each &.accept(self)
      end
      JSON.build(indent: 2) do |json|
        json.object do
          json.field "scope", "resolved semantic graph; not proof of emitter or initialization coverage"
          json.field "definitions", @seen.size
          json.field "constants", @constants.size
          json.field "class_variable_initializers", program.class_var_initializers.size
          json.field "nodes", @nodes.to_a.sort.to_h
          json.field "primitives", @primitives.to_a.sort.to_h
          json.field "dynamic_calls", @dynamic_calls.to_a.sort.to_h
          json.field "sources", @sources.to_a.sort.to_h
          json.field "types", @types.to_a.sort_by(&.[0]).to_h.transform_values(&.to_a.sort)
        end
      end
    end
  end
end
