#!/usr/bin/env python3
"""
Unit tests for strip_ansi_codes function.

These tests verify that the function correctly removes:
1. Actual ANSI escape sequences (\x1b[...m)
2. Caret notation for escape sequences (^[[...m)
3. JSON-escaped caret notation (\^[[...m)
4. Control characters and their caret notation (^@, ^A, etc.)
"""

import sys
import unittest

sys.path.insert(0, '/tmp/gh-issue-solver-1766688687154/api')

from app import strip_ansi_codes


class TestStripAnsiCodes(unittest.TestCase):
    """Tests for the strip_ansi_codes function."""

    def test_none_input(self):
        """Test that None input returns None."""
        self.assertIsNone(strip_ansi_codes(None))

    def test_empty_string(self):
        """Test that empty string returns empty string."""
        self.assertEqual(strip_ansi_codes(''), '')

    def test_plain_text(self):
        """Test that plain text is unchanged."""
        text = "Hello, World!"
        self.assertEqual(strip_ansi_codes(text), text)

    def test_actual_ansi_escape_codes(self):
        """Test stripping of actual ANSI escape sequences."""
        # Color codes
        self.assertEqual(strip_ansi_codes('\x1b[0;36mHello\x1b[0m'), 'Hello')
        self.assertEqual(strip_ansi_codes('\x1b[1;37mBold\x1b[0m'), 'Bold')
        
        # Cursor movement
        self.assertEqual(strip_ansi_codes('\x1b[HHome\x1b[J'), 'Home')
        
        # Multiple codes
        self.assertEqual(
            strip_ansi_codes('\x1b[0;32m✔\x1b[0m Done'),
            '✔ Done'
        )

    def test_caret_notation_escape_codes(self):
        """Test stripping of caret notation escape sequences."""
        # Color codes in caret notation
        self.assertEqual(strip_ansi_codes('^[[0;36mHello^[[0m'), 'Hello')
        self.assertEqual(strip_ansi_codes('^[[1;37mBold^[[0m'), 'Bold')
        
        # Cursor movement in caret notation
        self.assertEqual(strip_ansi_codes('^[[HHome^[[J'), 'Home')

    def test_backslash_caret_notation(self):
        """Test stripping of backslash-caret notation (from JSON output)."""
        # This is how the escape sequences appear in JSON output
        self.assertEqual(strip_ansi_codes(r'\^[[0;36mHello\^[[0m'), 'Hello')
        self.assertEqual(strip_ansi_codes(r'\^[[1;37mBold\^[[0m'), 'Bold')

    def test_null_characters(self):
        """Test stripping of NULL characters."""
        # Actual NULL bytes
        self.assertEqual(strip_ansi_codes('Hello\x00World'), 'HelloWorld')
        
        # Caret notation for NULL
        self.assertEqual(strip_ansi_codes('Hello^@World'), 'HelloWorld')
        
        # Backslash-caret notation for NULL
        self.assertEqual(strip_ansi_codes(r'Hello\^@World'), 'HelloWorld')

    def test_control_characters(self):
        """Test stripping of control characters."""
        # Various control characters
        self.assertEqual(strip_ansi_codes('a\x01b\x02c'), 'abc')
        
        # Caret notation for control chars
        self.assertEqual(strip_ansi_codes('a^Ab^Bc'), 'abc')

    def test_preserve_whitespace(self):
        """Test that tab, newline, and carriage return are preserved."""
        text = "Line1\nLine2\tTabbed\rCarriage"
        self.assertEqual(strip_ansi_codes(text), text)

    def test_unicode_preserved(self):
        """Test that unicode characters are preserved."""
        text = "╔══════╗\n║ ✔ ℹ ➜ •║\n╚══════╝"
        self.assertEqual(strip_ansi_codes(text), text)

    def test_mixed_content(self):
        """Test with mixed ANSI codes and regular content."""
        input_text = '\x1b[0;36m╔════╗\x1b[0m\n\x1b[0;32m✔\x1b[0m Done'
        expected = '╔════╗\n✔ Done'
        self.assertEqual(strip_ansi_codes(input_text), expected)

    def test_issue_sample(self):
        """Test with content similar to the issue sample."""
        input_text = r"""\^[[0;36m╔══════════════════╗\^[[0m
\^[[0;36m║\^[[0m  \^[[1;37mDomain Config\^[[0m
\^[[0;32m✔\^[[0m \^[[0;32mDone\^[[0m
\^[[H\^[[J\^@\^@\^@\^@"""
        
        expected = """╔══════════════════╗
║  Domain Config
✔ Done
"""
        
        self.assertEqual(strip_ansi_codes(input_text), expected)


if __name__ == '__main__':
    unittest.main(verbosity=2)
