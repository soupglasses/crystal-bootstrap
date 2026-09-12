# Keep layout queries until native emission. Upstream cleanup normally replaces
# them with LLVM-layout constants, which are wrong for C++ tuples, unions and
# records (for example, Hash entry copies would truncate their backing buffer).
class Crystal::CleanupTransformer
  def transform(node : Crystal::SizeOf)
    node
  end

  def transform(node : Crystal::AlignOf)
    node
  end

  {% for kind in [Crystal::InstanceSizeOf, Crystal::InstanceAlignOf] %}
    def transform(node : {{kind}})
      expanded = node.expanded
      node.expanded = nil
      previous_def
    ensure
      node.expanded = expanded
    end
  {% end %}
end
