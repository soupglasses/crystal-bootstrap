PYTHON ?= python3
CXX ?= c++
LLVM_CONFIG ?= llvm-config
OUTPUT ?= build
FINAL_FLAGS ?= --release --no-debug --threads 1 -Dstrict_multi_assign -Dpreview_overload_order

.PHONY: all
all:
	$(PYTHON) tools/build_source.py --cxx "$(CXX)" --llvm-config "$(LLVM_CONFIG)" \
	  --output-dir "$(OUTPUT)" --final-flags="$(FINAL_FLAGS)"
