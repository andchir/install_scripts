#!/bin/bash

#===============================================================================
# Regression test - Verify non-localhost domains still work as expected
#===============================================================================

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_PATH="../scripts/mysql-phpmyadmin.sh"

test_count=0
pass_count=0
fail_count=0

# Function to run a test
run_test() {
    local test_name="$1"
    local pattern="$2"

    test_count=$((test_count + 1))
    echo -e "\n${YELLOW}Test $test_count: $test_name${NC}"

    if grep -q "$pattern" "$SCRIPT_PATH"; then
        echo -e "${GREEN}✓ PASS${NC}"
        pass_count=$((pass_count + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL - Pattern not found: $pattern${NC}"
        fail_count=$((fail_count + 1))
        return 1
    fi
}

echo "========================================================================"
echo "Regression Testing - Non-localhost domain functionality"
echo "========================================================================"

# Test that domain validation still validates regular domains
run_test "Domain validation regex still exists for regular domains" \
    'if \[\[ ! "\$domain" =~ \^'

# Test that SSL setup still works for non-localhost
run_test "SSL setup still runs certbot for non-localhost" \
    'certbot --nginx -d "\$DOMAIN_NAME"'

# Test that Basic Auth is still created for non-localhost
run_test "Basic Auth htpasswd is still created for non-localhost" \
    'htpasswd -bc "\$HTPASSWD_FILE"'

# Test that regular nginx config (with root directive) is still present
run_test "Regular nginx config with 'root' directive exists" \
    'root /usr/share/phpmyadmin'

# Test that Basic Auth directives are still added for non-localhost
run_test "Basic Auth directives are still configured" \
    'auth_basic'

# Test that completion message still shows https for non-localhost
run_test "Completion message shows https:// for non-localhost" \
    'https://\$DOMAIN_NAME'

# Test that security settings are shown for non-localhost
run_test "Security settings section exists for non-localhost" \
    'if \[\[ "\$DOMAIN_NAME" != "localhost" \]\]; then'

# Test that Basic Auth credentials are saved for non-localhost
run_test "Basic Auth credentials file is still created" \
    '.phpmyadmin-auth'

# Test that parse_arguments still shows Basic Auth enabled for non-localhost
run_test "parse_arguments shows Basic Auth enabled (mandatory)" \
    'Basic Authentication: enabled (mandatory)'

echo ""
echo "========================================================================"
echo "Regression Test Summary"
echo "========================================================================"
echo -e "Total tests: $test_count"
echo -e "${GREEN}Passed: $pass_count${NC}"
if [ $fail_count -gt 0 ]; then
    echo -e "${RED}Failed: $fail_count${NC}"
    echo -e "${RED}REGRESSION DETECTED - Some non-localhost functionality may be broken!${NC}"
    exit 1
else
    echo -e "${GREEN}All regression tests passed!${NC}"
    echo -e "${GREEN}Non-localhost domain functionality is intact.${NC}"
    exit 0
fi
