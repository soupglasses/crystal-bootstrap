#ifndef CRYSTAL_BOOTSTRAP_SEED_BUILDER_HPP
#define CRYSTAL_BOOTSTRAP_SEED_BUILDER_HPP

// Included after generated IO so builders retain upstream IO inheritance.
namespace seed {
struct StringBuilder : public SEED_IO_BASE {
    Array<std::uint8_t> *buffer;
    StringBuilder() : buffer(Array<std::uint8_t>::create()) {}
    const char *seed_type_name() const override { return "String::Builder"; }
    static StringBuilder *create() { return make<StringBuilder>(); }
    StringBuilder *append(String *value) {
        for (std::int32_t i = 0; i < value->size; ++i) buffer->push(static_cast<std::uint8_t>(value->bytes[i]));
        return this;
    }
    StringBuilder *append_char(std::uint32_t value) {
        std::uint8_t bytes[4];
        const auto size = utf8proc_encode_char(static_cast<utf8proc_int32_t>(value), bytes);
        if (!size) throw Raised("Invalid character");
        for (utf8proc_ssize_t i = 0; i < size; ++i) buffer->push(bytes[i]);
        return this;
    }
    String *to_s() { return text(reinterpret_cast<const char *>(buffer->data()), buffer->size()); }
};

}
#endif
