#include "seed_runtime.hpp"
#include <cstdio>
#include <cstdlib>
#include <memory>

#if defined(__GNUC__) || defined(__clang__)
#define NOINLINE __attribute__((noinline))
#else
#define NOINLINE
#endif

static void require(bool condition, const char *message) {
    if (!condition) { std::fprintf(stderr, "%s\n", message); std::exit(1); }
}

struct Node {
    seed::Array<seed::Proc<std::int32_t()>> *callbacks;
    Node *next;
    const char *payload;
    std::int32_t value;
};

NOINLINE static Node *graph(std::int32_t value) {
    Node *node = seed::make<Node>();
    node->value = value;
    node->next = node;
    char *payload = static_cast<char *>(GC_MALLOC_ATOMIC(128 * 1024));
    if (!payload) throw std::bad_alloc();
    std::memset(payload, 'x', 128 * 1024);
    payload[128 * 1024 - 1] = '\0';
    node->payload = payload;
    node->callbacks = seed::Array<seed::Proc<std::int32_t()>>::create();
    node->callbacks->push(seed::Proc<std::int32_t()>::from([node]() {
        require(node->next == node, "cycle corrupted");
        require(node->payload[128 * 1024 - 2] == 'x', "closure lost payload");
        return node->value;
    }));
    return node;
}

// Clear abandoned frames before collecting; conservative stack retention should
// not make the outcome depend on the previous helper's register allocation.
NOINLINE static void collect() {
    volatile std::uintptr_t scrub[16384] = {};
    GC_gcollect();
    (void)scrub[0];
}

struct ReturnTag {};
[[noreturn]] NOINLINE static void return_graph(std::int32_t value) {
    throw seed::Return<ReturnTag, Node *>(graph(value));
}

[[noreturn]] NOINLINE static void raise_message() {
    Node *node = graph(19);
    throw seed::Raised(seed::exception(node->payload, "|ParseFailure|Exception|"));
}

// A native allocation deliberately hides exception_ptr from the collector.
// The runtime must root the payload independently until transport is destroyed.
NOINLINE static std::unique_ptr<std::exception_ptr> pending(bool raised) {
    try {
        if (raised) raise_message();
        return_graph(41);
    } catch (...) {
        return std::unique_ptr<std::exception_ptr>(new std::exception_ptr(std::current_exception()));
    }
}

int main() {
    GC_INIT();
    const std::size_t limit = 32 * 1024 * 1024;
    GC_set_max_heap_size(limit);
    const std::size_t before = GC_get_total_bytes();
    auto returned = pending(false);
    auto raised = pending(true);
    auto retained = seed::Array<Node *>::create();
    auto scratch = seed::Array<Node *>::create(128);
    auto union_values = seed::Array<seed::Value>::create();
    using Callback = seed::Proc<std::int32_t()>;
    for (std::int32_t i = 0; i < 12000; ++i) {
        Node *node = graph(i);
        scratch->push(node);
        require(scratch->pop()->value == i, "pop lost identity");
        if (i < 16) retained->push(node);
        else retained->set(i % 16, node);
        union_values->clear();
        union_values->push(seed::box(node, "Node"));
        union_values->push(seed::box(node->callbacks->at(0), "Proc"));
        union_values->push(seed::box(i, "Int32"));
        if (i % 32 == 0) {
            collect();
            require(retained->at(i % 16)->callbacks->at(0)() == i, "live graph lost");
            require(seed::unbox<Node *>(union_values->at(0))->value == i, "union pointer lost");
            require(seed::unbox<Callback>(union_values->at(1))() == i, "boxed closure lost");
            require(seed::unbox<std::int32_t>(union_values->at(2)) == i, "union scalar changed");
        }
        // A replaced control-flow exception must release its uncollectable root.
        try {
            seed::ensure([i]() { return_graph(i); }, []() {
                throw seed::Raised("replacement");
            });
        } catch (const seed::Raised &error) {
            require(std::strcmp(error.what(), "replacement") == 0, "cleanup replacement");
        }
    }
    union_values->clear();
    retained->clear();
    collect();
    try { std::rethrow_exception(*returned); }
    catch (const seed::Return<ReturnTag, Node *> &result) {
        require(result.value.get()->callbacks->at(0)() == 41, "pending return lost GC root");
    }
    try { std::rethrow_exception(*raised); }
    catch (const seed::Raised &error) {
        require(error.object.get()->is("|Exception|"), "exception ancestry");
        require(std::strlen(error.what()) == 128 * 1024 - 1, "pending exception lost GC root");
    }
    returned.reset();
    raised.reset();
    collect();
    const std::size_t allocated = GC_get_total_bytes() - before;
    require(allocated > 1024ULL * 1024 * 1024, "insufficient allocation pressure");
    require(GC_get_heap_size() <= limit, "collector exceeded configured heap limit");
    std::printf("allocated_bytes=%zu heap_bytes=%zu free_bytes=%zu collections=%zu\n",
                allocated, GC_get_heap_size(), GC_get_free_bytes(),
                static_cast<std::size_t>(GC_get_gc_no()));
}
