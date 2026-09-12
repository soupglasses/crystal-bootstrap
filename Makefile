CRYSTAL ?= crystal
CRYSTAL_SRC ?= ../../crystal-lang/crystal
LLVM_CONFIG ?= llvm-config
CXX ?= g++
NATIVE_OPTIMIZE ?= 0
PYTHON ?= python3
TARGET ?= $(shell $(PYTHON) -c 'import json; print(json.load(open("release.json"))["targets"][0]["version"])')
OUTPUT ?= build/generated/$(TARGET)
SNAPSHOT ?= $(OUTPUT)/snapshot
BOOTSTRAP_HOST ?= $(abspath build/reference-crystal)

UPSTREAM := $(abspath $(CRYSTAL_SRC))
GENERATOR := build/crystal-to-cpp
REFERENCE := build/reference-crystal
GENERATOR_FLAGS := -Dwithout_interpreter -Dwithout_mt -Dwithout_libxml2 -Dwithout_openssl -Dwithout_zlib
GENERATOR_ENV = CRYSTAL_PATH="$(UPSTREAM)/lib:$(UPSTREAM)/src" CRYSTAL_CACHE_DIR="$(abspath build/cache)" LLVM_CONFIG="$(LLVM_CONFIG)"

.PHONY: help generator reference check regen check-snapshot check-memory
help:
	@echo 'make generate: generate and refresh build/generated/<version> (downloads pinned inputs)'
	@echo 'make check CRYSTAL=/path/to/crystal: build the generator and run differential probes'
	@echo 'make regen: explicitly refresh the readable example snapshots'
	@echo 'make check-snapshot: compile and check locally generated snapshots without Crystal'
	@echo 'make check-memory: run the bounded-heap runtime stress test'
	@echo 'make check-compiler: compare real compiler components through split native snapshots'
	@echo 'make inventory / attempt-compiler / attempt-lexer: measure coverage and current blockers'
	@echo 'make stage0-snapshot SNAPSHOT=build/compiler-source: regenerate the full source snapshot'
	@echo 'make stage0 SNAPSHOT=build/compiler-source: build stage0 using only native tools'
	@echo 'make bootstrap: build stage0, stage1 and Crystal without an existing Crystal compiler'
	@echo 'make check-bootstrap BOOTSTRAP_HOST=/path/to/crystal: compare the complete compiler chain'

generator: $(GENERATOR)
reference: $(REFERENCE)

# Upstream internals are an explicit input; always rebuild this small prototype
# driver when requested so changing CRYSTAL_SRC cannot reuse a stale adapter.
.PHONY: FORCE
$(GENERATOR): FORCE
	@mkdir -p build
	$(GENERATOR_ENV) $(CRYSTAL) build generator/main.cr -o $@ $(GENERATOR_FLAGS) --error-trace

$(REFERENCE): FORCE
	@mkdir -p build
	$(GENERATOR_ENV) CRYSTAL_HAS_WRAPPER=1 $(CRYSTAL) build "$(UPSTREAM)/src/compiler/crystal.cr" -o $@ $(GENERATOR_FLAGS) -Dstrict_multi_assign -Dpreview_overload_order --error-trace

check: regen reference
	$(GENERATOR_ENV) CRYSTAL="$(CRYSTAL)" REFERENCE_CRYSTAL="$(abspath $(REFERENCE))" CRYSTAL_SRC="$(UPSTREAM)" CXX="$(CXX)" $(PYTHON) -u tests/check.py

regen: generator
	$(GENERATOR_ENV) CRYSTAL="$(CRYSTAL)" CRYSTAL_SRC="$(UPSTREAM)" $(PYTHON) -u tests/check.py --regen

check-snapshot:
	CXX="$(CXX)" $(PYTHON) -u tests/check.py --snapshot-only

check-memory:
	@mkdir -p build
	$(CXX) -std=c++11 -O2 -Wall -Wextra -Werror -I runtime tests/runtime/memory.cpp -o build/runtime-memory $$(pkg-config --cflags --libs bdw-gc libutf8proc)
	./build/runtime-memory

.PHONY: inventory attempt-compiler check-compiler
inventory: generator
	$(GENERATOR_ENV) CRYSTAL_SRC="$(UPSTREAM)" $(PYTHON) tools/compiler_probe.py inventory

# This target fails on the first unsupported compiler feature; it never
# substitutes an installed Crystal for an unfinished source translation.
attempt-compiler: generator
	$(GENERATOR_ENV) CRYSTAL_SRC="$(UPSTREAM)" $(PYTHON) tools/compiler_probe.py translate

check-compiler: generator reference
	$(GENERATOR_ENV) CRYSTAL_SRC="$(UPSTREAM)" REFERENCE_CRYSTAL="$(abspath $(REFERENCE))" CXX="$(CXX)" $(PYTHON) -u tests/check_compiler.py

.PHONY: attempt-lexer
attempt-lexer: generator
	$(GENERATOR_ENV) CRYSTAL_SRC="$(UPSTREAM)" $(PYTHON) tools/compiler_probe.py lexer

.PHONY: stage0-snapshot stage0 bootstrap check-bootstrap
stage0-snapshot: generator
	$(GENERATOR_ENV) CRYSTAL_SRC="$(UPSTREAM)" $(PYTHON) tools/compiler_probe.py stage0 --output-dir "$(SNAPSHOT)"

# The LLVM bridge is upstream C++ source, not a Crystal-produced object file.
build/llvm_ext.o: $(UPSTREAM)/src/llvm/ext/llvm_ext.cc
	@mkdir -p build
	$(CXX) -c $< -o $@ $$($(LLVM_CONFIG) --cxxflags)

# Deliberately has no generator or reference compiler prerequisite.
stage0: build/llvm_ext.o
	$(PYTHON) tools/measure.py build/stage0-native.metrics.json $(PYTHON) tools/build_snapshot.py "$(SNAPSHOT)" \
	  --cxx "$(CXX)" --optimize "$(NATIVE_OPTIMIZE)" --object build/llvm_ext.o --build-dir build/stage0-native --precompile-header \
	  --link-flags="$$($(LLVM_CONFIG) --ldflags --libs --system-libs) -lpcre2-8" -o build/crystal-stage0

bootstrap:
	$(MAKE) -C "$(OUTPUT)" CXX="$(CXX)" LLVM_CONFIG="$(LLVM_CONFIG)"

check-bootstrap:
	LLVM_CONFIG="$(LLVM_CONFIG)" CRYSTAL_SRC="$(UPSTREAM)" $(PYTHON) tools/bootstrap.py \
	  --host "$(BOOTSTRAP_HOST)" --stage0 build/crystal-stage0

.PHONY: generate check-release
generate:
	$(PYTHON) -u tools/generate.py --target "$(TARGET)" $(if $(filter command line environment,$(origin CRYSTAL)),--crystal "$(CRYSTAL)") --llvm-config "$(LLVM_CONFIG)" --output-dir "$(OUTPUT)"

check-release:
	$(PYTHON) -m unittest discover -s tests -p 'test_release.py'
