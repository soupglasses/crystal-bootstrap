#ifndef CRYSTAL_BOOTSTRAP_SEED_TEXT_HPP
#define CRYSTAL_BOOTSTRAP_SEED_TEXT_HPP

namespace seed {

struct String : Object {
    const char *bytes;
    std::int32_t size;
    std::int32_t length = 0;
    String(const char *bytes, std::int32_t size) : bytes(bytes), size(size) {}
    const char *seed_type_name() const override { return "String"; }
};

inline String *text(const char *bytes, std::int32_t size) {
    if (size < 0) throw Raised("Negative string size");
    char *copy = static_cast<char *>(GC_MALLOC_ATOMIC(static_cast<std::size_t>(size) + 1));
    if (!copy) throw std::bad_alloc();
    std::memcpy(copy, bytes, size);
    copy[size] = 0;
    return make<String>(String{copy, size});
}

inline Exception *exception(String *message, const char *ancestry = "|Exception|") {
    return make<Exception>(Exception{message->bytes, ancestry, message->size});
}
inline Raised::Raised(String *message) : object(seed::exception(message)) {}
inline const char *Exception::what_bytes() const noexcept {
    if (void *value = find("message")) {
        auto text = *static_cast<String **>(value);
        return text ? text->bytes : "Exception";
    }
    return message ? message : "Exception";
}
inline String *message(Exception *error) {
    if (void *value = error->find("message")) return *static_cast<String **>(value);
    return error->message ? text(error->message, error->message_size) : nullptr;
}
inline bool equal(String *a, String *b) {
    return a->size == b->size && std::memcmp(a->bytes, b->bytes, a->size) == 0;
}
inline String *concat(String *a, String *b) {
    if (a->size > INT32_MAX - b->size) throw Raised("String size overflow");
    std::int32_t size = a->size + b->size;
    char *bytes = static_cast<char *>(GC_MALLOC_ATOMIC(static_cast<std::size_t>(size) + 1));
    if (!bytes) throw std::bad_alloc();
    std::memcpy(bytes, a->bytes, a->size);
    std::memcpy(bytes + a->size, b->bytes, b->size);
    bytes[size] = 0;
    return make<String>(String{bytes, size});
}

// Base conversion has a bounded stack buffer; precision padding is allocated
// once in the traced heap, independent of the number of digits.
template<class T> String *integer_text(T value, std::int32_t base,
                                       std::int32_t precision, Bool uppercase) {
    if (base < 2 || (base > 36 && base != 62) || (base == 62 && uppercase) || precision < 0)
        throw Raised(exception("Invalid integer format", "|ArgumentError|Exception|"));
    const char *digits = base == 62 ? "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" :
                         uppercase ? "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" : "0123456789abcdefghijklmnopqrstuvwxyz";
    using Unsigned = typename UnsignedOf<T>::type;
    const bool negative = SignedOf<T>::value && value < 0;
    Unsigned magnitude = negative ? Unsigned(0) - static_cast<Unsigned>(value) : static_cast<Unsigned>(value);
    char reversed[sizeof(T) * 8];
    std::int32_t count = 0;
    while (magnitude) {
        reversed[count++] = digits[magnitude % base];
        magnitude /= base;
    }
    const std::int32_t width = count > precision ? count : precision;
    if (width == INT32_MAX && negative) throw Raised("String size overflow");
    const std::int32_t size = width + negative;
    char *bytes = static_cast<char *>(GC_MALLOC_ATOMIC(static_cast<std::size_t>(size) + 1));
    if (!bytes) throw std::bad_alloc();
    if (negative) bytes[0] = '-';
    std::memset(bytes + negative, '0', width - count);
    for (std::int32_t i = 0; i < count; ++i) bytes[size - i - 1] = reversed[i];
    bytes[size] = 0;
    return make<String>(String{bytes, size});
}

struct StringBuilder;

// Crystal's reader consumes one byte and reports it when UTF-8 is malformed.
// utf8proc supplies validation and decoding; the adapter preserves byte offsets.
struct CharReader {
    String *string = nullptr;
    std::int32_t pos = 0;
    std::uint32_t current = 0;
    std::int32_t width = 1;
    Value error;
    static CharReader create(String *string, std::int32_t pos = 0) {
        CharReader reader;
        reader.string = string;
        reader.set_pos(pos);
        return reader;
    }
    void decode() {
        error = Value{};
        current = 0;
        width = 1;
        if (pos == string->size) return;
        utf8proc_int32_t point;
        const auto bytes = reinterpret_cast<const std::uint8_t *>(string->bytes + pos);
        const auto count = utf8proc_iterate(bytes, string->size - pos, &point);
        if (count < 0) {
            current = 0xfffd;
            error = box(bytes[0], "UInt8");
        } else {
            current = static_cast<std::uint32_t>(point);
            width = static_cast<std::int32_t>(count);
        }
    }
    std::int32_t set_pos(std::int32_t value) {
        if (value < 0 || value > string->size)
            throw Raised(exception("Index out of bounds", "|IndexError|Exception|"));
        pos = value;
        decode();
        return pos;
    }
    bool has_next() const { return pos < string->size; }
    std::uint32_t next() {
        if (!has_next()) throw Raised(exception("Index out of bounds", "|IndexError|Exception|"));
        set_pos(pos + width);
        return current;
    }
    std::uint32_t peek() const { CharReader copy = *this; return copy.next(); }
};

inline std::int32_t character_count(String *string) {
    // Lexer slices repeatedly query the size of the entire source string.
    // Match upstream's immutable String cache to avoid rescanning it per token.
    if (string->length) return string->length;
    CharReader reader = CharReader::create(string);
    std::int32_t count = 0;
    while (reader.has_next()) { ++count; reader.next(); }
    return string->length = count;
}

} // namespace seed
#endif
