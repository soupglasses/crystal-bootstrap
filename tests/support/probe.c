#include <stdint.h>
#include <stdio.h>

void probe_emit(int32_t value) {
    printf("%d\n", (int)value);
}

#include <stdlib.h>
#include <gc/gc.h>

static size_t probe_allocated_before;
static size_t probe_heap_limit;

void probe_gc_limit(int32_t mebibytes) {
    GC_INIT();
    probe_heap_limit = (size_t)mebibytes * 1024 * 1024;
    GC_set_max_heap_size(probe_heap_limit);
    probe_allocated_before = GC_get_total_bytes();
}

void probe_gc_check(int32_t minimum_mebibytes) {
    GC_gcollect();
    if (GC_get_total_bytes() - probe_allocated_before < (size_t)minimum_mebibytes * 1024 * 1024 ||
        GC_get_heap_size() > probe_heap_limit) {
        fprintf(stderr, "GC allocation-pressure check failed\n");
        exit(1);
    }
}
