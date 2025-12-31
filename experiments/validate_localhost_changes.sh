#!/bin/bash

#===============================================================================
# Validation script to check localhost handling changes
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
echo "Validating localhost handling changes in mysql-phpmyadmin.sh"
echo "========================================================================"

# Test validate_domain allows localhost
run_test "validate_domain allows 'localhost'" \
    'if \[\[ "\$domain" == "localhost" \]\]; then'

# Test usage mentions localhost
run_test "Usage text mentions localhost for local development" \
    "Use 'localhost' for local development (no SSL, no Basic Auth)"

# Test usage has localhost example
run_test "Usage has localhost example" \
    'localhost.*# Local access at http://localhost/phpmyadmin'

# Test configure_nginx has localhost check
run_test "configure_nginx checks for localhost" \
    'if \[\[ "\$DOMAIN_NAME" == "localhost" \]\]; then'

# Test nginx config uses /phpmyadmin location
run_test "Nginx config has /phpmyadmin location for localhost" \
    'location /phpmyadmin'

# Test nginx config uses alias for localhost
run_test "Nginx config uses alias for localhost" \
    'alias /usr/share/phpmyadmin'

# Test Basic Auth is disabled for localhost in nginx
run_test "Basic Auth is conditional (disabled for localhost)" \
    'if \[\[ "\$DOMAIN_NAME" != "localhost" \]\]; then'

# Test SSL setup skips localhost
run_test "SSL setup skips localhost" \
    'Skip SSL setup for localhost'

# Test create_htpasswd skips localhost
run_test "create_htpasswd skips localhost" \
    'Skip basic auth for localhost' # Changed from "Skipping Basic Authentication"

# Test completion message shows http://localhost/phpmyadmin
run_test "Completion message shows http://localhost/phpmyadmin" \
    'http://localhost/phpmyadmin'

# Test parse_arguments shows localhost mode info
run_test "parse_arguments shows localhost mode info" \
    'Basic Authentication: disabled (localhost mode)'

# Test parse_arguments mentions SSL disabled for localhost
run_test "parse_arguments mentions SSL disabled for localhost" \
    'SSL Certificate: disabled (localhost mode)'

echo ""
echo "========================================================================"
echo "Test Summary"
echo "========================================================================"
echo -e "Total tests: $test_count"
echo -e "${GREEN}Passed: $pass_count${NC}"
if [ $fail_count -gt 0 ]; then
    echo -e "${RED}Failed: $fail_count${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
