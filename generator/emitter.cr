require "file_utils"

module Seed
  class Unsupported < Exception
  end

  class ControlFlow < Crystal::Visitor
    getter? cleanup = false
    getter? returns = false

    def visit(node : Crystal::ASTNode)
      true
    end

    def visit(node : Crystal::ProcLiteral)
      false
    end

    def visit(node : Crystal::ExceptionHandler)
      @cleanup ||= !node.ensure.nil?
      true
    end

    def visit(node : Crystal::Return)
      @returns = true
      true
    end

    def self.needs_return_signal?(node : Crystal::ASTNode) : Bool
      visitor = new
      node.accept(visitor)
      visitor.returns?
    end
  end

  # Only the pinned upstream frontend resolves types, overloads, and generics.
  # The emitter walks resolved calls and refuses anything outside the probe ABI.
  class Emitter
    getter filename : String
    getter program_entry : String?
    @native_main : String?
    @definitions = {} of String => String
    @declarations = {} of String => String
    @record_types = {} of String => Crystal::Type
    @record_kinds = {} of String => String
    @records = {} of String => String
    @externals = {} of String => String
    @runtime_types = Set(String).new
    @symbols = Set(String).new
    @builder_base : String?
    @constant_names = {} of Crystal::Const => String
    @class_vars = {} of String => String
    @enum_conversions = {} of String => Crystal::EnumType
    @instance_initializers = {} of String => Array(Tuple(String, String, Crystal::Type))
    @function_names = {} of Tuple(UInt64, String?) => String
    @function_defs = {} of String => Crystal::Def

    @pending = [] of Tuple(String, FunctionEmitter)
    @unsupported = {} of String => String

    def initialize(@filename, @bootstrap = false)
    end

    def fail(node : Crystal::ASTNode, reason : String) : NoReturn
      loc = node.location
      where = loc ? "#{File.basename(loc.filename.to_s)}:#{loc.line_number}:#{loc.column_number}" : "generated node"
      raise Unsupported.new("#{where}: #{reason}")
    end

    def literal(value : String) : String
      String.build do |io|
        io << '"'
        value.each_byte do |byte|
          if byte == 63
            # C++11 processes trigraphs before parsing string literals.
            io << "\\?"
          elsif byte >= 32 && byte < 127 && byte != 34 && byte != 92
            io.write_byte(byte)
          else
            io << '\\' << byte.to_s(8).rjust(3, '0')
          end
        end
        io << '"'
      end
    end

    def identifier(name : String) : String
      # The leading letter and fixed escapes avoid C++ reserved identifiers,
      # including double underscores, without losing source-name identity.
      String.build do |io|
        io << 'n'
        name.each_byte do |char|
          if char >= 65 && char <= 90 || char >= 97 && char <= 122 || char >= 48 && char <= 57
            io.write_byte(char)
          elsif char == 95
            io << "_u"
          else
            io << "_x" << char.to_s(16).rjust(2, '0')
          end
        end
      end
    end

    def number(value : String, type : Crystal::Type) : String
      if {"Int128", "UInt128"}.includes?(type.to_s)
        bits = value.starts_with?('-') ? value.to_i128.unsafe_as(UInt128) : value.to_u128
        high, low = bits >> 64, bits & UInt64::MAX
        return "seed::integer_from_bits<#{type_name(type)}>((seed::UInt128(#{high}ULL) << 64) | seed::UInt128(#{low}ULL))"
      end
      if type.to_s == "Int64"
        return "std::numeric_limits<std::int64_t>::min()" if value == "-9223372036854775808"
        value += "LL"
      elsif type.to_s == "UInt64"
        value += "ULL"
      end
      "#{type_name(type)}(#{value})"
    end

    def type_name(type : Crystal::Type) : String
      @runtime_types << type.to_s
      case type
      when Crystal::MetaclassType, Crystal::GenericClassInstanceMetaclassType, Crystal::VirtualMetaclassType, Crystal::GenericModuleInstanceMetaclassType
        "seed::Type"
      when Crystal::TypeDefType
        type_name(type.remove_typedef)
      when Crystal::AliasType
        type_name(type.remove_alias)
      when Crystal::ReferenceStorageType
        type_name(type.reference_type).rchop(" *")
      when Crystal::ProcInstanceType
        "seed::Proc<#{type_name(type.return_type)}(#{type.arg_types.map { |arg| type_name(arg) }.join(", ")})>"
      when Crystal::NilableType
        type_name(type.not_nil_type)
      when Crystal::UnionType
        "seed::Value"
      when Crystal::VirtualType
        type_name(type.base_type)
      when Crystal::EnumType
        type_name(type.base_type)
      when Crystal::NonGenericModuleType, Crystal::GenericModuleInstanceType
        "seed::Value"
      when Crystal::TupleInstanceType
        "std::tuple<#{type.tuple_types.map { |item| type_name(item) }.join(", ")}>"
      when Crystal::NamedTupleInstanceType
        "std::tuple<#{type.entries.map { |entry| type_name(entry.type) }.join(", ")}>"
      when Crystal::StaticArrayInstanceType
        "std::array<#{type_name(type.element_type)}, #{type.size}>"
      else
        if type.is_a?(Crystal::GenericClassInstanceType) && type.generic_type.name == "Pointer"
          return "#{type_name(type.type_vars.values.first.type)} *"
        end
        return "seed::CharReader" if type.to_s == "Char::Reader"
        if type.to_s == "String::Builder"
          @builder_base = type_name(type.superclass.not_nil!).rchop(" *")
          return "seed::StringBuilder *"
        end
        return "seed::Exception *" if exception_type?(type)
        if element = array_element(type)
          return "seed::Array<#{type_name(element)}> *"
        end
        case type.to_s
        when "Int8"                then "std::int8_t"
        when "UInt8"               then "std::uint8_t"
        when "Int16"               then "std::int16_t"
        when "UInt16"              then "std::uint16_t"
        when "Int32"               then "std::int32_t"
        when "UInt32", "Char"      then "std::uint32_t"
        when "Int64"               then "std::int64_t"
        when "UInt64", "Symbol"    then "std::uint64_t"
        when "Int128" then "seed::Int128"
        when "UInt128" then "seed::UInt128"
        when "Float32"             then "float"
        when "Float64"             then "double"
        when "Bool"                then "seed::Bool"
        when "Nil", "NoReturn"     then "seed::Nil"
        when "Void"                then "void"
        when "Class" then "seed::Type"
        when "Object", "Reference" then "seed::Object *"
        when "String"              then "seed::String *"
        else
          unless type.is_a?(Crystal::ClassType | Crystal::GenericClassInstanceType)
            raise Unsupported.new("type #{type}: unsupported runtime representation")
          end
          name = "seed_type_#{identifier(type.to_s)}"
          unless @records.has_key?(name)
            @records[name] = ""
            @record_types[name] = type
            @record_kinds[name] = type.extern_union? ? "union" : "struct"
            base = ""
            inherited = Set(String).new
            unless type.struct?
              parent = type.superclass
              if parent && !{"Object", "Reference"}.includes?(parent.to_s)
                base = " : public #{type_name(parent).rchop(" *")}"
                inherited = parent.all_instance_vars.keys.to_set
              else
                base = " : public seed::Object"
              end
            end
            fields = type.all_instance_vars.compact_map do |field, variable|
              next if inherited.includes?(field)
              native = type.extern? ? foreign_type(variable.type) : type_name(variable.type)
              "    #{native} field_#{identifier(field.lchop('@'))}#{type.extern_union? ? "" : "{}"};"
            end
            fields << "    const char *seed_type_name() const override { return #{type.to_s.to_json}; }" unless type.struct?
            @records.delete(name)
            @records[name] = "#{@record_kinds[name]} #{type.packed? ? "__attribute__((packed)) " : ""}#{name}#{base} {\n#{fields.join('\n')}\n};\n"
          end
          type.struct? ? name : "#{name} *"
        end
      end
    end

    def coerce(value : String, from : Crystal::Type, to : Crystal::Type) : String
      if from.is_a?(Crystal::SymbolType) && to.is_a?(Crystal::EnumType)
        unless @enum_conversions.has_key?(to.to_s)
          @enum_conversions[to.to_s] = to
          to.types.each_value { |member| constant(member.as(Crystal::Const)) }
        end
        return "seed_enum_#{identifier(to.to_s)}(#{value})"
      end
      source, target = type_name(from), type_name(to)
      return "seed::unreachable<#{target}>(#{value})" if from.no_return? && !to.no_return?
      return value if source == target
      if from.is_a?(Crystal::TupleInstanceType) && to.is_a?(Crystal::TupleInstanceType)
        entries = from.tuple_types.map_with_index { |item, index| coerce("std::get<#{index}>(tuple_value)", item, to.tuple_types[index]) }
        return "([&]() { auto tuple_value = #{value}; return #{target}{#{entries.join(", ")}}; }())"
      end
      return "(static_cast<void>(#{value}), seed::Nil{})" if to.nil_type? || to.no_return?
      if target == "seed::Value"
        tag = from.is_a?(Crystal::NilableType) ? from.not_nil_type.to_s : from.to_s
        return "seed::box(#{value}, #{tag.to_json})"
      elsif source == "seed::Value"
        return "seed::unbox<#{target}>(#{value})"
      elsif (from.is_a?(Crystal::VirtualType) || to.is_a?(Crystal::VirtualType)) && !from.pointer? && !to.pointer? && source.ends_with?("*") && target.ends_with?("*")
        return "dynamic_cast<#{target}>(#{value})"
      elsif source.ends_with?("*") && target.ends_with?("*")
        return "reinterpret_cast<#{target}>(#{value})"
      elsif from.nil_type? && target.ends_with?("*")
        # A nil-returning overload can still mutate state. Its call must run
        # when dispatch widens the result to a nullable reference.
        return "(static_cast<void>(#{value}), static_cast<#{target}>(nullptr))"
      end
      value
    end

    def instance_initializers(type : Crystal::Type) : Array(Tuple(String, String, Crystal::Type))
      @instance_initializers[type.to_s] ||= begin
        result = [] of Tuple(String, String, Crystal::Type)
        owners = [] of Crystal::Type
        owner = type
        while owner.is_a?(Crystal::ClassType | Crystal::GenericClassInstanceType)
          owners.unshift(owner)
          break unless parent = owner.superclass
          owner = parent
        end
        owners.each do |ancestor|
          next unless ancestor.is_a?(Crystal::ClassType | Crystal::GenericClassInstanceType)
          ancestor.instance_vars_initializers.try &.each do |initializer|
            name = "seed_initialize_#{identifier(type.to_s)}_#{result.size}"
            definition = Crystal::Def.new(name, [] of Crystal::Arg, initializer.value)
            definition.owner = type.metaclass
            definition.vars = initializer.meta_vars
            definition.type = initializer.value.type
            emitter = FunctionEmitter.new(self, definition, name)
            @declarations[name] = emitter.signature + ";"
            @pending << {name, emitter}
            result << {initializer.name, name, initializer.value.type}
          end
        end
        result
      end
    end

    def alternatives(type : Crystal::Type) : Array(Crystal::Type)
      case type
      when Crystal::VirtualMetaclassType
        result = [] of Crystal::Type
        type.instance_type.each_concrete_type { |concrete| result << concrete.metaclass }
        result
      when Crystal::UnionType, Crystal::VirtualType
        result = [] of Crystal::Type
        type.each_concrete_type { |concrete| result << concrete }
        result
      when Crystal::NonGenericModuleType
        resolved = type.remove_indirection
        resolved == type ? [type.as(Crystal::Type)] : alternatives(resolved)
      else
        [type]
      end
    end

    def discriminant(value : String, type : Crystal::Type) : String
      tag = type.is_a?(Crystal::NilableType) ? type.not_nil_type.to_s : type.to_s
      type_name(type) == "seed::Value" ? value : "seed::box(#{value}, #{tag.to_json})"
    end

    def type_id(type : Crystal::Type) : String
      @runtime_types << type.to_s
      "seed_type_id_#{identifier(type.to_s)}"
    end

    def constant(constant : Crystal::Const) : String
      if name = @constant_names[constant]?
        return name
      end
      name = "seed_constant_#{identifier(constant.to_s)}"
      @constant_names[constant] = name
      if info = constant.program.const_slices[constant.name]?
        type = type_name(constant.value.type)
        element = constant.value.type.as(Crystal::StaticArrayInstanceType).element_type
        values = info.args.map { |arg| number(arg.as(Crystal::NumberLiteral).value, element) }
        contents = values.each_slice(4).map { |slice| "    " + slice.join(", ") }.join(",\n")
        @declarations[name] = "#{type} &#{name}();"
        @definitions[name] = "#{type} &#{name}() { static #{type} value = {{\n#{contents}\n}}; return value; }\n"
        return name
      end
      definition = Crystal::Def.new(name, [] of Crystal::Arg, constant.value)
      definition.vars = constant.fake_def.try(&.vars)
      definition.owner = constant.namespace.is_a?(Crystal::Program) ? constant.program : constant.namespace.metaclass
      definition.type = constant.value.type
      initializer = "#{name}_initialize"
      emitter = FunctionEmitter.new(self, definition, initializer)
      type = type_name(constant.value.type)
      @declarations[initializer] = emitter.signature + ";"
      @pending << {initializer, emitter}
      @declarations[name] = "#{type} #{name}();"
      @definitions[name] = "#{type} #{name}() {\n    static #{type} value = #{initializer}();\n    return value;\n}\n"
      name
    end

    def class_variable(variable : Crystal::MetaTypeVar) : String
      key = "#{variable.owner}::#{variable.name}"
      if name = @class_vars[key]?
        return name
      end
      name = "seed_class_variable_#{identifier(key)}"
      @class_vars[key] = name
      type = type_name(variable.type)
      initial = "{}"
      if initializer = variable.initializer
        definition = Crystal::Def.new("#{name}_initialize", [] of Crystal::Arg, initializer.node)
        definition.owner = initializer.owner.as(Crystal::Type).metaclass
        definition.vars = initializer.meta_vars
        definition.type = variable.type
        emitter = FunctionEmitter.new(self, definition, "#{name}_initialize")
        @declarations["#{name}_initialize"] = emitter.signature + ";"
        @pending << {"#{name}_initialize", emitter}
        initial = "#{name}_initialize()"
      end
      @declarations[name] = "#{type} &#{name}();"
      @definitions[name] = "#{type} &#{name}() {\n    static #{type} value = #{initial};\n    return value;\n}\n"
      name
    end

    def symbol(name : String) : String
      @symbols << name
      "seed_symbol_#{identifier(name)}"
    end

    def array_element(type : Crystal::Type) : Crystal::Type?
      if type.is_a?(Crystal::GenericClassInstanceType) && type.generic_type.name == "Array"
        type.type_vars.values.first.type
      end
    end

    def exception_type?(type : Crystal::Type) : Bool
      return exception_type?(type.base_type) if type.is_a?(Crystal::VirtualType)
      return true if type.to_s == "Exception"
      if parent = type.superclass
        return exception_type?(parent)
      end
      false
    end

    def exception_ancestry(type : Crystal::Type) : String
      names = [] of String
      loop do
        names << type.to_s
        break if type.to_s == "Exception"
        type = type.superclass.not_nil!
      end
      "|#{names.join('|')}|"
    end

    def block_signature(block : Crystal::Block) : String
      if type = block.fun_literal.try(&.type?).as?(Crystal::ProcInstanceType)
        return "#{type_name(type.return_type)}(#{type.arg_types.map { |arg| type_name(arg) }.join(", ")})"
      end
      return "seed::Nil()" unless block.type?
      "#{type_name(block.type)}(#{block.args.map { |arg| type_name(arg.type? || block.type.program.nil) }.join(", ")})"
    end

    def receiver_type(definition : Crystal::Def) : Crystal::Type
      definition.vars.try(&.[]?("self")).try(&.type?) || definition.owner
    end

    def instance_method?(definition : Crystal::Def) : Bool
      owner = receiver_type(definition)
      !owner.is_a?(Crystal::Program | Crystal::MetaclassType | Crystal::GenericClassInstanceMetaclassType | Crystal::LibType) && (!owner.module? || owner.is_a?(Crystal::EnumType))
    end

    def function_name(definition : Crystal::Def) : String
      owner = definition.owner.is_a?(Crystal::Program) ? "Program" : definition.owner.to_s
      signature = [owner, definition.name] + definition.args.map { |arg| arg.type.to_s }
      "seed_#{signature.map { |part| identifier(part) }.join("_")}"
    end

    def function(definition : Crystal::Def, block : Crystal::Block? = nil, block_key : String? = nil) : String
      # The callable ABI depends on the typed definition and yield signature,
      # not the caller's identity. Reuse it across recursive calls and sites.
      identity = {definition.object_id, block ? block_signature(block) : nil}
      if existing = @function_names[identity]?
        return existing
      end
      name = function_name(definition)
      name += "_block" if block
      base = name
      variant = 0
      while @function_defs.has_key?(name)
        variant += 1
        name = "#{base}_variant_#{variant}"
      end
      @function_names[identity] = name
      fail(definition, "missing yield block") if definition.block_arity && !block

      @definitions[name] = ""
      @function_defs[name] = definition
      emitter = FunctionEmitter.new(self, definition, name, block)
      @declarations[name] = emitter.signature + ";"
      @pending << {name, emitter}
      name
    rescue ex : Unsupported
      context = "\n  while lowering #{definition.owner}##{definition.name}"
      raise Unsupported.new(ex.message.to_s + (ex.message.to_s.count('\n') < 8 ? context : ""))
    end

    def drain
      index = 0
      while index < @pending.size
        name, emitter = @pending[index]
        index += 1
        begin
          @definitions[name] = emitter.generate
        rescue ex : Unsupported
          raise ex unless @bootstrap
          message = ex.message.to_s.gsub(/macro_\d+/, "macro")
          @unsupported[name] = message
          @definitions[name] = "#{emitter.signature} {\n    throw std::runtime_error(#{("Unsupported bootstrap path: " + message).to_json});\n}\n"
        end
      end
    end

    def foreign_type(type : Crystal::Type, parameter : Bool = false) : String
      case type
      when Crystal::ProcInstanceType
        "seed::CFunction<#{type_name(type.return_type)}(#{type.arg_types.map { |arg| foreign_type(arg, true) }.join(", ")})>"
      when Crystal::PointerInstanceType
        "#{foreign_type(type.element_type)} *"
      when Crystal::StaticArrayInstanceType
        parameter ? "#{type_name(type.element_type)} *" : type_name(type)
      else
        type_name(type)
      end
    end

    def external(definition : Crystal::External) : String
      fail(definition, "foreign calling convention #{definition.call_convention}") if definition.call_convention && definition.call_convention != "C"
      original = definition.real_name
      fail(definition, "unmapped LLVM intrinsic #{original}") if original.starts_with?("llvm.")
      fail(definition, "unsupported foreign symbol #{original}") unless original.matches?(/\A[A-Za-z_][A-Za-z_0-9]*\z/)
      name = "seed_foreign_#{identifier(original)}"
      if definition.external_var?
        @externals[name] = "extern \"C\" #{definition.thread_local? ? "thread_local " : ""}#{foreign_type(definition.type)} #{name} asm(#{original.to_json});"
        return name
      end
      arguments = definition.args.map { |arg| foreign_type(arg.type, true) }
      arguments << "..." if definition.varargs?
      result = definition.type.no_return? || definition.type.nil_type? ? "void" : foreign_type(definition.type)
      # An assembler label keeps libc declarations from colliding with the
      # host headers while preserving the native C symbol and ABI.
      @externals[name] = "extern \"C\" #{result} #{name}(#{arguments.join(", ")}) asm(#{original.to_json});"
      name
    end

    def read_foreign(value : String, type : Crystal::Type) : String
      if type.is_a?(Crystal::ProcInstanceType)
        "#{type_name(type)}::from_pointer(reinterpret_cast<void *>(#{value}), nullptr)"
      else
        value
      end
    end

    def validate_declaration(node : Crystal::ASTNode)
      case node
      when Crystal::Def, Crystal::Macro, Crystal::LibDef, Crystal::Nop, Crystal::Require, Crystal::EnumDef
      when Crystal::Assign
        fail(node, "top-level assignment outside bootstrap_main") unless node.target.is_a?(Crystal::Path)
      when Crystal::TypeDeclaration
        fail(node, "type-body initialization is not implemented") if node.value || !node.var.is_a?(Crystal::InstanceVar)
      when Crystal::Expressions
        node.expressions.each { |child| validate_declaration(child) }
      when Crystal::ClassDef, Crystal::ModuleDef
        validate_declaration(node.body)
      else
        fail(node, "executable top-level code outside bootstrap_main")
      end
    end

    def generate(node : Crystal::ASTNode, whole_program : Crystal::Program? = nil, output_dir : String? = nil, functions_per_unit : Int32 = 200) : String
      if program = whole_program
        definition = Crystal::Def.new("program_entry", [] of Crystal::Arg, node)
        definition.owner = program
        definition.vars = program.vars
        definition.type = program.nil
        entry_name = function(definition)
        @program_entry = entry_name
        native_main = program.lookup_defs("main").find { |candidate| candidate.is_a?(Crystal::External) && candidate.fun_def?.try(&.body) }
        fail(node, "program requires the upstream main(argc, argv) entry") unless native_main && native_main.args.size == 2
        @native_main = function(native_main)
      else
        nodes = node.is_a?(Crystal::Expressions) ? node.expressions : [node]
        entry = nodes.last.as?(Crystal::Call)
        unless entry && entry.name == "bootstrap_main" && entry.args.empty? && entry.obj.nil?
          fail(node, "probe must end with bootstrap_main, a zero-argument entry function")
        end
        # Fixture definitions are inputs; unrelated executable top-level code
        # would be silently omitted by an entry-only compilation and is rejected.
        nodes[0...-1].each do |top|
          next unless top.location.try(&.filename) == @filename
          validate_declaration(top)
        end
        targets = entry.target_defs
        fail(entry, "entry must resolve to exactly one function") unless targets && targets.size == 1
        entry_name = function(targets.first)
      end
      drain
      if destination = output_dir
        publish(destination, entry_name, functions_per_unit)
        return ""
      end
      String.build do |io|
        preamble(io)
        @definitions.keys.sort.each { |key| io << @definitions[key] << '\n' }
        main(io, entry_name)
      end
    end

    def layout_dependencies(type : Crystal::Type) : Array(String)
      case type
      when Crystal::TupleInstanceType
        type.tuple_types.flat_map { |item| layout_dependencies(item) }
      when Crystal::NamedTupleInstanceType
        type.entries.flat_map { |entry| layout_dependencies(entry.type) }
      when Crystal::StaticArrayInstanceType
        layout_dependencies(type.element_type)
      else
        name = type_name(type)
        type.struct? && @records.has_key?(name) ? [name] : [] of String
      end
    end

    def ordered_records : Array(String)
      ordered = [] of String
      seen = Set(String).new
      pending = @records.keys.sort
      until pending.empty?
        ready = pending.select do |name|
          type = @record_types[name]
          dependencies = type.all_instance_vars.values.flat_map { |var| layout_dependencies(var.type) }
          if !type.struct? && (parent = type.superclass) && !{"Object", "Reference"}.includes?(parent.to_s)
            parent_name = type_name(parent).rchop(" *")
            dependencies << parent_name if @records.has_key?(parent_name)
          end
          dependencies.all? { |dependency| seen.includes?(dependency) }
        end
        raise Unsupported.new("cyclic native value layouts: #{pending.join(", ")}") if ready.empty?
        ready.each { |name| seen << name; ordered << name }
        pending.reject! { |name| seen.includes?(name) }
      end
      ordered
    end

    def preamble(io : IO)
      io << "// Generated from #{File.basename(@filename)} by crystal-to-cpp. Do not edit.\n"
      io << "// Typed-source snapshot; no LLVM IR is used.\n"
      io << "#include \"seed_runtime.hpp\"\n#include <cstdio>\n\n"
      @records.keys.sort.each { |key| io << "#{@record_kinds[key]} #{key};\n" }
      ordered_records.each { |name| io << @records[name] << '\n' }
      io << "#define SEED_IO_BASE #{@builder_base || "seed::Object"}\n#include \"seed_builder.hpp\"\n#undef SEED_IO_BASE\n"
      @symbols.to_a.sort.each_with_index { |symbol, index| io << "static constexpr std::uint64_t #{self.symbol(symbol)} = #{index + 1};\n" }
      io << "inline seed::String *seed_symbol_text(std::uint64_t id) { switch (id) {\n"
      @symbols.to_a.sort.each_with_index { |symbol, index| io << "case #{index + 1}: return seed::text(#{literal(symbol)}, #{symbol.bytesize});\n" }
      io << "default: throw std::logic_error(\"invalid Symbol\"); } }\n"
      @runtime_types.to_a.sort.each_with_index { |type, index| io << "static constexpr std::int32_t seed_type_id_#{identifier(type)} = #{type == "Nil" ? 0 : index + 1};\n" }
      io << "inline std::int32_t seed_runtime_type_id(const char *name) {\n"
      io << "static const char *names[] = {#{@runtime_types.to_a.sort.map(&.to_json).join(", ")}};\n"
      io << "std::size_t low = 0, high = sizeof(names) / sizeof(*names); while (low < high) { auto mid = low + (high - low) / 2; int order = std::strcmp(name, names[mid]); if (!order) return std::strcmp(name, \"Nil\") ? mid + 1 : 0; if (order < 0) high = mid; else low = mid + 1; } throw std::logic_error(\"unknown runtime type\"); }\n"
      @externals.keys.sort.each { |key| io << @externals[key] << '\n' }
      @declarations.keys.sort.each { |key| io << @declarations[key] << '\n' }
      # Upstream accepts a literal symbol when its underscored name matches an
      # enum member. Symbol IDs and enum values are otherwise unrelated.
      @enum_conversions.keys.sort.each do |name|
        type = @enum_conversions[name]
        members = type.types.to_h { |key, value| {key.underscore, value.as(Crystal::Const)} }
        io << "inline #{type_name(type)} seed_enum_#{identifier(name)}(std::uint64_t value) { switch (value) {\n"
        @symbols.to_a.sort.each do |symbol|
          if member = members[symbol.underscore]?
            io << "case #{self.symbol(symbol)}: return #{@constant_names[member]}();\n"
          end
        end
        io << "default: throw std::logic_error(\"invalid implicit enum conversion\"); } }\n"
      end
    end

    def main(io : IO, entry_name : String)
      io << "int main(int argc, char **argv) {\n    GC_INIT();\n    seed::argc() = argc;\n    seed::argv() = reinterpret_cast<std::uint8_t **>(argv);\n    try {\n"
      if native_main = @native_main
        io << "        return #{native_main}(argc, seed::argv());\n"
      else
        io << "        #{entry_name}();\n        return 0;\n"
      end
      io << "    } catch (const seed::Raised &error) {\n        std::fprintf(stderr, \"%s\\n\", error.what());\n        return 1;\n    } catch (const std::exception &error) {\n        std::fprintf(stderr, \"%s\\n\", error.what());\n        return 2;\n    }\n}\n"
    end

    def digest(filename : String) : String
      output = IO::Memory.new
      status = Process.run("sha256sum", [filename], output: output)
      raise "sha256sum failed" unless status.success?
      output.to_s.split.first
    end

    def publish(destination : String, entry_name : String, functions_per_unit : Int32)
      raise ArgumentError.new("functions per unit must be positive") unless functions_per_unit > 0
      raise ArgumentError.new("output directory already exists: #{destination}") if File.exists?(destination)
      FileUtils.mkdir_p(File.dirname(destination))
      staging = "#{destination}.partial-#{Process.pid}"
      Dir.mkdir(staging)
      begin
        File.open(File.join(staging, "program.hpp"), "w") do |io|
          io << "#ifndef SEED_GENERATED_PROGRAM_HPP\n#define SEED_GENERATED_PROGRAM_HPP\n"
          preamble(io)
          io << "#endif\n"
        end
        units = [] of String
        # A function count alone does not bound units containing large dispatch
        # methods. Limit source bytes as well; an individual function stays whole.
        partitions = [] of Array(String)
        partition = [] of String
        bytes = 0
        @definitions.keys.sort.each do |key|
          size = @definitions[key].bytesize
          if !partition.empty? && (partition.size >= functions_per_unit || bytes + size > 2 * 1024 * 1024)
            partitions << partition
            partition = [] of String
            bytes = 0
          end
          partition << key
          bytes += size
        end
        partitions << partition unless partition.empty?
        partitions.each_with_index do |keys, index|
          name = "unit_#{index.to_s.rjust(5, '0')}.cpp"
          units << name
          File.open(File.join(staging, name), "w") do |io|
            io << "#include \"program.hpp\"\n"
            keys.each { |key| io << @definitions[key] << '\n' }
          end
        end
        units << "main.cpp"
        File.open(File.join(staging, "main.cpp"), "w") do |io|
          io << "#include \"program.hpp\"\n"
          main(io, entry_name)
        end
        Dir.glob(File.join(__DIR__, "../runtime/*.hpp")).sort.each do |runtime|
          FileUtils.cp(runtime, File.join(staging, File.basename(runtime)))
        end
        files = Dir.children(staging).sort.to_h do |name|
          {name, digest(File.join(staging, name))}
        end
        File.write(File.join(staging, "manifest.json"), {
          "format" => 1, "source" => File.basename(@filename),
          "definitions" => @definitions.size, "units" => units,
          "functions_per_unit" => functions_per_unit, "max_unit_bytes" => 2 * 1024 * 1024,
          "largest_function_bytes" => @definitions.values.max_of?(&.bytesize) || 0, "files" => files,
          "unsupported_paths" => @unsupported.to_a.sort.to_h,
        }.to_pretty_json + "\n")
        File.rename(staging, destination)
      ensure
        FileUtils.rm_rf(staging) if Dir.exists?(staging)
      end
    end
  end

  class FunctionEmitter
    @io = IO::Memory.new
    @indent = 1
    @declaration_depth = 0
    @temporary = 0
    @names = {} of String => String
    @local_types = {} of String => Crystal::Type
    @closed = Set(String).new
    @return_tag : String
    @self_type : Crystal::Type
    @return_type : String
    @return_source_type : Crystal::Type
    @return_signal : Bool
    @prepared_call : Tuple(String?, Array(String))?
    @jumps = {} of Crystal::ASTNode => Tuple(String, String)
    @loop_next = {} of Crystal::ASTNode => Tuple(String, String)
    @lambda_depth = 0

    def initialize(@program : Emitter, @definition : Crystal::Def, @name : String, @block : Crystal::Block? = nil)
      @self_type = @program.receiver_type(@definition)
      @return_source_type = @definition.type
      @return_type = @program.type_name(@definition.type)
      @return_tag = "#{@name}_return"
      @return_signal = ControlFlow.needs_return_signal?(@definition.body)
      @definition.vars.try &.each do |key, value|
        @closed << key if key != "self" && value.closured?
      end
    end

    def local(name : String) : String
      @names[name] ||= name.starts_with?("__temp") || name == "_" ? "local_generated_#{@names.size}" : "local_#{@program.identifier(name)}"
    end

    def variable(name : String) : String
      if name == "self"
        return "self" if @program.instance_method?(@definition)
        return "seed::Type{#{@definition.owner.instance_type.to_s.to_json}}"
      end
      @closed.includes?(name) ? "(*#{local(name)})" : local(name)
    end

    def signature : String
      args = @definition.args.map_with_index { |arg, index| "#{@program.type_name(arg.type)} arg_#{index}_#{@program.identifier(arg.name)}" }
      if @program.instance_method?(@definition)
        reference = @self_type.struct? && !@self_type.nil_type? && !@self_type.is_a?(Crystal::IntegerType | Crystal::FloatType | Crystal::CharType | Crystal::BoolType | Crystal::EnumType | Crystal::SymbolType | Crystal::PointerInstanceType | Crystal::ProcInstanceType) ? "&" : ""
        args.unshift "#{@program.type_name(@self_type)} #{reference}self"
      end
      if block = @block
        args << "seed::Proc<#{@program.block_signature(block)}> yield_block"
      end
      @definition.special_vars.try &.to_a.sort.each do |name|
        type = @definition.vars.not_nil![name].type
        args << "#{@program.type_name(type)} *special_#{@program.identifier(name)}"
      end
      "#{@definition.naked? ? "__attribute__((naked, noinline)) " : ""}#{@return_type} #{@name}(#{args.join(", ")})"
    end

    def line(text : String)
      @io << "    " * @indent << text << '\n'
    end

    def fresh : String
      @temporary += 1
      "value_#{@temporary}"
    end

    def store(type : Crystal::Type, expression : String) : String
      name = fresh
      line "#{@program.type_name(type)} #{name} = #{expression};"
      name
    end

    def declare_locals(definition : Crystal::Def, inherited = Set(String).new)
      args = definition.args.to_h { |arg| {arg.name, arg} }
      definition.vars.try &.each do |key, value|
        next if key == "self" || inherited.includes?(key) || !value.type?
        @local_types[key] = value.type
        type = @program.type_name(value.type)
        if definition.same?(@definition) && definition.special_vars.try(&.includes?(key))
          # Upstream forwards $? and $~ as hidden pointers into the caller's
          # lexical frame. Bind the slot instead of creating another local.
          @closed << key
          line "auto #{local(key)} = special_#{@program.identifier(key)};"
          next
        end
        initial = if args.has_key?(key)
                    @program.coerce("arg_#{definition.args.index(args[key]).not_nil!}_#{@program.identifier(key)}", args[key].type, value.type)
                  elsif @definition.block_arg.try(&.name) == key && @block
                    "yield_block"
                  else
                    "{}"
                  end
        if @closed.includes?(key)
          line "auto #{local(key)} = seed::make<#{type}>(#{initial == "{}" ? "" : initial});"
        else
          line "#{type} #{local(key)} = #{initial};"
        end
      end
    end

    def generate : String
      # Anonymous macro virtual filenames contain host object addresses. Point
      # reviewers at the original macro source instead of emitting those names.
      loc = @definition.location.try(&.macro_location) || @definition.location.try(&.expanded_location)
      @io << "// #{File.basename(loc.try(&.filename).to_s)}:#{loc.try(&.line_number)} -- #{@definition.owner}##{@definition.name}\n"
      @io << "struct #{@return_tag} {};\n" if @return_signal
      @io << "#{signature} {\n"
      if @definition.naked?
        emit(@definition.body)
        @io << "}\n"
        return @io.to_s
      end
      declare_locals(@definition)
      if @return_signal
        line "try {"
        @indent += 1
      end
      value = emit(@definition.body)
      if !@definition.body.type? || exits?(@definition.body)
        line "throw std::logic_error(\"unreachable after NoReturn\");"
      else
        line "return #{@program.coerce(return_value(value, @definition.type), @definition.body.type, @definition.type)};"
      end
      if @return_signal
        @indent -= 1
        line "} catch (const seed::Return<#{@return_tag}, #{@return_type}> &returned) {"
        @indent += 1
        line "return returned.value.get();"
        @indent -= 1
        line "}"
      end
      @io << "}\n"
      @io.to_s
    end

    def return_value(value : String, type : Crystal::Type) : String
      type.nil_type? || type.no_return? ? "seed::Nil{}" : value
    end

    def field(name : String, type : Crystal::Type = @self_type, receiver : String = "self") : String
      if type.to_s == "String::Builder"
        return "#{receiver}->buffer->field_nsize" if name == "@bytesize"
      end
      if type.to_s == "String"
        return "#{receiver}->size" if name == "@bytesize"
        return "#{receiver}->length" if name == "@length"
      end
      if type.to_s == "Char::Reader"
        member = {"@string" => "string", "@pos" => "pos", "@current_char" => "current", "@current_char_width" => "width", "@error" => "error"}[name]?
        return "#{receiver}.#{member}" if member
      end
      return "#{receiver}[0]" if type.is_a?(Crystal::StaticArrayInstanceType) && name == "@buffer"
      if @program.exception_type?(type)
        native = @program.type_name(type.all_instance_vars[name].type)
        return "seed::exception_slot<#{native}>(#{receiver}, #{name.lchop('@').to_json})"
      end
      "#{receiver}#{type.struct? ? "." : "->"}field_#{@program.identifier(name.lchop('@'))}"
    end

    def initialize_fields(type : Crystal::Type, receiver : String)
      type = type.base_type if type.is_a?(Crystal::VirtualType)
      @program.instance_initializers(type).each do |name, function, value_type|
        destination = type.all_instance_vars[name].type
        line "#{field(name, type, receiver)} = #{@program.coerce("#{function}()", value_type, destination)};"
      end
    end

    # Cleanup can retain an enclosing result type after an expanded child
    # unconditionally exits. Follow the executed structure as well as its type.
    def exits?(node : Crystal::ASTNode) : Bool
      return true if node.type?.try(&.no_return?) || node.is_a?(Crystal::Return | Crystal::Break | Crystal::Next | Crystal::Unreachable)
      case node
      when Crystal::Expressions
        node.expressions.any? { |child| exits?(child) }
      when Crystal::If
        return exits?(node.cond) || exits?(node.then) if node.truthy?
        return exits?(node.cond) || exits?(node.else) if node.falsey? || node.cond.type?.try(&.nil_type?)
        if condition = node.cond.as?(Crystal::BoolLiteral)
          return exits?(condition.value ? node.then : node.else)
        end
        exits?(node.cond) || (exits?(node.then) && exits?(node.else))
      when Crystal::Call
        if expanded = node.expanded
          return exits?(expanded)
        end
        !node.block && !!node.target_defs.try { |defs| !defs.empty? && defs.all?(&.type.no_return?) }
      when Crystal::Assign
        exits?(node.value)
      when Crystal::Case, Crystal::And, Crystal::Or, Crystal::MultiAssign, Crystal::StringInterpolation, Crystal::MacroExpression, Crystal::MacroIf, Crystal::MacroFor
        !!node.expanded.try { |expanded| exits?(expanded) }
      else
        false
      end
    end

    def emit(node : Crystal::ASTNode) : String
      case node
      when Crystal::VisibilityModifier
        emit(node.exp)
      when Crystal::FileNode
        emit(node.node)
      when Crystal::Expressions
        value = "seed::Nil{}"
        node.expressions.each do |expression|
          value = emit(expression)
          if exits?(expression)
            return "seed::unreachable<#{@program.type_name(node.type? || @return_source_type)}>(seed::Nil{})"
          end
        end
        value
      when Crystal::Def, Crystal::FunDef, Crystal::Macro, Crystal::LibDef, Crystal::CStructOrUnionDef, Crystal::AnnotationDef, Crystal::Alias, Crystal::EnumDef, Crystal::Include, Crystal::Extend, Crystal::Annotation, Crystal::TypeDeclaration
        "seed::Nil{}"
      when Crystal::ClassDef, Crystal::ModuleDef
        @declaration_depth += 1
        value = emit(node.body)
        @declaration_depth -= 1
        value
      when Crystal::Asm
        @program.fail(node, "assembly requires a naked function with basic assembly") unless @definition.naked? && !node.outputs && !node.inputs && !node.intel? && !node.can_throw?
        text = node.text.gsub("$$", "$").gsub("//", "#") + "\nret\n"
        line "__asm__(#{@program.literal(text)});"
        "seed::Nil{}"
      when Crystal::Primitive
        case node.name
        when "argc" then "seed::argc()"
        when "argv" then "seed::argv()"
        else @program.fail(node, "standalone primitive #{node.name}")
        end
      when Crystal::AlignOf, Crystal::InstanceAlignOf
        type = @program.type_name(node.exp.type.instance_type)
        return "std::int32_t(1)" if type == "void"
        type = type.rchop(" *") if node.is_a?(Crystal::InstanceAlignOf)
        "std::int32_t(alignof(#{type}))"
      when Crystal::SizeOf, Crystal::InstanceSizeOf
        type = @program.type_name(node.exp.type.instance_type)
        return "std::int32_t(1)" if type == "void"
        type = type.rchop(" *") if node.is_a?(Crystal::InstanceSizeOf)
        "std::int32_t(sizeof(#{type}))"
      when Crystal::UninitializedVar
        "#{@program.type_name(node.type)}{}"
      when Crystal::Nop, Crystal::NilLiteral
        "seed::Nil{}"
      when Crystal::NumberLiteral
        @program.number(node.value, node.type)
      when Crystal::SymbolLiteral
        @program.symbol(node.value)
      when Crystal::NamedTupleLiteral
        values = node.entries.map { |entry| store(entry.value.type, emit(entry.value)) }
        "#{@program.type_name(node.type)}{#{values.join(", ")}}"
      when Crystal::TupleLiteral
        values = node.elements.map { |element| store(element.type, emit(element)) }
        "#{@program.type_name(node.type)}{#{values.join(", ")}}"
      when Crystal::CharLiteral
        "std::uint32_t(#{node.value.ord})"
      when Crystal::Path
        if replacement = node.syntax_replacement
          emit(replacement)
        elsif constant = node.target_const
          "#{@program.constant(constant)}()"
        else
          "seed::Type{#{node.type.instance_type.to_s.to_json}}"
        end
      when Crystal::Generic, Crystal::TypeOf
        "seed::Type{#{node.type.instance_type.to_s.to_json}}"
      when Crystal::AssignWithRestriction
        emit(node.assign)
      when Crystal::NilableCast
        value = store(node.obj.type, emit(node.obj))
        narrowed = node.to.type.instance_type
        condition = dispatch_condition(value, narrowed, node.obj.type)
        yes = @program.coerce(@program.coerce(value, node.obj.type, narrowed), narrowed, node.type)
        no = @program.coerce("seed::Nil{}", node.type.program.nil, node.type)
        "(#{condition} ? #{yes} : #{no})"
      when Crystal::Cast
        value = store(node.obj.type, emit(node.obj))
        if node.obj.type.is_a?(Crystal::UnionType | Crystal::VirtualType)
          condition = dispatch_condition(value, node.type, node.obj.type)
          line "if (!(#{condition})) throw seed::Raised(seed::exception(\"Type cast failed\", \"|TypeCastError|Exception|\"));"
        end
        @program.coerce(value, node.obj.type, node.type)
      when Crystal::Not
        "!(#{truth(emit(node.exp), node.exp.type)})"
      when Crystal::Case, Crystal::And, Crystal::Or, Crystal::MultiAssign, Crystal::StringInterpolation, Crystal::MacroExpression, Crystal::MacroIf, Crystal::MacroFor
        expanded = node.expanded || @program.fail(node, "missing expansion for #{node.class}")
        emit(expanded)
      when Crystal::Unreachable
        line "throw std::logic_error(\"unreachable\");"
        "seed::Nil{}"
      when Crystal::RespondsTo
        value = store(node.obj.type, emit(node.obj))
        if filtered = node.obj.type.filter_by_responds_to(node.name)
          dispatch_condition(value, filtered, node.obj.type)
        else
          "false"
        end
      when Crystal::IsA
        if replacement = node.syntax_replacement
          emit(replacement)
        else
          value = emit(node.obj)
          type = node.const.type.instance_type
          if @program.type_name(node.obj.type) == "seed::Value" || node.obj.type.is_a?(Crystal::UnionType | Crystal::VirtualType | Crystal::VirtualMetaclassType)
            dispatch_condition(value, type, node.obj.type)
          else
            node.obj.type.implements?(type).to_s
          end
        end
      when Crystal::BoolLiteral
        node.value.to_s
      when Crystal::StringLiteral
        name = fresh
        line "static seed::String #{name}_literal(#{@program.literal(node.value)}, #{node.value.bytesize});"
        "&#{name}_literal"
      when Crystal::Var
        actual = node.name == "self" && @program.instance_method?(@definition) ? @self_type : @local_types[node.name]? || node.type
        @program.coerce(variable(node.name), actual, node.type)
      when Crystal::ClassVar, Crystal::Global
        @program.coerce("#{@program.class_variable(node.var)}()", node.var.type, node.type)
      when Crystal::Out, Crystal::PointerOf
        storage = case exp = node.exp
                  when Crystal::Var then variable(exp.name)
                  when Crystal::InstanceVar then field(exp.name)
                  when Crystal::ClassVar, Crystal::Global then "#{@program.class_variable(exp.var)}()"
                  else emit(exp)
                  end
        "&(#{storage})"
      when Crystal::ReadInstanceVar
        obj = emit(node.obj)
        return "#{obj}[0]" if node.obj.type.is_a?(Crystal::StaticArrayInstanceType) && node.name == "@buffer"
        value = "#{obj}#{node.obj.type.struct? ? "." : "->"}field_#{@program.identifier(node.name.lchop('@'))}"
        node.obj.type.extern? ? @program.read_foreign(value, node.type) : value
      when Crystal::InstanceVar
        actual = @self_type.all_instance_vars[node.name].type
        value = field(node.name)
        value = @program.read_foreign(value, actual) if @self_type.extern?
        @program.coerce(value, actual, node.type)
      when Crystal::Assign
        return "seed::Nil{}" if node.discarded?
        if target = node.target.as?(Crystal::Path)
          constant = target.target_const.not_nil!
          line "#{@program.constant(constant)}();" if constant.used? && !constant.simple? && !constant.compile_time_value
          return "seed::Nil{}"
        end
        # Use typed initializer metadata; declaration templates may be untyped.
        if @declaration_depth > 0 || !node.target.type?
          if target = node.target.as?(Crystal::ClassVar)
            line "#{@program.class_variable(target.var)}();"
            return "seed::Nil{}"
          end
          return "seed::Nil{}" if node.target.is_a?(Crystal::InstanceVar)
        end
        value = emit(node.value)
        if node.target.is_a?(Crystal::Underscore)
          line "static_cast<void>(#{value});"
          return "seed::Nil{}"
        end
        target = case lhs = node.target
                 when Crystal::Var         then variable(lhs.name)
                 when Crystal::InstanceVar then field(lhs.name)
                 when Crystal::ClassVar, Crystal::Global then "#{@program.class_variable(lhs.var)}()"
                 else                           @program.fail(node, "assignment target #{lhs.class}")
                 end
        target_type = if lhs = node.target.as?(Crystal::Var)
                        @local_types[lhs.name]? || lhs.type
                      elsif class_var = node.target.as?(Crystal::ClassVar)
                        class_var.var.type
                      elsif global_var = node.target.as?(Crystal::Global)
                        global_var.var.type
                      else
                        @self_type.all_instance_vars[node.target.as(Crystal::InstanceVar).name].type
                      end
        line "#{target} = #{@program.coerce(value, node.value.type, target_type)};"
        @program.coerce(target, target_type, node.type)
      when Crystal::Call
        emit_call(node)
      when Crystal::If
        emit_if(node)
      when Crystal::While
        output = store(node.type, "{}")
        break_tag, next_tag = "#{fresh}_break", "#{fresh}_next"
        native = @program.type_name(node.type)
        @jumps[node] = {break_tag, native}
        @loop_next[node] = {next_tag, "seed::Nil"}
        line "struct #{break_tag} {};"
        line "struct #{next_tag} {};"
        line "try {"
        @indent += 1
        line "while (true) {"
        @indent += 1
        condition = emit(node.cond)
        line "if (!(#{truth(condition, node.cond.type)})) break;"
        line "try {"
        @indent += 1
        emit(node.body)
        @indent -= 1
        line "} catch (const seed::Return<#{next_tag}, seed::Nil> &) {}"
        @indent -= 1
        line "}"
        @indent -= 1
        line "} catch (const seed::Return<#{break_tag}, #{native}> &stopped) {"
        @indent += 1
        line "#{output} = stopped.value.get();"
        @indent -= 1
        line "}"
        @jumps.delete(node)
        @loop_next.delete(node)
        output
      when Crystal::Break, Crystal::Next
        jump = (node.is_a?(Crystal::Next) ? @loop_next[node.target]? : nil) || @jumps[node.target]? || @program.fail(node, "unknown break/next target")
        value = node.exp ? emit(node.exp.not_nil!) : "seed::Nil{}"
        if jump[1] == "seed::Nil"
          value = "seed::Nil{}"
        else
          value = @program.coerce(value, node.exp.try(&.type) || @definition.type.program.nil, node.target.type)
        end
        line "throw seed::Return<#{jump[0]}, #{jump[1]}>{#{value}};"
        "seed::Nil{}"
      when Crystal::Return
        value = node.exp ? emit(node.exp.not_nil!) : "seed::Nil{}"
        value = @program.coerce(value, node.exp.try(&.type) || @definition.type.program.nil, @return_source_type)
        if @return_signal && @lambda_depth > 0
          line "throw seed::Return<#{@return_tag}, #{@return_type}>{#{value}};"
        else
          line "return #{value};"
        end
        "seed::Nil{}"
      when Crystal::ArrayLiteral
        element = @program.array_element(node.type).not_nil!
        array = store(node.type, "seed::Array<#{@program.type_name(element)}>::create(#{node.elements.size}, #{node.type.to_s.to_json})")
        node.elements.each { |item| line "#{array}->push(#{@program.coerce(emit(item), item.type, element)});" }
        array
      when Crystal::Yield
        @program.fail(node, "scoped yield") if node.scope
        @program.fail(node, "yield without a block") unless @block
        values = [] of Tuple(String, Crystal::Type)
        node.exps.each do |expression|
          exp = expression.is_a?(Crystal::Splat) ? expression.exp : expression
          value = store(exp.type, emit(exp))
          if expression.is_a?(Crystal::Splat)
            exp.type.as(Crystal::TupleInstanceType).tuple_types.each_with_index do |type, index|
              values << {"std::get<#{index}>(#{value})", type}
            end
          else
            values << {value, exp.type}
          end
        end
        block = @block.not_nil!
        if !block.splat_index && values.size == 1 && block.args.size > 1 && (tuple_type = values.first[1].as?(Crystal::TupleInstanceType))
          tuple = values.first[0]
          values = tuple_type.tuple_types.map_with_index { |type, index| {"std::get<#{index}>(#{tuple})", type} }
        end
        position = 0
        args = block.args.map_with_index do |arg, index|
          expected = arg.type? || node.type.program.nil
          if index == block.splat_index && expected.is_a?(Crystal::TupleInstanceType)
            members = expected.tuple_types.map do |type|
              value, actual = values[position]
              position += 1
              @program.coerce(value, actual, type)
            end
            "#{@program.type_name(expected)}{#{members.join(", ")}}"
          elsif item = values[position]?
            position += 1
            @program.coerce(item[0], item[1], expected)
          else
            @program.coerce("seed::Nil{}", node.type.program.nil, expected)
          end
        end
        store(node.type, @program.coerce("yield_block(#{args.join(", ")})", block.type, node.type))
      when Crystal::ProcLiteral
        emit_proc(node)
      when Crystal::ExceptionHandler
        emit_handler(node)
      else
        @program.fail(node, "AST node #{node.class}")
      end
    end

    def truth(value : String, type : Crystal::Type) : String
      native = @program.type_name(type)
      return "seed::truth(#{value})" if native == "seed::Value"
      return value if type.to_s == "Bool"
      return "false" if type.nil_type?
      return "(#{value} != nullptr)" if native.ends_with?("*")
      "true"
    end

    def emit_selected(node : Crystal::If, branch : Crystal::ASTNode) : String
      value = emit(branch)
      if (from = branch.type?) && (to = node.type?)
        @program.coerce(value, from, to)
      else
        value
      end
    end

    def emit_if(node : Crystal::If) : String
      if node.truthy? || node.falsey?
        emit(node.cond)
        return emit_selected(node, node.truthy? ? node.then : node.else)
      end
      if condition = node.cond.as?(Crystal::BoolLiteral)
        return emit_selected(node, condition.value ? node.then : node.else)
      end
      condition = emit(node.cond)
      return emit_selected(node, node.then) if condition == "true"
      return emit_selected(node, node.else) if condition == "false" || node.cond.type.nil_type?
      condition = truth(condition, node.cond.type)
      result_type = node.type? || @definition.type.program.nil
      result = store(result_type, "{}")
      line "if (#{condition}) {"
      @indent += 1
      value = emit(node.then)
      if branch_type = node.then.type?
        line "#{result} = #{@program.coerce(value, branch_type, result_type)};" unless exits?(node.then)
      end
      @indent -= 1
      line "} else {"
      @indent += 1
      value = emit(node.else)
      if branch_type = node.else.type?
        line "#{result} = #{@program.coerce(value, branch_type, result_type)};" unless exits?(node.else)
      end
      @indent -= 1
      line "}"
      result
    end

    def emit_call(node : Crystal::Call) : String
      return emit_call_body(node) unless node.block
      result = store(node.type, "{}")
      tag = "#{fresh}_break"
      type = @program.type_name(node.type)
      line "struct #{tag} {};"
      @jumps[node] = {tag, type}
      line "try {"
      @indent += 1
      value = emit_call_body(node)
      line "#{result} = #{return_value(value, node.type)};" unless node.type.no_return?
      @indent -= 1
      line "} catch (const seed::Return<#{tag}, #{type}> &stopped) {"
      @indent += 1
      line "#{result} = stopped.value.get();"
      @indent -= 1
      line "}"
      @jumps.delete(node)
      result
    end

    def emit_call_body(node : Crystal::Call) : String
      if expanded = node.expanded
        return emit(expanded)
      end
      @program.fail(node, "explicit block forwarding has no resolved block") if node.block_arg && !node.block
      targets = node.target_defs
      if node.name == "not_nil!" && (obj = node.obj) && obj.type.is_a?(Crystal::NilableType) && targets && targets.all? { |definition| {"object.cr", "nil.cr"}.includes?(File.basename(definition.location.try(&.original_filename).to_s)) }
        return store(node.type, "seed::not_nil(#{emit(obj)})")
      end
      @program.fail(node, "call #{node.name} has no resolved target") unless targets && !targets.empty?
      return emit_dispatch(node, targets) if targets.size > 1
      emit_call_target(node, targets.first)
    end

    def result(node : Crystal::Call, target : Crystal::Def, expression : String) : String
      store(node.type, @program.coerce(expression, target.type, node.type))
    end

    def dispatch_condition(value : String, type : Crystal::Type, actual : Crystal::Type = type) : String
      alternatives = @program.alternatives(actual).select(&.implements?(type)).map do |concrete|
        "seed::is(#{@program.discriminant(value, actual)}, #{concrete.to_s.to_json})"
      end
      alternatives.empty? ? "false" : "(#{alternatives.join(" || ")})"
    end

    def emit_dispatch(node : Crystal::Call, targets : Array(Crystal::Def)) : String
      receiver_type = node.obj.try(&.type) || @self_type
      receiver = if obj = node.obj
                   store(receiver_type, emit(obj))
                 elsif targets.any? { |target| @program.instance_method?(target) }
                   "self"
                 end
      args = node.args.map { |arg| store(arg.type, emit(arg)) }
      output = store(node.type, "{}")
      targets.each_with_index do |target, index|
        conditions = [] of String
        concrete_receiver = @program.instance_method?(target) ? receiver : nil
        if receiver && receiver_type.is_a?(Crystal::UnionType | Crystal::VirtualType | Crystal::VirtualMetaclassType | Crystal::NonGenericModuleType)
          expected = @program.receiver_type(target)
          conditions << dispatch_condition(receiver, expected, receiver_type)
          concrete_receiver = @program.coerce(receiver, receiver_type, expected) if @program.instance_method?(target)
        end
        concrete_args = args.map_with_index do |arg, argument|
          actual, expected = node.args[argument].type, target.args[argument].type
          conditions << dispatch_condition(arg, expected, actual) if actual.is_a?(Crystal::UnionType | Crystal::VirtualType | Crystal::NonGenericModuleType)
          @program.coerce(arg, actual, expected)
        end
        @program.fail(node, "dynamic dispatch lacks a runtime discriminant") if conditions.empty?
        line "#{index == 0 ? "if" : "else if"} (#{conditions.join(" && ")}) {"
        @indent += 1
        @prepared_call = {concrete_receiver, concrete_args}
        value = emit_call_target(node, target)
        line "#{output} = #{value};" unless target.type.no_return?
        @indent -= 1
        line "}"
      end
      line "else { throw seed::Raised(\"Unmatched runtime dispatch\"); }"
      output
    end

    def emit_call_target(node : Crystal::Call, target : Crystal::Def) : String
      prepared = @prepared_call
      @prepared_call = nil
      # Deliberate runtime substitution for the prototype, identified by its
      # upstream definition rather than any user method merely named 'raise'.
      if target.owner.is_a?(Crystal::Program) && target.name == "raise" && target.args.size == 1 && (target.args.first.type.to_s == "String" || @program.exception_type?(target.args.first.type)) && target.location.try(&.original_filename.to_s.ends_with?("/raise.cr"))
        message = prepared ? prepared[1].first : emit(node.args.first)
        line "throw seed::Raised(#{message});"
        return "seed::Nil{}"
      end
      receiver = if prepared
                   prepared[0]
                 elsif @program.instance_method?(target)
                   node.obj ? emit(node.obj.not_nil!) : "self"
                 else
                   nil
                 end
      if receiver && !prepared
        actual = node.obj.try(&.type) || @self_type
        receiver = @program.coerce(receiver, actual, @program.receiver_type(target))
      end
      # A scalar/proc receiver is evaluated before arguments as well. Keep
      # struct receivers as lvalues so initialize and mutating methods work.
      if receiver && (target.owner.is_a?(Crystal::ProcInstanceType) || target.owner.is_a?(Crystal::IntegerType | Crystal::FloatType | Crystal::CharType | Crystal::BoolType | Crystal::EnumType | Crystal::SymbolType) || target.owner.pointer? || !target.owner.struct?)
        receiver = store(@program.receiver_type(target), receiver)
      elsif receiver
        temporary = fresh
        line "auto &&#{temporary} = #{receiver};"
        receiver = temporary
      end
      # Materialize arguments left-to-right; neither C nor C++11 guarantees
      # source evaluation order for function arguments.
      args = prepared ? prepared[1] : node.args.map_with_index do |arg, index|
        expected = target.args[index]?.try(&.type) || arg.type
        if target.is_a?(Crystal::External) && expected.is_a?(Crystal::StaticArrayInstanceType)
          # C array parameters decay to pointers and may write the source array.
          value = emit(arg)
          temporary = fresh
          line "auto &&#{temporary} = #{value};"
          temporary
        else
          arg.is_a?(Crystal::Out) ? store(expected, emit(arg)) : @program.coerce(store(arg.type, emit(arg)), arg.type, expected)
        end
      end
      unless target.is_a?(Crystal::External)
        node.args.size.upto(target.args.size - 1) do |index|
          arg = target.args[index]
          magic = arg.default_value.as?(Crystal::MagicConstant) || @program.fail(node, "missing default argument #{arg.name}")
          expression = case magic.name
                       when .magic_line? then "std::int32_t(#{Crystal::MagicConstant.expand_line(node.location)})"
                       when .magic_end_line? then "std::int32_t(#{Crystal::MagicConstant.expand_line(node.end_location)})"
                       when .magic_file?, .magic_dir?
                         value = magic.name.magic_file? ? Crystal::MagicConstant.expand_file(node.location) : Crystal::MagicConstant.expand_dir(node.location)
                         "seed::text(#{@program.literal(value)}, #{value.bytesize})"
                       else @program.fail(node, "unknown magic default argument")
                       end
          args << store(arg.type, expression)
        end
      end
      if target.is_a?(Crystal::External)
        if target.real_name == "__crystal_main" && (entry = @program.program_entry)
          return result(node, target, "#{entry}()")
        end
        if target.fun_def?.try(&.body)
          if target.real_name == "_fiber_get_stack_top"
            return result(node, target, "seed::stack_top()")
          end
          name = @program.function(target)
          return result(node, target, "#{name}(#{args.join(", ")})")
        end
        if target.external_var?
          variable = @program.external(target)
          return result(node, target, args.empty? ? variable : "(#{variable} = #{args.first})")
        end
        if match = /\Allvm\.(fshl|fshr)\.i(8|16|32|64)\z/.match(target.real_name)
          return result(node, target, "seed::#{match[1]}(#{args.join(", ")})")
        end
        if target.real_name == "llvm.x86.sse2.pause"
          line "__asm__ __volatile__(\"pause\");"
          return "seed::Nil{}"
        end
        if match = /\Allvm\.(pow|powi|floor|ceil|copysign)\.f(32|64)(?:\.i32)?\z/.match(target.real_name)
          operation = match[1] == "powi" ? "pow" : match[1]
          return result(node, target, "static_cast<#{@program.type_name(target.type)}>(std::#{operation}(#{args.join(", ")}))")
        end
        if match = /\Allvm\.(ctlz|cttz|ctpop)\.i(8|16|32|64)\z/.match(target.real_name)
          operation = {"ctlz" => "leading_zeros", "cttz" => "trailing_zeros", "ctpop" => "population_count"}[match[1]]
          return result(node, target, "seed::#{operation}(#{args.first})")
        end
        if target.real_name.starts_with?("llvm.memcpy.") || target.real_name.starts_with?("llvm.memmove.") || target.real_name.starts_with?("llvm.memset.")
          name = target.real_name.split('.')[1]
          line "std::#{name}(#{args[0]}, #{args[1]}, #{args[2]});"
          return "seed::Nil{}"
        end
        foreign_args = args.map_with_index do |value, index|
          type = target.args[index]?.try(&.type)
          if type.is_a?(Crystal::ProcInstanceType)
            "#{value}.c_function()"
          elsif type.is_a?(Crystal::StaticArrayInstanceType)
            "#{value}.data()"
          elsif type && @program.foreign_type(type, true) != @program.type_name(type)
            value == "nullptr" ? value : "reinterpret_cast<#{@program.foreign_type(type, true)}>(#{value})"
          else
            value
          end
        end
        call = "#{@program.external(target)}(#{foreign_args.join(", ")})"
        if target.type.to_s == "Void" || node.type.nil_type? || target.type.no_return?
          line "#{call};"
          return "seed::Nil{}"
        end
        if target.type.is_a?(Crystal::ProcInstanceType)
          call = "#{@program.type_name(target.type)}::from_pointer(reinterpret_cast<void *>(#{call}), nullptr)"
        end
        return result(node, target, call)
      end
      if primitive = target.body.as?(Crystal::Primitive)
        expression = case primitive.name
                     when "symbol_to_s"
                       "seed_symbol_text(#{receiver})"
                     when "class"
                       self_type = @program.receiver_type(target)
                       if @program.type_name(self_type) == "seed::Value"
                         "seed::Type{#{receiver}.type ? #{receiver}.type : \"Nil\"}"
                       elsif @program.type_name(self_type).ends_with?("*") && !self_type.pointer?
                         "seed::Type{#{receiver} ? #{receiver}->seed_type_name() : \"Nil\"}"
                       else
                         "seed::Type{#{self_type.to_s.to_json}}"
                       end
                     when "object_crystal_type_id"
                       self_type = @program.receiver_type(target)
                       if @program.type_name(self_type).ends_with?("*") && !self_type.pointer?
                         "seed_runtime_type_id(#{receiver} ? #{receiver}->seed_type_name() : \"Nil\")"
                       else
                         @program.type_id(self_type)
                       end
                     when "class_crystal_instance_type_id"
                       @program.type_id(target.owner.instance_type)
                     when "allocate"
                       type = @program.type_name(node.type)
                       allocation = if @program.array_element(node.type)
                         "#{type.rchop(" *")}::create(0, #{node.type.to_s.to_json})"
                       elsif @program.exception_type?(node.type)
                         "seed::new_exception(#{@program.exception_ancestry(node.type).to_json})"
                       else
                         node.type.struct? ? "{}" : "seed::make<#{type.rchop(" *")}>()"
                       end
                       object = store(node.type, allocation)
                       initialize_fields(node.type, object)
                       return object
                     when "pre_initialize"
                       type = @program.type_name(node.type).rchop(" *")
                       object = store(node.type, "new (static_cast<void *>(#{args.first})) #{type}{}")
                       initialize_fields(node.type, object)
                       return object
                     when "tuple_indexer_known_index"
                       index = primitive.as(Crystal::TupleIndexer).index
                       @program.fail(node, "tuple slicing") unless index.is_a?(Int32)
                       "std::get<#{index}>(#{receiver})"
                     when "convert", "unchecked_convert"
                       "static_cast<#{@program.type_name(target.type)}>(#{receiver || args.first})"
                     when "pointer_malloc"
                       element = node.type.as(Crystal::PointerInstanceType).element_type
                       "seed::allocate<#{element.void? ? "std::uint8_t" : @program.type_name(element)}>(#{args.first})"
                     when "load_atomic" then "__atomic_load_n(#{args[0]}, __ATOMIC_SEQ_CST)"
                     when "store_atomic"
                       line "__atomic_store_n(#{args[0]}, #{args[1]}, __ATOMIC_SEQ_CST);"
                       "seed::Nil{}"
                     when "atomicrmw"
                       operation = node.args.first.as?(Crystal::SymbolLiteral).try(&.value)
                       builtin = {"xchg" => "exchange", "add" => "fetch_add", "sub" => "fetch_sub", "and" => "fetch_and", "or" => "fetch_or", "xor" => "fetch_xor", "nand" => "fetch_nand"}[operation]?
                       @program.fail(node, "atomic operation #{operation}") unless builtin
                       "__atomic_#{builtin}_n(#{args[1]}, #{args[2]}, __ATOMIC_SEQ_CST)".sub("fetch_#{operation}_n", "fetch_#{operation}")
                     when "cmpxchg" then "seed::compare_exchange(#{args[0]}, #{args[1]}, #{args[2]})"
                     when "fence"
                       line "__atomic_thread_fence(__ATOMIC_SEQ_CST);"
                       "seed::Nil{}"
                     when "struct_or_union_set"
                       value = target.args.first.type.is_a?(Crystal::ProcInstanceType) ? "#{args.first}.c_function()" : args.first
                       line "#{receiver}.field_#{@program.identifier(target.name.rchop)} = #{value};"
                       args.first
                     when "pointer_realloc" then "seed::reallocate(#{receiver}, #{args.first})"
                     when "pointer_diff"
                       target.owner.as(Crystal::PointerInstanceType).element_type.to_s == "Void" ? "(reinterpret_cast<std::uint8_t *>(#{receiver}) - reinterpret_cast<std::uint8_t *>(#{args.first}))" : "(#{receiver} - #{args.first})"
                     when "pointer_get"
                       return "seed::Nil{}" if target.owner.as(Crystal::PointerInstanceType).element_type.void?
                       # Pointer#value is an lvalue: setters on a pointed-to
                       # struct must update the original storage.
                       return "(*#{receiver})"
                     when "pointer_set"
                       element = target.owner.as(Crystal::PointerInstanceType).element_type
                       return "seed::Nil{}" if element.void?
                       line "*#{receiver} = #{@program.coerce(args.first, target.args.first.type, element)};"
                       args.first
                     when "pointer_add"
                       if target.owner.as(Crystal::PointerInstanceType).element_type.void?
                         "static_cast<void *>(reinterpret_cast<std::uint8_t *>(#{receiver}) + #{args.first})"
                       else
                         "(#{receiver} + #{args.first})"
                       end
                     when "pointer_new"                  then "reinterpret_cast<#{@program.type_name(node.type)}>(#{args.first})"
                     when "pointer_address", "object_id" then "reinterpret_cast<std::uint64_t>(#{receiver})"
                     when "enum_value", "enum_new"
                       receiver || args.first
                     when "proc_call"
                       proc_type = target.owner.as(Crystal::ProcInstanceType)
                       proc_args = args.map_with_index { |arg, index| @program.coerce(arg, target.args[index].type, proc_type.arg_types[index]) }
                       "#{receiver}(#{proc_args.join(", ")})"
                     when "binary"
                       if {"==", "!="}.includes?(target.name) && target.owner.pointer?
                         return result(node, target, "(#{receiver} #{target.name} #{args.first})")
                       end
                       @program.fail(node, "binary operation types") unless target.owner.is_a?(Crystal::IntegerType | Crystal::FloatType | Crystal::CharType | Crystal::BoolType | Crystal::EnumType | Crystal::SymbolType)
                       native = @program.type_name(target.type)
                       if target.type.is_a?(Crystal::FloatType) && {"+", "-", "*", "/"}.includes?(target.name)
                         "(#{receiver} #{target.name} #{args.first})"
                       else
                         case target.name
                         when "+"  then "seed::add<#{native}>(#{receiver}, #{args.first})"
                         when "&+" then "seed::wrap_add<#{native}>(#{receiver}, #{args.first})"
                         when "-"  then "seed::subtract<#{native}>(#{receiver}, #{args.first})"
                         when "&-" then "seed::wrap_subtract<#{native}>(#{receiver}, #{args.first})"
                         when "*"  then "seed::multiply<#{native}>(#{receiver}, #{args.first})"
                         when "&*" then "seed::wrap_multiply<#{native}>(#{receiver}, #{args.first})"
                         when "unsafe_shl" then "seed::shift_left(#{receiver}, #{args.first})"
                         when "unsafe_shr" then "seed::shift_right(#{receiver}, #{args.first})"
                         when "fdiv" then "(static_cast<#{native}>(#{receiver}) / static_cast<#{native}>(#{args.first}))"
                         when "unsafe_div" then "seed::divide<#{native}>(#{receiver}, #{args.first})"
                         when "unsafe_mod" then "seed::remainder<#{native}>(#{receiver}, #{args.first})"
                         when "==", "!=", "<", "<=", ">", ">=", "&", "|", "^"
                           "(#{receiver} #{target.name} #{args.first})"
                         else @program.fail(node, "binary operator #{target.name}")
                         end
                       end
                     else @program.fail(node, "primitive #{primitive.name}")
                     end
        return result(node, target, expression)
      end
      if adapted = emit_adapter(node, target, receiver, args)
        return adapted
      end
      if node.type.is_a?(Crystal::ProcInstanceType) && target.name == "new" && node.block
        block = node.block.not_nil!
        if literal = block.fun_literal
          return emit(literal)
        end
        return emit_block(block)
      end
      block_value = node.block.try do |block|
        if target.uses_block_arg? && (literal = block.fun_literal)
          emit(literal)
        else
          emit_block(block)
        end
      end
      name = @program.function(target, node.block, "#{@name}_#{block_value}")
      args.unshift receiver if receiver
      args << block_value if block_value
      target.special_vars.try &.to_a.sort.each do |key|
        @program.fail(node, "missing caller slot for #{key}") unless @local_types.has_key?(key)
        args << "&(#{variable(key)})"
      end
      if target.type.no_return?
        line "#{name}(#{args.join(", ")});"
        line "throw std::logic_error(\"unreachable after NoReturn\");"
        return "#{@program.type_name(node.type)}{}"
      end
      result(node, target, "#{name}(#{args.join(", ")})")
    end

    def emit_proc(node : Crystal::ProcLiteral) : String
      definition = node.def
      type = node.type.as(Crystal::ProcInstanceType)
      name = fresh
      old_tag, old_type = @return_tag, @return_type
      old_source_type = @return_source_type
      @return_source_type = type.return_type
      old_return_signal = @return_signal
      @return_signal = ControlFlow.needs_return_signal?(definition.body)
      @return_tag = "#{name}_return"
      @return_type = @program.type_name(type.return_type)
      inherited = @names.keys.to_set
      old_names = @names.dup
      old_local_types = @local_types.dup
      definition.args.each { |arg| inherited.delete(arg.name) }
      old_closed = @closed.dup
      definition.vars.try &.each do |key, value|
        next if key == "self" || inherited.includes?(key)
        value.closured? ? @closed.add(key) : @closed.delete(key)
      end
      old_lambda_depth = @lambda_depth
      @lambda_depth = 0
      args = definition.args.map_with_index { |arg, index| "#{@program.type_name(arg.type)} arg_#{index}_#{@program.identifier(arg.name)}" }
      capture = definition.closure? || definition.self_closured? ? "=" : ""
      line "#{@program.type_name(type)} #{name} = #{@program.type_name(type)}::from([#{capture}](#{args.join(", ")}) mutable -> #{@return_type} {"
      @indent += 1
      line "struct #{@return_tag} {};" if @return_signal
      declare_locals(definition, inherited)
      if @return_signal
        line "try {"
        @indent += 1
      end
      value = emit(definition.body)
      if !definition.body.type? || exits?(definition.body)
        line "throw std::logic_error(\"unreachable after NoReturn\");"
      else
        line "return #{@program.coerce(value, definition.body.type, type.return_type)};"
      end
      if @return_signal
        @indent -= 1
        line "} catch (const seed::Return<#{@return_tag}, #{@return_type}> &returned) {"
        @indent += 1
        line "return returned.value.get();"
        @indent -= 1
        line "}"
      end
      @indent -= 1
      line "});"
      @closed = old_closed
      @names = old_names
      @local_types = old_local_types
      @return_tag, @return_type = old_tag, old_type
      @return_source_type = old_source_type
      @return_signal = old_return_signal
      @lambda_depth = old_lambda_depth
      name
    end

    def emit_adapter(node : Crystal::Call, target : Crystal::Def, receiver : String?, args : Array(String)) : String?
      if receiver && target.owner.extern? && args.empty? && (member = target.body.as?(Crystal::InstanceVar))
        # C aggregate getters denote fields, including nested unions such as
        # epoll_event.data. A value copy would discard a following setter.
        actual = target.owner.all_instance_vars[member.name].type
        value = @program.read_foreign(field(member.name, target.owner, receiver), actual)
        return @program.coerce(value, actual, node.type)
      end
      if node.type.is_a?(Crystal::ProcInstanceType) && target.name == "new" && args.size == 2 && !node.block
        return result(node, target, "#{@program.type_name(node.type)}::from_pointer(#{args.join(", ")})")
      end
      if target.owner.is_a?(Crystal::ProcInstanceType)
        return result(node, target, "#{receiver}.pointer()") if target.name == "pointer"
        return result(node, target, "#{receiver}.closure_data()") if target.name == "closure_data"
      end
      if target.owner.is_a?(Crystal::ReferenceStorageType) && target.name == "to_reference"
        return result(node, target, "&(#{receiver})")
      end
      if node.type.to_s == "Char::Reader" && target.name == "new"
        return result(node, target, "seed::CharReader::create(#{args.join(", ")})")
      end
      if target.owner.to_s == "Char::Reader"
        expression = case target.name
                     when "string"             then "#{receiver}.string"
                     when "current_char"       then "#{receiver}.current"
                     when "current_char_width" then "#{receiver}.width"
                     when "pos"                then "#{receiver}.pos"
                     when "pos="               then "#{receiver}.set_pos(#{args.first})"
                     when "error"              then "#{receiver}.error"
                     when "has_next?"          then "#{receiver}.has_next()"
                     when "next_char"          then "#{receiver}.next()"
                     when "peek_next_char"     then "#{receiver}.peek()"
                     else                           nil
                     end
        return result(node, target, expression) if expression
      end
      if target.owner.metaclass? && node.type.to_s == "String" && target.name == "new"
        if node.block && args.size == 1 && target.args.first.type.is_a?(Crystal::IntegerType)
          buffer = fresh
          line "auto #{buffer} = seed::allocate<std::uint8_t>(#{args.first} + 1);"
          callback = emit_block(node.block.not_nil!)
          dimensions = fresh
          line "auto #{dimensions} = #{callback}(#{buffer});"
          line "if (std::get<0>(#{dimensions}) < 0 || std::get<0>(#{dimensions}) > #{args.first}) throw seed::Raised(\"String capacity exceeded\");"
          return result(node, target, "seed::text(reinterpret_cast<const char *>(#{buffer}), std::get<0>(#{dimensions}))")
        elsif target.args.first?.try(&.type.pointer?)
          size = args.size >= 2 ? args[1] : "std::strlen(reinterpret_cast<const char *>(#{args.first}))"
          return result(node, target, "seed::text(reinterpret_cast<const char *>(#{args.first}), #{size})")
        end
      end
      if target.owner.to_s == "String"
        expression = case target.name
                     when "size"      then "seed::character_count(#{receiver})"
                     when "bytesize"  then "#{receiver}->size"
                     when "empty?"    then "(#{receiver}->size == 0)"
                     when "to_unsafe" then "reinterpret_cast<std::uint8_t *>(const_cast<char *>(#{receiver}->bytes))"
                     when "=="        then target.args.first.type.to_s == "String" ? "seed::equal(#{receiver}, #{args.first})" : nil
                     when "!="        then target.args.first.type.to_s == "String" ? "!seed::equal(#{receiver}, #{args.first})" : nil
                     when "+"         then target.args.first.type.to_s == "String" ? "seed::concat(#{receiver}, #{args.first})" : nil
                     else                  nil
                     end
        return result(node, target, expression) if expression
      end
      if node.type.to_s == "String::Builder" && target.name == "new" && target.args.all? { |arg| arg.type.is_a?(Crystal::IntegerType) }
        return result(node, target, "seed::StringBuilder::create()")
      end
      if target.owner.to_s == "String::Builder"
        if target.name == "write_byte" && args.size == 1
          line "#{receiver}->buffer->push(#{args.first});"
          return "seed::Nil{}"
        end
        if {"write", "write_string"}.includes?(target.name) && target.args.first.type.to_s == "Slice(UInt8)"
          value = args.first
          line "#{receiver}->append(seed::text(reinterpret_cast<const char *>(#{value}.field_npointer), #{value}.field_nsize));"
          return "seed::Nil{}"
        end
        expression = case target.name
                     when "to_s" then "#{receiver}->to_s()"
                     when "buffer" then "#{receiver}->buffer->data()"
                     when "bytesize" then "#{receiver}->buffer->size()"
                     when "empty?" then "#{receiver}->buffer->empty()"
                     when "<<"
                       return nil unless {"Char", "String"}.includes?(node.args.first.type.to_s)
                       method = node.args.first.type.to_s == "Char" ? "append_char" : "append"
                       "#{receiver}->#{method}(#{args.first})"
                     else nil
                     end
        return result(node, target, expression) if expression
      end
      if target.owner.is_a?(Crystal::IntegerType) && (target.name == "to_s" || target.name.starts_with?("to_s:")) && target.type.to_s == "String" && target.args.all? { |arg| {"base", "precision", "upcase"}.includes?(arg.name) } && File.basename(target.location.try(&.original_filename).to_s) == "int.cr"
        parameters = target.args.map_with_index { |arg, index| {arg.name, args[index]} }.to_h
        format = [parameters["base"]? || "10", parameters["precision"]? || "1", parameters["upcase"]? || "false"]
        return result(node, target, "seed::integer_text(#{receiver}, #{format.join(", ")})")
      end
      if target.owner.is_a?(Crystal::GenericClassInstanceType) && target.owner.to_s.starts_with?("Pointer(")
        if {"+", "-"}.includes?(target.name) && args.size == 1 && target.args.first.type.is_a?(Crystal::IntegerType)
          if target.owner.as(Crystal::PointerInstanceType).element_type.void?
            return result(node, target, "static_cast<void *>(reinterpret_cast<std::uint8_t *>(#{receiver}) #{target.name} #{args.first})")
          end
          return result(node, target, "(#{receiver} #{target.name} #{args.first})")
        end
        if target.name == "[]=" && args.size == 2 && target.args.first.type.is_a?(Crystal::IntegerType)
          element = target.owner.as(Crystal::PointerInstanceType).element_type
          return "seed::Nil{}" if element.void?
          line "#{receiver}[#{args[0]}] = #{@program.coerce(args[1], target.args[1].type, element)};"
          return result(node, target, args[1])
        elsif target.name == "[]" && args.size == 1 && target.args.first.type.is_a?(Crystal::IntegerType)
          return "seed::Nil{}" if target.owner.as(Crystal::PointerInstanceType).element_type.void?
          return result(node, target, "#{receiver}[#{args[0]}]")
        end

      end
      if @program.exception_type?(target.owner) && target.name == "message" && args.empty? && target.body.as?(Crystal::InstanceVar).try(&.name) == "@message"
        return result(node, target, "seed::message(#{receiver})")
      end
      element = @program.array_element(target.owner) || (target.owner.metaclass? ? @program.array_element(node.type) : nil)
      return nil unless element
      size_getter = target.name == "size" && target.body.as?(Crystal::InstanceVar).try(&.name) == "@size"
      return nil unless size_getter || {"array.cr", "enumerable.cr", "indexable.cr", "mutable.cr", "macros.cr"}.includes?(File.basename(target.location.try(&.original_filename).to_s))
      native = "seed::Array<#{@program.type_name(element)}>"
      if {"new", "unsafe_build"}.includes?(target.name) && target.owner.metaclass?
        return nil unless args.size <= 1 && !node.block
        return result(node, target, "#{native}::#{target.name == "new" ? "create" : "unsafe_build"}(#{args.first? || "0"}, #{node.type.to_s.to_json})")
      end
      return nil unless @program.array_element(target.owner)
      if block = node.block
        return nil unless {"map", "each"}.includes?(target.name) && args.empty? && block.args.size == 1
        callback = emit_block(block)
        result = if target.name == "map"
                   result(node, target, "seed::Array<#{@program.type_name(@program.array_element(node.type).not_nil!)}>::create(#{receiver}->size(), #{node.type.to_s.to_json})")
                 else
                   receiver.not_nil!
                 end
        index = fresh
        line "for (std::int32_t #{index} = 0; #{index} < #{receiver}->size(); ++#{index}) {"
        @indent += 1
        argument = @program.coerce("#{receiver}->at(#{index})", element, block.args.first.type? || node.type.program.nil)
        expression = "#{callback}(#{argument})"
        if target.name == "map"
          expression = @program.coerce(expression, block.type, @program.array_element(node.type).not_nil!)
          line "#{result}->push(#{expression});"
        else
          line "#{expression};"
        end
        @indent -= 1
        line "}"
        return result
      end
      if target.name == "sum" && args.empty? && element.to_s == "Int32" && node.type.to_s == "Int32"
        return result(node, target, "seed::sum_i32(#{receiver})")
      end
      if {"<<", "push"}.includes?(target.name) && args.size == 1
        value = @program.coerce(args.first, target.args.first.type, element)
        return result(node, target, "#{receiver}->push(#{value})")
      end
      if target.name == "[]=" && args.size == 2 && target.args.first.type.is_a?(Crystal::IntegerType)
        value = @program.coerce(args[1], target.args[1].type, element)
        line "#{receiver}->set(#{args[0]}, #{value});"
        return result(node, target, args[1])
      end
      method = case target.name
               when "[]"         then args.size == 1 && target.args.first.type.is_a?(Crystal::IntegerType) ? "at" : return nil
               when "to_unsafe"  then "data"
               when "size"       then "size"
               when "empty?"     then "empty"
               when "pop"        then "pop"
               when "clear"      then "clear"
               else                   return nil
               end
      result(node, target, "#{receiver}->#{method}(#{args.join(", ")})")
    end

    def emit_block(block : Crystal::Block) : String
      return "seed::Proc<seed::Nil()>{}" unless block.type?
      name = fresh
      old_names, old_closed = @names.dup, @closed.dup
      old_local_types = @local_types.dup
      args = block.args.map_with_index { |arg, index| "#{@program.type_name(arg.type? || block.type.program.nil)} block_#{index}_#{@program.identifier(arg.name)}" }
      line "auto #{name}_body = [&](#{args.join(", ")}) mutable -> #{@program.type_name(block.type)} {"
      @indent += 1
      @lambda_depth += 1
      block.args.each_with_index do |arg, index|
        cell = "block_cell_#{index}_#{@program.identifier(arg.name)}"
        argument_type = arg.type? || block.type.program.nil
        storage_type = block.vars.try(&.[]?(arg.name)).try(&.type?) || argument_type
        initial = @program.coerce("block_#{index}_#{@program.identifier(arg.name)}", argument_type, storage_type)
        if block.vars.try(&.[]?(arg.name)).try(&.closured?)
          line "auto #{cell} = seed::make<#{@program.type_name(storage_type)}>(#{initial});"
          @closed << arg.name
        else
          line "#{@program.type_name(storage_type)} #{cell} = #{initial};"
          @closed.delete(arg.name)
        end
        @names[arg.name] = cell
        @local_types[arg.name] = storage_type
      end
      block.vars.try &.each do |key, meta|
        next if key == "self" || !meta.type? || block.args.any? { |arg| arg.name == key }
        next if @names.has_key?(key) && !meta.belongs_to?(block)
        # Destructured block arguments arrive as assignments in the body.
        # Their metadata owns a new slot even when an outer local has the name.
        @names[key] = "#{name}_local_#{@program.identifier(key)}" if @names.has_key?(key)
        type = @program.type_name(meta.type)
        @local_types[key] = meta.type
        if meta.closured?
          @closed << key
          line "auto #{local(key)} = seed::make<#{type}>();"
        else
          @closed.delete(key)
          line "#{type} #{local(key)} = {};"
        end
      end
      tag = "#{fresh}_next"
      type = @program.type_name(block.type)
      @jumps[block] = {tag, type}
      line "struct #{tag} {};"
      line "try {"
      @indent += 1
      value = emit(block.body)
      if !block.body.type? || exits?(block.body)
        line "throw std::logic_error(\"unreachable after NoReturn\");"
      else
        line "return #{@program.coerce(value, block.body.type, block.type)};"
      end
      @indent -= 1
      line "} catch (const seed::Return<#{tag}, #{type}> &continued) {"
      @indent += 1
      line "return continued.value.get();"
      @indent -= 1
      line "}"
      @jumps.delete(block)
      @indent -= 1
      @lambda_depth -= 1
      line "};"
      line "auto #{name} = seed::Proc<#{@program.block_signature(block)}>::borrow(#{name}_body);"
      @names, @closed = old_names, old_closed
      @local_types = old_local_types
      name
    end

    def emit_handler(node : Crystal::ExceptionHandler) : String
      result = store(node.type, "{}")
      cleanup = node.ensure
      if cleanup
        line "seed::ensure([&]() {"
        @indent += 1
        @lambda_depth += 1
      end
      rescues = node.rescues
      succeeded = fresh
      line "bool #{succeeded} = false;" if node.else
      if rescues
        line "try {"
        @indent += 1
      end
      value = emit(node.body)
      line "#{result} = #{@program.coerce(value, node.body.type, node.type)};" unless exits?(node.body) || node.else
      line "#{succeeded} = true;" if node.else
      if rescues
        @indent -= 1
        caught = fresh
        line "} catch (const seed::Raised &#{caught}) {"
        @indent += 1
        rescues.each_with_index do |clause, index|
          condition = clause.types.try &.map { |type| "#{caught}.object.get()->is(#{("|" + type.type.instance_type.to_s + "|").to_json})" }.join(" || ")
          line "#{index == 0 ? "if" : "else if"} (#{condition || "true"}) {"
          @indent += 1
          if name = clause.name
            value = @program.coerce("#{caught}.object.get()", node.type.program.exception, @local_types[name])
            line "#{variable(name)} = #{value};"
          end
          rescue_value = emit(clause.body)
          line "#{result} = #{@program.coerce(rescue_value, clause.body.type, node.type)};" unless exits?(clause.body)
          @indent -= 1
          line "}"
        end
        line "else { throw; }"
        @indent -= 1
        line "}"
      end
      if otherwise = node.else
        line "if (#{succeeded}) {"
        @indent += 1
        value = emit(otherwise)
        line "#{result} = #{@program.coerce(value, otherwise.type, node.type)};" unless exits?(otherwise)
        @indent -= 1
        line "}"
      end
      if cleanup
        @indent -= 1
        line "}, [&]() {"
        @indent += 1
        emit(cleanup)
        @indent -= 1
        line "});"
        @lambda_depth -= 1
      end
      result
    end
  end
end
