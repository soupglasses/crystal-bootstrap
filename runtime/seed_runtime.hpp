#ifndef CRYSTAL_BOOTSTRAP_SEED_RUNTIME_HPP
#define CRYSTAL_BOOTSTRAP_SEED_RUNTIME_HPP

#include <cstdint>
#include <cmath>
#include <cstring>
#include <exception>
#include <limits>
#include <stdexcept>
#include <new>
#include <type_traits>
#include <utility>
#include <vector>
#include <tuple>
#include <array>
#include <utf8proc.h>
#include <gc/gc.h>
#include <gc/gc_allocator.h>

namespace seed {

inline std::int32_t &argc() { static std::int32_t value = 0; return value; }
inline std::uint8_t **&argv() { static std::uint8_t **value = nullptr; return value; }

// Keep this on the native stack; a collected local would not be a stack bound.
__attribute__((noinline)) inline void *stack_top() { return __builtin_frame_address(0); }

using Int128 = __int128;
using UInt128 = unsigned __int128;
template<class T> struct UnsignedOf { using type = typename std::make_unsigned<T>::type; };
template<> struct UnsignedOf<Int128> { using type = UInt128; };
template<> struct UnsignedOf<UInt128> { using type = UInt128; };
template<class T> struct SignedOf : std::is_signed<T> {};
template<> struct SignedOf<Int128> : std::true_type {};
template<> struct SignedOf<UInt128> : std::false_type {};
template<class T> T integer_from_bits(typename UnsignedOf<T>::type bits) { T value; std::memcpy(&value, &bits, sizeof value); return value; }
struct Nil {};
struct Type { const char *name; };
template<class T, class V> [[noreturn]] T unreachable(V) { throw std::logic_error("NoReturn expression returned"); }
// Native RTTI supplies checked inheritance casts; GC owns these objects and
// never deletes through this base, so no nontrivial destructor is needed.
struct Object {
    virtual const char *seed_type_name() const { return "Reference"; }
};
// A byte also avoids std::vector<bool> hiding its elements behind proxy references.
using Bool = std::uint8_t;

// GC-owned values must not depend on destructors to release external resources.
// File handles and foreign allocations need separate, explicit ownership.
template<class T, class... Args> T *make(Args&&... args) {
    static_assert(std::is_trivially_destructible<T>::value,
                  "GC payload requires trivial destruction");
    void *memory = GC_MALLOC(sizeof(T));
    if (!memory) throw std::bad_alloc();
    return new (memory) T(std::forward<Args>(args)...);
}

// One representation for all source unions keeps C++ template instantiation
// independent of the number of alternatives. Only non-scalar values are boxed.
struct Value {
    const char *type = nullptr;
    void *pointer = nullptr;
    std::uint64_t bits = 0;
};

inline Value box(Type value, const char *) {
    Value result;
    const auto length = std::strlen(value.name);
    char *name = static_cast<char *>(GC_MALLOC_ATOMIC(length + 7));
    if (!name) throw std::bad_alloc();
    std::memcpy(name, value.name, length);
    std::memcpy(name + length, ".class", 7);
    result.type = name;
    result.pointer = make<Type>(value);
    return result;
}
inline Value box(Nil, const char *) { return Value{}; }
template<class T> typename std::enable_if<std::is_arithmetic<T>::value && sizeof(T) <= 8, Value>::type
box(T value, const char *type) {
    Value result;
    result.type = type;
    static_assert(sizeof(T) <= sizeof(result.bits), "scalar payload");
    std::memcpy(&result.bits, &value, sizeof(T));
    return result;
}
template<class T> typename std::enable_if<!std::is_base_of<Object, T>::value, Value>::type
box(T *value, const char *type) {
    Value result;
    if (value) {
        result.type = type;
        result.pointer = const_cast<void *>(static_cast<const void *>(value));
    }
    return result;
}
template<class T> typename std::enable_if<std::is_base_of<Object, T>::value, Value>::type
box(T *value, const char *) {
    Value result;
    if (value) {
        result.type = value->seed_type_name();
        result.pointer = static_cast<Object *>(value);
    }
    return result;
}
template<class T> typename std::enable_if<(!std::is_arithmetic<T>::value || sizeof(T) > 8) && !std::is_pointer<T>::value, Value>::type
box(T value, const char *type) {
    Value result;
    result.type = type;
    result.pointer = make<T>(value);
    return result;
}
template<class T> typename std::enable_if<std::is_arithmetic<T>::value && sizeof(T) <= 8, T>::type
unbox(Value value) {
    T result;
    std::memcpy(&result, &value.bits, sizeof(T));
    return result;
}
template<class T> typename std::enable_if<std::is_pointer<T>::value && !std::is_base_of<Object, typename std::remove_pointer<T>::type>::value, T>::type
unbox(Value value) { return static_cast<T>(value.pointer); }
template<class T> typename std::enable_if<std::is_pointer<T>::value && std::is_base_of<Object, typename std::remove_pointer<T>::type>::value, T>::type
unbox(Value value) { return dynamic_cast<T>(static_cast<Object *>(value.pointer)); }
template<class T> typename std::enable_if<(!std::is_arithmetic<T>::value || sizeof(T) > 8) && !std::is_pointer<T>::value, T &>::type
unbox(Value value) { return *static_cast<T *>(value.pointer); }
template<> inline Nil &unbox<Nil>(Value) {
    static Nil nil;
    return nil;
}
inline bool is(Value value, const char *type) {
    return value.type ? std::strcmp(value.type, type) == 0 : std::strcmp(type, "Nil") == 0;
}
inline bool truth(Value value) {
    return value.type && (!is(value, "Bool") || unbox<Bool>(value));
}

// Crystal exposes these operations as LLVM intrinsics. Native compiler helpers
// preserve their bit-width semantics without linking LLVM into the runtime.
template<class T> std::int32_t leading_zeros(T input) {
    using U = typename UnsignedOf<T>::type;
    const auto bits = static_cast<unsigned long long>(static_cast<U>(input));
    return bits ? __builtin_clzll(bits) - (64 - sizeof(T) * 8) : sizeof(T) * 8;
}
template<class T> std::int32_t trailing_zeros(T input) {
    using U = typename UnsignedOf<T>::type;
    const auto bits = static_cast<unsigned long long>(static_cast<U>(input));
    return bits ? __builtin_ctzll(bits) : sizeof(T) * 8;
}
template<class T> std::int32_t population_count(T input) {
    using U = typename UnsignedOf<T>::type;
    return __builtin_popcountll(static_cast<unsigned long long>(static_cast<U>(input)));
}

inline const char *copy_string(const char *text) {
    const std::size_t size = std::strlen(text) + 1;
    void *memory = GC_MALLOC_ATOMIC(size);
    if (!memory) throw std::bad_alloc();
    return static_cast<const char *>(std::memcpy(memory, text, size));
}

// The native exception heap and exception_ptr are not necessarily traced.
// Each transport owns a temporary traced root, released even when replaced.
template<class T> class Root {
    T *value_;
public:
    explicit Root(T value) {
        static_assert(std::is_trivially_destructible<T>::value, "root payload");
        void *memory = GC_MALLOC_UNCOLLECTABLE(sizeof(T));
        if (!memory) throw std::bad_alloc();
        value_ = new (memory) T(value);
    }
    Root(const Root &other) : Root(other.get()) {}
    Root(Root &&other) noexcept : value_(other.value_) { other.value_ = nullptr; }
    Root &operator=(Root other) noexcept { std::swap(value_, other.value_); return *this; }
    ~Root() { if (value_) GC_FREE(value_); }
    T get() const { return *value_; }
};

// Nil carries no pointers. Block control in a collector callback must not
// allocate another traced root while the collector is already running.
template<> class Root<Nil> {
public:
    explicit Root(Nil) {}
    Nil get() const { return Nil{}; }
};

struct String;

struct ExceptionField {
    const char *name;
    void *value;
    ExceptionField *next;
};

struct Exception : Object {
    const char *message = nullptr;
    const char *ancestry = "|Exception|";
    std::int32_t message_size = 0;
    ExceptionField *fields = nullptr;
    const char *kind = "Exception";
    Exception() = default;
    Exception(const char *text, const char *parents, std::int32_t size)
        : message(text), ancestry(parents), message_size(size) {
        const char *end = std::strchr(parents + 1, '|');
        const auto length = static_cast<std::size_t>(end - parents - 1);
        char *name = static_cast<char *>(GC_MALLOC_ATOMIC(length + 1));
        if (!name) throw std::bad_alloc();
        std::memcpy(name, parents + 1, length);
        name[length] = 0;
        kind = name;
    }
    const char *seed_type_name() const override { return kind; }
    bool is(const char *type) const { return std::strstr(ancestry, type) != nullptr; }
    void *find(const char *name) const {
        for (auto field = fields; field; field = field->next)
            if (std::strcmp(field->name, name) == 0) return field->value;
        return nullptr;
    }
    const char *what_bytes() const noexcept;
};

// Exception payload layouts remain generated Crystal code. Sparse, traced
// slots also let runtime-created errors participate in typed Crystal rescue.
template<class T> T &exception_slot(Exception *error, const char *name) {
    if (void *value = error->find(name)) return *static_cast<T *>(value);
    T *value = make<T>();
    error->fields = make<ExceptionField>(ExceptionField{name, value, error->fields});
    return *value;
}
inline Exception *new_exception(const char *ancestry) {
    return make<Exception>(nullptr, ancestry, 0);
}

inline Exception *exception(const char *message, const char *ancestry = "|Exception|") {
    return make<Exception>(Exception{copy_string(message), ancestry, static_cast<std::int32_t>(std::strlen(message))});
}

struct Raised : std::exception {
    Root<Exception *> object;
    explicit Raised(String *message);
    explicit Raised(Exception *value) : object(value) {}
    explicit Raised(const char *message) : object(seed::exception(message)) {}
    const char *what() const noexcept override { return object.get()->what_bytes(); }
};

template<class T> T *not_nil(T *value) {
    if (!value) throw Raised(exception("Nil assertion failed", "|NilAssertionError|Exception|"));
    return value;
}

template<class Tag, class T> struct Return {
    Root<T> value;
    explicit Return(T result) : value(result) {}
};

template<class R> struct CReturn {
    using type = R;
    template<class F, class... A> static R call(F function, A... args) { return function(args...); }
    template<class F, class... A> static R from(F function, A... args) { return function(args...); }
};
template<> struct CReturn<Nil> {
    using type = void;
    template<class F, class... A> static void call(F function, A... args) { function(args...); }
    template<class F, class... A> static Nil from(F function, A... args) { function(args...); return Nil{}; }
};
template<class Signature> struct CFunctionType;
template<class R, class... A> struct CFunctionType<R(A...)> { using type = typename CReturn<R>::type (*)(A...); };
template<class Signature> using CFunction = typename CFunctionType<Signature>::type;

// C accepts capture-free procs only, as in upstream Crystal. Each lambda type
// has one stable trampoline; its function pointer needs no collected storage.
template<class F, class R, class... A> struct CCallback {
    static R (*&function())(A...) { static R (*value)(A...) = nullptr; return value; }
    static typename CReturn<R>::type invoke(A... args) { return CReturn<R>::call(function(), args...); }
};
template<class Signature> class Proc;
template<class R, class... Args> class Proc<R(Args...)> {
    void *environment_ = nullptr;
    R (*invoke_)(void *, Args...) = nullptr;
    CFunction<R(Args...)> c_function_ = nullptr;
    template<class F> void prepare_c(F body, std::true_type) {
        CCallback<F, R, Args...>::function() = body;
        c_function_ = &CCallback<F, R, Args...>::invoke;
    }
    template<class F> void prepare_c(F, std::false_type) {}
    template<class F> static R invoke(void *environment, Args... args) {
        return (*static_cast<F *>(environment))(args...);
    }
public:
    Proc() = default;
    template<class F> static Proc from(F body) {
        Proc proc;
        proc.prepare_c(body, typename std::is_convertible<F, R (*)(Args...)>::type{});
        if (!proc.c_function_) {
            proc.environment_ = make<F>(body);
            proc.invoke_ = &invoke<F>;
        }
        return proc;
    }
    // Synchronous yield blocks borrow a callable on their caller's stack.
    // This also keeps collector callbacks free of implicit GC allocations.
    template<class F> static Proc borrow(F &body) {
        Proc proc;
        proc.environment_ = &body;
        proc.invoke_ = &invoke<F>;
        return proc;
    }
    static Proc from_pointer(void *function, void *environment) {
        Proc proc;
        if (environment) {
            proc.environment_ = environment;
            proc.invoke_ = reinterpret_cast<R (*)(void *, Args...)>(function);
        } else {
            proc.c_function_ = reinterpret_cast<CFunction<R(Args...)>>(function);
        }
        return proc;
    }
    void *closure_data() const { return c_function_ ? nullptr : environment_; }
    void *pointer() const { return c_function_ ? reinterpret_cast<void *>(c_function_) : reinterpret_cast<void *>(invoke_); }
    CFunction<R(Args...)> c_function() const {
        if (c_function_) return c_function_;
        if (!invoke_) return nullptr;
        throw std::logic_error("C callback captures a closure");
    }
    R operator()(Args... args) const {
        if (c_function_) return CReturn<R>::from(c_function_, args...);
        if (!invoke_) throw std::logic_error("uninitialized Proc");
        return invoke_(environment_, args...);
    }
};

template<class R, class... Args> Value box(Proc<R(Args...)> value, const char *type) {
    if (!value.pointer()) return Value{};
    Value result;
    result.type = type;
    result.pointer = make<Proc<R(Args...)>>(value);
    return result;
}

// Field names follow Array's typed instance variables so ordinary upstream
// methods and literal adapters share storage, including shifted buffers.
template<class T> class Array : public Object {
    std::int32_t index(std::int32_t offset) const {
        const std::int64_t position = offset < 0 ? std::int64_t(size()) + offset : offset;
        if (position < 0 || position >= size())
            throw Raised(exception("Index out of bounds", "|IndexError|Exception|"));
        return static_cast<std::int32_t>(position);
    }
public:
    const char *type_name = "Array";
    const char *seed_type_name() const override { return type_name; }
    std::int32_t field_nsize = 0;
    std::int32_t field_ncapacity = 0;
    std::int32_t field_noffset_uto_ubuffer = 0;
    T *field_nbuffer = nullptr;
    static Array *create(std::int32_t capacity = 0, const char *type_name = "Array") {
        if (capacity < 0) throw Raised(exception("Negative array capacity", "|ArgumentError|Exception|"));
        Array *array = make<Array>();
        array->type_name = type_name;
        array->field_ncapacity = capacity;
        if (capacity) {
            array->field_nbuffer = static_cast<T *>(GC_MALLOC(std::size_t(capacity) * sizeof(T)));
            if (!array->field_nbuffer) throw std::bad_alloc();
            for (std::int32_t i = 0; i < capacity; ++i) new (array->field_nbuffer + i) T{};
        }
        return array;
    }
    std::int32_t size() const { return field_nsize; }
    bool empty() const { return !field_nsize; }
    T *data() { return field_nbuffer; }
    static Array *unsafe_build(std::int32_t size, const char *type_name = "Array") {
        Array *array = create(size, type_name);
        array->field_nsize = size;
        return array;
    }
    T at(std::int32_t offset) const { return field_nbuffer[index(offset)]; }
    T set(std::int32_t offset, T value) { field_nbuffer[index(offset)] = value; return value; }
    Array *push(T value) {
        if (field_nsize == INT32_MAX)
            throw Raised(exception("Array size overflow", "|OverflowError|Exception|"));
        // Upstream shift/unshift can move the live buffer within its allocation.
        // Capacity includes the prefix, which is unavailable for appending.
        if (field_nsize == field_ncapacity - field_noffset_uto_ubuffer) {
            const auto capacity = field_ncapacity > INT32_MAX / 2 ? INT32_MAX : std::max(4, field_ncapacity * 2);
            Array *grown = create(capacity);
            for (std::int32_t i = 0; i < field_nsize; ++i) grown->field_nbuffer[i] = field_nbuffer[i];
            field_nbuffer = grown->field_nbuffer;
            field_ncapacity = capacity;
            field_noffset_uto_ubuffer = 0;
        }
        field_nbuffer[field_nsize++] = value;
        return this;
    }
    T pop() {
        if (empty()) throw Raised(exception("Empty array", "|IndexError|Exception|"));
        T value = field_nbuffer[--field_nsize];
        field_nbuffer[field_nsize] = T{};
        return value;
    }
    Array *clear() {
        for (std::int32_t i = 0; i < field_nsize; ++i) field_nbuffer[i] = T{};
        field_nsize = 0;
        return this;
    }
};

// Cleanup can replace a pending exception or return. A destructor cannot do
// this: throwing from one during C++ unwinding would terminate the process.
template<class Body, class Cleanup>
void ensure(Body body, Cleanup cleanup) {
    std::exception_ptr pending;
    try {
        body();
    } catch (...) {
        pending = std::current_exception();
    }
    cleanup();
    if (pending) std::rethrow_exception(pending);
}

inline std::int32_t wrapping_add_i32(std::int32_t left, std::int32_t right) {
    std::uint32_t bits = static_cast<std::uint32_t>(left) + static_cast<std::uint32_t>(right);
    std::int32_t value;
    static_assert(sizeof value == sizeof bits, "32-bit integer representation required");
    std::memcpy(&value, &bits, sizeof value);
    return value;
}

inline std::int32_t checked_add_i32(std::int32_t left, std::int32_t right) {
    std::int64_t result = static_cast<std::int64_t>(left) + right;
    if (result < std::numeric_limits<std::int32_t>::min() ||
        result > std::numeric_limits<std::int32_t>::max()) {
        throw Raised(exception("Arithmetic overflow", "|OverflowError|Exception|"));
    }
    return static_cast<std::int32_t>(result);
}

template<class T> T add(T a, T b) {
    T result;
    if (__builtin_add_overflow(a, b, &result)) throw Raised(exception("Arithmetic overflow", "|OverflowError|Exception|"));
    return result;
}
template<class T> T subtract(T a, T b) {
    T result;
    if (__builtin_sub_overflow(a, b, &result)) throw Raised(exception("Arithmetic overflow", "|OverflowError|Exception|"));
    return result;
}
template<class T> T multiply(T a, T b) {
    T result;
    if (__builtin_mul_overflow(a, b, &result)) throw Raised(exception("Arithmetic overflow", "|OverflowError|Exception|"));
    return result;
}
template<class T> T wrap_add(T a, T b) { T result; __builtin_add_overflow(a, b, &result); return result; }
template<class T> T wrap_subtract(T a, T b) { T result; __builtin_sub_overflow(a, b, &result); return result; }
template<class T> T wrap_multiply(T a, T b) { T result; __builtin_mul_overflow(a, b, &result); return result; }
template<class T> T *allocate(std::uint64_t count) {
    if (count > SIZE_MAX / sizeof(T)) throw std::bad_alloc();
    T *memory = static_cast<T *>(GC_MALLOC(static_cast<std::size_t>(count) * sizeof(T)));
    if (!memory) throw std::bad_alloc();
    for (std::uint64_t index = 0; index < count; ++index) new (memory + index) T{};
    return memory;
}
template<class T> T *reallocate(T *memory, std::uint64_t count) {
    if (count > SIZE_MAX / sizeof(T)) throw std::bad_alloc();
    T *result = static_cast<T *>(GC_REALLOC(memory, static_cast<std::size_t>(count) * sizeof(T)));
    if (!result && count) throw std::bad_alloc();
    return result;
}

template<class T> std::tuple<T, Bool> compare_exchange(T *pointer, T expected, T value) {
    const Bool changed = __atomic_compare_exchange_n(pointer, &expected, value, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    return std::make_tuple(expected, changed);
}

// LLVM funnel shifts reduce the count modulo the element width:
// https://llvm.org/docs/LangRef.html#llvm-fshl-intrinsic
template<class T> T fshl(T high, T low, T amount) {
    constexpr unsigned width = sizeof(T) * 8;
    const unsigned count = static_cast<unsigned>(amount % width);
    using U = typename UnsignedOf<T>::type;
    return count ? static_cast<T>((U(high) << count) | (U(low) >> (width - count))) : high;
}
template<class T> T fshr(T high, T low, T amount) {
    constexpr unsigned width = sizeof(T) * 8;
    const unsigned count = static_cast<unsigned>(amount % width);
    using U = typename UnsignedOf<T>::type;
    return count ? static_cast<T>((U(high) << (width - count)) | (U(low) >> count)) : low;
}

template<class T, class N> T shift_left(T value, N count) {
    if (count < 0 || static_cast<std::uint64_t>(count) >= sizeof(T) * 8) return 0;
    using U = typename UnsignedOf<T>::type;
    U bits = static_cast<U>(value) << count;
    T result;
    std::memcpy(&result, &bits, sizeof(T));
    return result;
}
template<class T, class N> T shift_right(T value, N count) {
    if (count < 0 || static_cast<std::uint64_t>(count) >= sizeof(T) * 8) return 0;
    // GCC and Clang implement arithmetic right shift for signed integers.
    return value >> count;
}
template<class T> T divide(T a, T b) {
    if (!b) throw Raised(exception("Division by zero", "|DivisionByZeroError|Exception|"));
    if (SignedOf<T>::value && a == std::numeric_limits<T>::min() && b == T(-1))
        throw Raised(exception("Arithmetic overflow", "|OverflowError|Exception|"));
    return a / b;
}
template<class T> T remainder(T a, T b) {
    if (!b) throw Raised(exception("Division by zero", "|DivisionByZeroError|Exception|"));
    if (SignedOf<T>::value && a == std::numeric_limits<T>::min() && b == T(-1)) return 0;
    return a % b;
}

inline std::int32_t sum_i32(Array<std::int32_t> *array) {
    std::int32_t sum = 0;
    for (std::int32_t i = 0; i < array->size(); ++i) sum = checked_add_i32(sum, array->at(i));
    return sum;
}

} // namespace seed
#include "seed_text.hpp"
#endif
