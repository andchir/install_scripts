#!/usr/bin/env python3
"""
Test script for analyzing and testing ANSI escape code stripping.

This script helps understand the exact format of ANSI codes in the input data
and tests the strip_ansi_codes function.
"""

import re
import sys
sys.path.insert(0, '/tmp/gh-issue-solver-1766688687154/api')

from app import strip_ansi_codes

# Test data from the issue comment
# The issue shows escape sequences like "\^[[0;36m" which is caret notation
# for the actual ANSI escape sequence "\x1b[0;36m"

# First, let's test with actual ANSI escape sequences
test_text_actual_ansi = """Starting installation of 'pocketbase' on 109.199.116.127...
Connecting to 109.199.116.127:22 via SSH...
Executing script: pocketbase

\x1b[0;36m╔══════════════════════════════════════════════════════════════════════════════╗\x1b[0m
\x1b[0;36m║\x1b[0m  \x1b[1m\x1b[1;37mDomain Configuration\x1b[0m
\x1b[0;36m╚══════════════════════════════════════════════════════════════════════════════╝\x1b[0m

\x1b[0;32m✔\x1b[0m \x1b[0;32mDomain configured: installer.api2app.org\x1b[0m
\x1b[H\x1b[J\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
"""

print("=" * 80)
print("TEST 1: Actual ANSI escape sequences (\\x1b[...)")
print("=" * 80)
print("Original text (repr):")
print(repr(test_text_actual_ansi[:200]))
print()
print("After strip_ansi_codes:")
result1 = strip_ansi_codes(test_text_actual_ansi)
print(repr(result1[:200]))
print()
print("Clean output:")
print(result1)

# Now test with caret notation as shown in the issue
# ^[ is often used to represent ESC character in caret notation
test_text_caret_notation = r"""Starting installation of 'pocketbase' on 109.199.116.127...
Connecting to 109.199.116.127:22 via SSH...
Executing script: pocketbase

^[[0;36m╔══════════════════════════════════════════════════════════════════════════════╗^[[0m
^[[0;36m║^[[0m  ^[[1m^[[1;37mDomain Configuration^[[0m
^[[0;36m╚══════════════════════════════════════════════════════════════════════════════╝^[[0m

^[[0;32m✔^[[0m ^[[0;32mDomain configured: installer.api2app.org^[[0m
^[[H^[[J^@^@^@^@^@^@^@^@^@^@^@^@^@^@^@^@
"""

print()
print("=" * 80)
print("TEST 2: Caret notation (^[[...)")
print("=" * 80)
print("Original text (repr):")
print(repr(test_text_caret_notation[:200]))
print()
print("After strip_ansi_codes:")
result2 = strip_ansi_codes(test_text_caret_notation)
print(repr(result2[:200]))
print()
print("Clean output:")
print(result2)

# Test with \^[ notation as shown in JSON output from issue
test_text_json_escaped = r"""Starting installation of 'pocketbase' on 109.199.116.127...
Connecting to 109.199.116.127:22 via SSH...
Executing script: pocketbase

\^[[0;36m╔══════════════════════════════════════════════════════════════════════════════╗\^[[0m
\^[[0;36m║\^[[0m  \^[[1m\^[[1;37mDomain Configuration\^[[0m
\^[[0;36m╚══════════════════════════════════════════════════════════════════════════════╝\^[[0m

\^[[0;32m✔\^[[0m \^[[0;32mDomain configured: installer.api2app.org\^[[0m
\^[[H\^[[J\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@
"""

print()
print("=" * 80)
print("TEST 3: Backslash-caret notation (\\^[[...)")
print("=" * 80)
print("Original text (repr):")
print(repr(test_text_json_escaped[:200]))
print()
print("After strip_ansi_codes:")
result3 = strip_ansi_codes(test_text_json_escaped)
print(repr(result3[:200]))
print()
print("Clean output:")
print(result3)

# Additional test: Check what characters we're dealing with
print()
print("=" * 80)
print("Character Analysis")
print("=" * 80)
print(f"ESC character: {repr(chr(27))} = \\x1b")
print(f"^ character: {repr('^')} = \\x5e")
print(f"[ character: {repr('[')} = \\x5b")

# Let's also check CSI detection with different inputs
test_csi_variations = [
    '\x1b[0;36m',      # Standard ESC [ sequence
    '^[[0;36m',        # Caret notation
    '\\^[[0;36m',      # JSON-escaped caret notation
    '\033[0;36m',      # Octal notation
]

print()
print("=" * 80)
print("CSI Sequence Variations")
print("=" * 80)
for seq in test_csi_variations:
    cleaned = strip_ansi_codes(seq)
    print(f"Input: {repr(seq):30} -> Output: {repr(cleaned)}")
