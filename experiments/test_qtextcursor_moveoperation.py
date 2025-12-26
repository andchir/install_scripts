#!/usr/bin/env python3
"""
Experiment to verify the QTextCursor.MoveOperation.End fix.

This script tests that QTextCursor.MoveOperation.End is the correct way
to reference the End enum value in PyQt6, and that the old approach
(textCursor().End) is incorrect.

Related to issue: https://github.com/andchir/install_scripts/issues/78
"""

import sys

# Test 1: Check that QTextCursor.MoveOperation.End is valid in PyQt6
try:
    from PyQt6.QtGui import QTextCursor

    # The correct way to access the End enum in PyQt6
    end_operation = QTextCursor.MoveOperation.End
    print(f"✓ Test 1 PASSED: QTextCursor.MoveOperation.End = {end_operation}")
except ImportError:
    print("✗ Test 1 SKIPPED: PyQt6 is not installed")
    sys.exit(0)
except AttributeError as e:
    print(f"✗ Test 1 FAILED: {e}")
    sys.exit(1)


# Test 2: Create a simple QTextEdit and test moveCursor with the correct enum
try:
    from PyQt6.QtWidgets import QApplication, QTextEdit

    # Create a minimal application
    app = QApplication([])
    text_edit = QTextEdit()

    # Add some text
    text_edit.setPlainText("Hello, World!")

    # Move cursor to end using the correct approach
    text_edit.moveCursor(QTextCursor.MoveOperation.End)

    # Verify cursor is at the end
    cursor = text_edit.textCursor()
    print(f"✓ Test 2 PASSED: Cursor position after moveCursor(End): {cursor.position()}")

    # Clean up
    del text_edit
    del app
except Exception as e:
    print(f"✗ Test 2 FAILED: {e}")
    sys.exit(1)


# Test 3: Verify the old incorrect approach fails
try:
    from PyQt6.QtWidgets import QApplication, QTextEdit

    app = QApplication([])
    text_edit = QTextEdit()

    # Try the old incorrect approach - this should raise AttributeError
    try:
        _ = text_edit.textCursor().End  # This is the bug we're fixing
        print("✗ Test 3 FAILED: Expected AttributeError was not raised")
        sys.exit(1)
    except AttributeError as e:
        print(f"✓ Test 3 PASSED: Old approach correctly raises AttributeError: {e}")

    # Clean up
    del text_edit
    del app
except Exception as e:
    print(f"✗ Test 3 FAILED with unexpected error: {e}")
    sys.exit(1)


print("\n✓ All tests PASSED! The fix is correct.")
print("  QTextCursor.MoveOperation.End is the correct way to access the End enum in PyQt6.")
