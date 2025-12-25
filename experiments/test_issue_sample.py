#!/usr/bin/env python3
"""
Test the exact sample from the issue comment.
"""

import sys
sys.path.insert(0, '/tmp/gh-issue-solver-1766688687154/api')

from app import strip_ansi_codes
import json

# This is exactly what was provided in the issue comment (the "result" field content)
issue_sample = r"""Starting installation of 'pocketbase' on 109.199.116.127...
Connecting to 109.199.116.127:22 via SSH...
Executing script: pocketbase

\^[[0;36m╔══════════════════════════════════════════════════════════════════════════════╗\^[[0m
\^[[0;36m║\^[[0m  \^[[1m\^[[1;37mDomain Configuration\^[[0m
\^[[0;36m╚══════════════════════════════════════════════════════════════════════════════╝\^[[0m

\^[[0;32m✔\^[[0m \^[[0;32mDomain configured: installer.api2app.org\^[[0m
\^[[H\^[[J\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@\^@
\^[[0;36m   ╔═══════════════════════════════════════════════════════════════════════════╗\^[[0m
\^[[0;36m   ║\^[[0m                                                                           \^[[0;36m║\^[[0m
\^[[0;36m   ║\^[[0m   \^[[1m\^[[1;37mPocketBase\^[[0m                                                              \^[[0;36m║\^[[0m
\^[[0;36m   ║\^[[0m   \^[[0;35mAutomated Installation Script for Ubuntu 24.04\^[[0m                         \^[[0;36m║\^[[0m
\^[[0;36m   ║\^[[0m                                                                           \^[[0;36m║\^[[0m
\^[[0;36m   ║\^[[0m   \^[[1;37mThis script will install and configure:\^[[0m                                \^[[0;36m║\^[[0m
\^[[0;36m   ║\^[[0m   \^[[0;32m•\^[[0m PocketBase backend server                                             \^[[0;36m║\^[[0m
\^[[0;36m   ║\^[[0m   \^[[0;32m•\^[[0m Nginx as reverse proxy                                                \^[[0;36m║\^[[0m
\^[[0;36m   ║\^[[0m   \^[[0;32m•\^[[0m Systemd services for auto-start                                       \^[[0;36m║\^[[0m
\^[[0;36m   ║\^[[0m   \^[[0;32m•\^[[0m SSL certificate via Let's Encrypt                                     \^[[0;36m║\^[[0m
\^[[0;36m   ║\^[[0m                                                                           \^[[0;36m║\^[[0m
\^[[0;36m   ╚═══════════════════════════════════════════════════════════════════════════╝\^[[0m


\^[[0;36m╔══════════════════════════════════════════════════════════════════════════════╗\^[[0m
\^[[0;36m║\^[[0m  \^[[1m\^[[1;37mSetting Up Installer User\^[[0m
\^[[0;36m╚══════════════════════════════════════════════════════════════════════════════╝\^[[0m

\^[[0;35mℹ\^[[0m \^[[1;37mUser 'installer_user' already exists\^[[0m
\^[[0;34m➜\^[[0m \^[[1;37mAdding 'installer_user' to sudo group...\^[[0m
\^[[0;32m✔\^[[0m \^[[0;32mUser added to sudo group\^[[0m
\^[[0;32m✔\^[[0m \^[[0;32mInstaller user configured: installer_user\^[[0m
\^[[0;35mℹ\^[[0m \^[[1;37mHome directory: /home/installer_user\^[[0m
\^[[0;35mℹ\^[[0m \^[[1;37mInstallation directory: /home/installer_user/pocketbase\^[[0m

\^[[0;35mℹ\^[[0m \^[[1;37mStarting installation. This may take several minutes...\^[[0m
\^[[0;35mℹ\^[[0m \^[[1;37mDomain: installer.api2app.org\^[[0m
\^[[0;35mℹ\^[[0m \^[[1;37mUser: installer_user\^[[0m


\^[[0;36m╔══════════════════════════════════════════════════════════════════════════════╗\^[[0m
\^[[0;36m║\^[[0m  \^[[1m\^[[1;37mInstalling System Dependencies\^[[0m
\^[[0;36m╚══════════════════════════════════════════════════════════════════════════════╝\^[[0m

\^[[0;34m➜\^[[0m \^[[1;37mUpdating package lists...\^[[0m
"""

print("=" * 80)
print("TESTING EXACT SAMPLE FROM ISSUE")
print("=" * 80)

result = strip_ansi_codes(issue_sample)

print("\nOriginal length:", len(issue_sample))
print("Cleaned length:", len(result))
print()
print("CLEANED OUTPUT:")
print("-" * 80)
print(result)
print("-" * 80)

# Check if any unwanted patterns remain
unwanted_patterns = [
    r'\\?\^\[',  # Caret escape sequences
    r'\\?\^@',   # Caret NULL
    r'\[0;3[0-9]m',  # Color codes like [0;36m
    r'\[1;3[0-9]m',  # Bold color codes like [1;37m
    r'\[0m',     # Reset code
    r'\[1m',     # Bold code
]

import re
print("\nCHECKING FOR REMAINING UNWANTED PATTERNS:")
all_clean = True
for pattern in unwanted_patterns:
    matches = re.findall(pattern, result)
    if matches:
        print(f"  FOUND: {pattern} -> {matches[:5]}...")
        all_clean = False
    else:
        print(f"  OK: {pattern} - not found")

print()
if all_clean:
    print("✓ SUCCESS: All unwanted patterns have been removed!")
else:
    print("✗ FAIL: Some unwanted patterns remain in output")
