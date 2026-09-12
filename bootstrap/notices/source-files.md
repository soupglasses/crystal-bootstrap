# Upstream source-file notices

The following comment blocks are retained from the pinned Crystal source.
They supplement the repository and shard license notices.

## src/crystal/fd_lock.cr

```crystal
# The general design is influenced by fdMutex in Go (LICENSE: BSD 3-Clause,
# Copyright Google):
# https://github.com/golang/go/blob/go1.25.1/src/internal/poll/fd_mutex.go
#
# The internal details (spinlock, designated waker) of the locks are heavily
# influenced by the nsync library (LICENSE: Apache-2.0, Copyright Google):
# https://github.com/google/nsync

# :nodoc:
#
# Tracks active references over a system file descriptor (fd) and serializes
# reads and writes.
#
# Every read on the fd must lock read.
# Every write on the fd must lock write.
# Other operations (fcntl, setsockopt, ...) must acquire a shared reference.
#
# The read and write locks are exclusive but distinct: each can only be acquired
# once, but both can be acquire at the same time. Shared references can happen
# at any time. Both locks also acquire a shared reference while the lock is
# acquired.
#
# The fdlock can be closed at any time (at which point we can't lock for read,
# write or acquire a shared reference anymore), but the actual system close will
# wait until there are no more references left. This avoids potential races when
# a thread might try to read a fd that has been closed... and has been reused by
# the OS for example.
#
# NOTE: since only one attempt to read (or write) can go through, it avoids
# situations where multiple fibers are waiting, then the first fiber is resumed but
# doesn't consume/fill everything, and... won't resume the next fiber! The lock
# will always resume a waiting fiber (if any).
#
# Lock concepts
#
# Spinlock: slow-path for lock/unlock will spin until it acquires the spinlock
# bit to add/remove waiters; the CPU is relaxed between each attempt.
#
# Designated waker: set on unlock to report that a waiter has been scheduler and
# there's no need to wake another one. It's unset when a waiter acquires or
# fails to acquire and adds itself again as a waiter. This leads to an
# impressive performance boost when the lock is contended.
```

## src/crystal/system/win32/group.cr

```crystal
# This file contains source code derived from the following:
#
# * https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/os/user/lookup_windows.go
# * https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/syscall/security_windows.go
#
# The following is their license:
#
# Copyright 2009 The Go Authors.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#    * Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above
# copyright notice, this list of conditions and the following disclaimer
# in the documentation and/or other materials provided with the
# distribution.
#    * Neither the name of Google LLC nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## src/crystal/system/win32/user.cr

```crystal
# This file contains source code derived from the following:
#
# * https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/os/user/lookup_windows.go
# * https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/syscall/security_windows.go
#
# The following is their license:
#
# Copyright 2009 The Go Authors.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#    * Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above
# copyright notice, this list of conditions and the following disclaimer
# in the documentation and/or other materials provided with the
# distribution.
#    * Neither the name of Google LLC nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## src/crystal/system/win32/visual_studio.cr

```crystal
    # ported from https://github.com/microsoft/vswhere/wiki/Find-VC
    # Copyright (C) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
```

## src/float/printer/cached_powers.cr

```crystal
# CachedPowers is ported from the C++ "double-conversions" library.
# The following is their license:
#   Copyright 2006-2008 the V8 project authors. All rights reserved.
#   Redistribution and use in source and binary forms, with or without
#   modification, are permitted provided that the following conditions are
#   met:
#
#       * Redistributions of source code must retain the above copyright
#         notice, this list of conditions and the following disclaimer.
#       * Redistributions in binary form must reproduce the above
#         copyright notice, this list of conditions and the following
#         disclaimer in the documentation and/or other materials provided
#         with the distribution.
#       * Neither the name of Google Inc. nor the names of its
#         contributors may be used to endorse or promote products derived
#         from this software without specific prior written permission.
#
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## src/float/printer/diy_fp.cr

```crystal
# DiyFP is ported from the C++ "double-conversions" library.
#
# The following is their license:
#   Copyright 2010 the V8 project authors. All rights reserved.
#   Redistribution and use in source and binary forms, with or without
#   modification, are permitted provided that the following conditions are
#   met:
#
#       * Redistributions of source code must retain the above copyright
#         notice, this list of conditions and the following disclaimer.
#       * Redistributions in binary form must reproduce the above
#         copyright notice, this list of conditions and the following
#         disclaimer in the documentation and/or other materials provided
#         with the distribution.
#       * Neither the name of Google Inc. nor the names of its
#         contributors may be used to endorse or promote products derived
#         from this software without specific prior written permission.
#
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## src/float/printer/dragonbox.cr

```crystal
# Source port of Dragonbox's reference implementation in C++.
#
# The following is their license:
#
#   Copyright 2020-2021 Junekey Jeon
#
#   The contents of this file may be used under the terms of
#   the Apache License v2.0 with LLVM Exceptions.
#
#      (See accompanying file LICENSE-Apache or copy at
#       https://llvm.org/foundation/relicensing/LICENSE.txt)
#
#   Alternatively, the contents of this file may be used under the terms of
#   the Boost Software License, Version 1.0.
#      (See accompanying file LICENSE-Boost or copy at
#       https://www.boost.org/LICENSE_1_0.txt)
#
#   Unless required by applicable law or agreed to in writing, this software
#   is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#   KIND, either express or implied.
```

## src/float/printer/grisu3.cr

```crystal
# Grisu3 is ported from the C++ "double-conversions" library.
#
# The following is their license:
#   Copyright 2012 the V8 project authors. All rights reserved.
#   Redistribution and use in source and binary forms, with or without
#   modification, are permitted provided that the following conditions are
#   met:
#
#       * Redistributions of source code must retain the above copyright
#         notice, this list of conditions and the following disclaimer.
#       * Redistributions in binary form must reproduce the above
#         copyright notice, this list of conditions and the following
#         disclaimer in the documentation and/or other materials provided
#         with the distribution.
#       * Neither the name of Google Inc. nor the names of its
#         contributors may be used to endorse or promote products derived
#         from this software without specific prior written permission.
#
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## src/float/printer/ieee.cr

```crystal
# IEEE is ported from the C++ "double-conversions" library.
#
# The following is their license:
#   Copyright 2012 the V8 project authors. All rights reserved.
#   Redistribution and use in source and binary forms, with or without
#   modification, are permitted provided that the following conditions are
#   met:
#
#       * Redistributions of source code must retain the above copyright
#         notice, this list of conditions and the following disclaimer.
#       * Redistributions in binary form must reproduce the above
#         copyright notice, this list of conditions and the following
#         disclaimer in the documentation and/or other materials provided
#         with the distribution.
#       * Neither the name of Google Inc. nor the names of its
#         contributors may be used to endorse or promote products derived
#         from this software without specific prior written permission.
#
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## src/float/printer/ryu_printf.cr

```crystal
# Source port of Ryu Printf's reference implementation in C.
#
# The following is their license:
#
#   Copyright 2018 Ulf Adams
#
#   The contents of this file may be used under the terms of the Apache License,
#   Version 2.0.
#
#      (See accompanying file LICENSE-Apache or copy at
#       http://www.apache.org/licenses/LICENSE-2.0)
#
#   Alternatively, the contents of this file may be used under the terms of
#   the Boost Software License, Version 1.0.
#      (See accompanying file LICENSE-Boost or copy at
#       https://www.boost.org/LICENSE_1_0.txt)
#
#   Unless required by applicable law or agreed to in writing, this software
#   is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#   KIND, either express or implied.
```

## src/openssl/ktls.cr

```crystal
# Ported from OpenSSL include/internal/ktls.h private header to enable KTLS
# through a custom BIO so the actual TCP communication goes through the normal
# Crystal::EventLoop regardless of the socket's blocking mode.
#
# Copyright 2018-2024 The OpenSSL Project Authors. All Rights Reserved.
#
# Licensed under the Apache License 2.0 (the "License").  You may not use
# this file except in compliance with the License.  You can obtain a copy
# in the file LICENSE in the source distribution or at
# https://www.openssl.org/source/license.html

# libressl doesn't support Kernel TLS
```

## src/openssl/ssl/hostname_validation.cr

```crystal
  # Matches a hostname against a wildcard pattern.
  #
  # The hostname must be an exact match or use a wildcard following
  # [RFC 6125, section 6.4.3](http://tools.ietf.org/html/rfc6125#section-6.4.3)
  # and [RFC 6125, section 7.2](http://tools.ietf.org/html/rfc6125#section-7.2)
  #
  # IDNA domains must be given in their punycode encoding, and no wildcard match
  # will be attempted if the left-most label is an IDNA label. For example
  # `*.xn--kcry6tjko.example.org` will match `foo.xn--kcry6tjko.example.org` but
  # `xn--*.example.org` won't match `xn--kcry6tjko.example.org`.
  #
  # No wildcard match is attempted for IP addresses. The hostname and patterns
  # are normalized to skip trailing dots (like browsers do).
  #
  # To be compatible with OpenSSL `X509_check_host` a leading dot will match any
  # subdomain. For example `.example.org` will match both `foo.example.com` and
  # `bar.foo.example.com`.
  #
  # Adapted from cURL:
  # Copyright (C) 1998 - 2014, Daniel Stenberg, <daniel@haxx.se>, et al.
  # https://github.com/curl/curl/blob/curl-7_41_0/lib/hostcheck.c
```

## src/random/pcg32.cr

```crystal
# This is a Crystal conversion of basic C PCG implementation
#
#  Original file notice:
#
#  PCG Random Number Generation for C.
#
#  Copyright 2014 Melissa O'Neill <oneill@pcg-random.org>
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
#  For additional information about the PCG random number generation scheme,
#  including its license and other licensing options, visit
#
#        http://www.pcg-random.org
#

# pcg32_random_r:
#       -  result:      32-bit unsigned int (uint32_t)
#       -  period:      2^64   (* 2^63 streams)
#       -  state type:  pcg32_random_t (16 bytes)
#       -  output func: XSH-RR
```

## src/slice/sort.cr

```crystal
  # The stable sort implementation is ported from Rust.
  # https://github.com/rust-lang/rust/blob/507bff92fadf1f25a830da5065a5a87113345163/library/alloc/src/slice.rs
  #
  # Rust License (MIT):
  #
  # Permission is hereby granted, free of charge, to any
  # person obtaining a copy of this software and associated
  # documentation files (the "Software"), to deal in the
  # Software without restriction, including without
  # limitation the rights to use, copy, modify, merge,
  # publish, distribute, sublicense, and/or sell copies of
  # the Software, and to permit persons to whom the Software
  # is furnished to do so, subject to the following
  # conditions:
  #
  # The above copyright notice and this permission notice
  # shall be included in all copies or substantial portions
  # of the Software.
  #
  # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF
  # ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
  # TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
  # PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT
  # SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
  # CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
  # OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
  # IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
  # DEALINGS IN THE SOFTWARE.

  # Slices of up to this length get sorted using insertion sort.
```

## src/sync/cv.cr

```crystal
# Crystal adaptation of "mu" from the "nsync" library with adaptations by
# Justine Alexandra Roberts Tunney in the "cosmopolitan" C library.
#
# Copyright 2016 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# References:
# - <https://github.com/google/nsync>
# - <https://github.com/jart/cosmopolitan/tree/master/third_party/nsync/>
```

## src/sync/mu.cr

```crystal
# Crystal adaptation of "mu" from the "nsync" library with adaptations by
# Justine Alexandra Roberts Tunney in the "cosmopolitan" C library.
#
# Copyright 2016 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# References:
# - <https://github.com/google/nsync>
# - <https://github.com/jart/cosmopolitan/tree/master/third_party/nsync/>
```
