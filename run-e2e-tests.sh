#!/bin/bash
set -euo pipefail

# 🧪 End-to-End Test Suite
# Comprehensive testing of the complete GitOps encrypted secrets workflow

# Parse command line arguments
TEST_MODE="full"
case "${1:-}" in
    "local"|"--local"|"-l")
        TEST_MODE="local"
        echo "🧪 Running Local Filter Tests for SOPS"
        echo "====================================="
        echo "Testing encryption/decryption filters without Git operations"
        ;;
    "full"|"--full"|"-f"|"")
        TEST_MODE="full"  
        echo "🧪 Running Full End-to-End Tests for SOPS GitOps Secrets"
        echo "========================================================"
        echo "Testing complete GitOps workflow including Git operations"
        ;;
    "help"|"--help"|"-h")
        echo "🧪 SOPS GitOps Test Suite"
        echo ""
        echo "Usage: $0 [MODE]"
        echo ""
        echo "Test Modes:"
        echo "  local, -l, --local    Test only encryption/decryption filters locally"
        echo "  full, -f, --full      Test complete GitOps workflow with Git operations (default)"
        echo "  help, -h, --help      Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 local              # Quick local testing"
        echo "  $0 full               # Complete workflow testing"
        echo "  $0                    # Same as 'full' (default)"
        exit 0
        ;;
    *)
        echo "❌ Unknown test mode: $1"
        echo "Use '$0 --help' for usage information"
        exit 1
        ;;
esac
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"  # Script is in repository root
TESTS_PASSED=0
TESTS_FAILED=0
CLEANUP_FILES=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_success() {
    echo -e "${GREEN}✅ $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test files..."
    for file in "${CLEANUP_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            echo "   Removed: $file"
        fi
    done
    
    # Reset any Git changes
    if git status --porcelain | grep -q .; then
        log_info "Resetting Git changes..."
        git reset --hard HEAD > /dev/null 2>&1
        git clean -fd > /dev/null 2>&1
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Change to repository root
cd "$REPO_ROOT"

echo "📍 Running tests from: $REPO_ROOT"
echo ""

# Test 1: Prerequisites Check
echo "🔍 Test 1: Prerequisites Check"
echo "==============================="

if ! command -v sops &> /dev/null; then
    log_error "SOPS not installed"
    exit 1
else
    log_success "SOPS installed"
fi

if ! command -v age &> /dev/null; then
    log_error "AGE not installed"
    exit 1
else
    log_success "AGE installed"
fi

# Check AGE key using same logic as Python scripts
AGE_KEY_PATH=""
if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]] && [[ -f "$SOPS_AGE_KEY_FILE" ]]; then
    AGE_KEY_PATH="$SOPS_AGE_KEY_FILE"
    log_success "AGE private key found via SOPS_AGE_KEY_FILE: $AGE_KEY_PATH"
elif [[ -f ".age/age.key" ]]; then
    AGE_KEY_PATH=".age/age.key"
    log_success "AGE private key found at repository-local path: $AGE_KEY_PATH"
elif [[ -f "$HOME/.age/age.key" ]]; then
    AGE_KEY_PATH="$HOME/.age/age.key"
    log_success "AGE private key found at home directory: $AGE_KEY_PATH"
else
    log_error "AGE private key not found. Checked: SOPS_AGE_KEY_FILE, .age/age.key, ~/.age/age.key"
    exit 1
fi

if [[ ! -f ".sops.yaml" ]]; then
    log_error ".sops.yaml not found - copy from .sops.yaml.template and configure"
    exit 1
else
    log_success ".sops.yaml configuration found"
fi

# Validate .sops.yaml content
if grep -q "creation_rules:" ".sops.yaml"; then
    log_success ".sops.yaml contains creation_rules"
else
    log_error ".sops.yaml missing creation_rules section"
fi

if grep -q "age:" ".sops.yaml"; then
    log_success ".sops.yaml contains AGE key configuration"
else
    log_error ".sops.yaml missing AGE key configuration"
fi

# Check if .sops.yaml contains a realistic AGE public key
if grep -q "age1[a-z0-9]\{58\}" ".sops.yaml"; then
    log_success ".sops.yaml contains valid-format AGE public key"
else
    log_error ".sops.yaml missing or invalid AGE public key format"
fi

echo ""

# Test 2: AGE Key Configuration Test
echo "🔑 Test 2: AGE Key Configuration"
echo "================================="

# Test environment variable precedence
if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
    log_success "SOPS_AGE_KEY_FILE environment variable is set: $SOPS_AGE_KEY_FILE"
    # Validate the path points to a valid file
    if [[ -f "$SOPS_AGE_KEY_FILE" ]]; then
        log_success "Environment variable points to valid AGE key file"
    else
        log_error "Environment variable points to non-existent file: $SOPS_AGE_KEY_FILE"
    fi
else
    log_info "SOPS_AGE_KEY_FILE not set, using default path detection"
fi

# Show which key path is being used
log_info "Using AGE key: $AGE_KEY_PATH"

# Test that the key works by trying to get its public key
if age-keygen -y "$AGE_KEY_PATH" > /dev/null 2>&1; then
    log_success "AGE private key is valid and readable"
else
    log_error "AGE private key is invalid or unreadable"
fi

# Test that Python scripts can use the same key (create temp test)
TEST_KEY_SECRET="examples/test-key-config-$$.yaml"
CLEANUP_FILES+=("$TEST_KEY_SECRET")

cat > "$TEST_KEY_SECRET" << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: test-key-config
  annotations:
    def.ms/sops-encrypt: "true"
stringData:
  test: "key-config-test"
EOF

# Test that clean filter can use the key
if ./sops-clean.py < "$TEST_KEY_SECRET" | grep -q "ENC\["; then
    log_success "Python clean filter can access AGE key"
else
    log_error "Python clean filter cannot access AGE key"
fi

# Test that smudge filter can use the key
TEMP_ENCRYPTED=$(./sops-clean.py < "$TEST_KEY_SECRET")
if echo "$TEMP_ENCRYPTED" | ./sops-smudge.py | grep -q "test: key-config-test"; then
    log_success "Python smudge filter can access AGE key"
else
    log_error "Python smudge filter cannot access AGE key"
fi

echo ""

# Test 3: Git Filter Configuration (Full mode only)
if [[ "$TEST_MODE" == "full" ]]; then
    echo "⚙️  Test 3: Git Filter Configuration"
    echo "===================================="

CLEAN_FILTER=$(git config filter.sops.clean 2>/dev/null || echo "")
SMUDGE_FILTER=$(git config filter.sops.smudge 2>/dev/null || echo "")

if [[ "$CLEAN_FILTER" == "./sops-clean.py" ]]; then
    log_success "Clean filter configured correctly"
else
    log_error "Clean filter not configured: got '$CLEAN_FILTER'"
fi

if [[ "$SMUDGE_FILTER" == "./sops-smudge.py" ]]; then
    log_success "Smudge filter configured correctly"
else
    log_error "Smudge filter not configured: got '$SMUDGE_FILTER'"
fi

if [[ -x "sops-clean.py" ]] && [[ -x "sops-smudge.py" ]]; then
    log_success "Filter scripts are executable"
else
    log_error "Filter scripts not executable"
fi

    echo ""
else
    log_info "Git Filter Configuration Test skipped in local mode"
fi

echo ""

# Test 4: Basic Secret Creation and Encryption
echo "🔐 Test 4: Basic Secret Creation and Encryption"
echo "==============================================="

# Use existing example file
TEST_SECRET="examples/basic-secret.yaml"

# Test clean filter (encryption)
ENCRYPTED_OUTPUT=$(./sops-clean.py < "$TEST_SECRET")

if echo "$ENCRYPTED_OUTPUT" | grep -q "kind: SopsSecret"; then
    log_success "Secret converted to SopsSecret"
else
    log_error "Secret not converted to SopsSecret"
fi

if echo "$ENCRYPTED_OUTPUT" | grep -q "ENC\[AES256_GCM"; then
    log_success "Secret data encrypted"
else
    log_error "Secret data not encrypted"
fi

if echo "$ENCRYPTED_OUTPUT" | grep -q "name: basic-secret"; then
    log_success "Template name preserved unencrypted"
else
    log_error "Template name not preserved or encrypted"
fi

echo ""

# Test 5: Secret Decryption (Smudge Filter)
echo "🔓 Test 5: Secret Decryption (Smudge Filter)"
echo "============================================"

# Test smudge filter (decryption)
DECRYPTED_OUTPUT=$(echo "$ENCRYPTED_OUTPUT" | ./sops-smudge.py)

if echo "$DECRYPTED_OUTPUT" | grep -q "kind: Secret"; then
    log_success "SopsSecret converted back to Secret"
else
    log_error "SopsSecret not converted back to Secret"
fi

if echo "$DECRYPTED_OUTPUT" | grep -q "password: supersecretpassword123"; then
    log_success "Secret data decrypted correctly"
else
    log_error "Secret data not decrypted correctly"
fi

echo ""

# Test 6: Annotation-Based Filtering
echo "🎯 Test 6: Annotation-Based Filtering"
echo "====================================="

# Use existing unencrypted example
TEST_UNENCRYPTED="examples/unencrypted-secret.yaml"

# Test that secret without annotation is not processed
UNPROCESSED_OUTPUT=$(./sops-clean.py < "$TEST_UNENCRYPTED")

if echo "$UNPROCESSED_OUTPUT" | grep -q "kind: Secret"; then
    log_success "Secret without annotation remains as Secret"
else
    log_error "Secret without annotation was incorrectly processed"
fi

if echo "$UNPROCESSED_OUTPUT" | grep -q "public-config: This data is not sensitive"; then
    log_success "Unencrypted secret data preserved"
else
    log_error "Unencrypted secret data modified"
fi

echo ""

# Test 7: Mixed Data and StringData Fields
echo "📊 Test 7: Mixed Data and StringData Fields"
echo "==========================================="

# Use existing mixed fields example
TEST_MIXED="examples/mixed-fields.yaml"

MIXED_ENCRYPTED=$(./sops-clean.py < "$TEST_MIXED")
MIXED_DECRYPTED=$(echo "$MIXED_ENCRYPTED" | ./sops-smudge.py)

if echo "$MIXED_ENCRYPTED" | grep -q "data:" && echo "$MIXED_ENCRYPTED" | grep -q "stringData:"; then
    log_success "Both data and stringData fields preserved in encrypted format"
else
    log_error "Mixed field types not preserved correctly"
fi

if echo "$MIXED_DECRYPTED" | grep -q "data:" && echo "$MIXED_DECRYPTED" | grep -q "stringData:"; then
    log_success "Mixed field types preserved after decryption"
else
    log_error "Mixed field types not preserved after decryption"
fi

echo ""

# Test 8: Different Secret Types
echo "🏷️  Test 8: Different Secret Types"
echo "=================================="

# Use existing docker config example
TEST_DOCKER="examples/docker-config.yaml"

DOCKER_ENCRYPTED=$(./sops-clean.py < "$TEST_DOCKER")
DOCKER_DECRYPTED=$(echo "$DOCKER_ENCRYPTED" | ./sops-smudge.py)

if echo "$DOCKER_DECRYPTED" | grep -q "type: kubernetes.io/dockerconfigjson"; then
    log_success "Docker config secret type preserved"
else
    log_error "Docker config secret type not preserved"
fi

echo ""

# Test 9: Git Integration Test (Full mode only)
if [[ "$TEST_MODE" == "full" ]]; then
    echo "📝 Test 9: Git Integration Test"
    echo "==============================="

TEST_GIT_SECRET="examples/test-git-integration-$$.yaml"
CLEANUP_FILES+=("$TEST_GIT_SECRET")

cat > "$TEST_GIT_SECRET" << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: test-git-integration
  namespace: default
  annotations:
    def.ms/sops-encrypt: "true"
type: Opaque
stringData:
  test-value: "git-integration-test"
EOF

# Add to Git and check what's stored (this tests .gitattributes integration)
git add "$TEST_GIT_SECRET"
STORED_CONTENT=$(git show ":$TEST_GIT_SECRET")

if echo "$STORED_CONTENT" | grep -q "kind: SopsSecret"; then
    log_success "Git stores encrypted SopsSecret"
else
    log_error "Git not storing encrypted format"
fi

if echo "$STORED_CONTENT" | grep -q "ENC\["; then
    log_success "Secret data encrypted in Git"
else
    log_error "Secret data not encrypted in Git"
fi

# Check working directory shows decrypted version
if grep -q "test-value: \"git-integration-test\"" "$TEST_GIT_SECRET"; then
    log_success "Working directory shows decrypted Secret"
else
    log_error "Working directory not showing decrypted Secret"
fi

    echo ""
else
    log_info "Git Integration Test skipped in local mode"
fi

echo ""

# Test 10: Multi-line YAML Content
echo "📄 Test 10: Multi-line YAML Content"
echo "==================================="

TEST_MULTILINE="examples/test-multiline-$$.yaml"
CLEANUP_FILES+=("$TEST_MULTILINE")

cat > "$TEST_MULTILINE" << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: test-multiline
  namespace: default
  annotations:
    def.ms/sops-encrypt: "true"
type: Opaque
stringData:
  config.yaml: |
    server:
      host: "api.example.com"
      port: 8443
      ssl: true
    features:
      analytics: true
      debug: false
EOF

MULTILINE_ENCRYPTED=$(./sops-clean.py < "$TEST_MULTILINE")
MULTILINE_DECRYPTED=$(echo "$MULTILINE_ENCRYPTED" | ./sops-smudge.py)

if echo "$MULTILINE_DECRYPTED" | grep -q "server:" && echo "$MULTILINE_DECRYPTED" | grep -q "analytics: true"; then
    log_success "Multi-line YAML content preserved"
else
    log_error "Multi-line YAML content corrupted"
fi

echo ""

# Test 11: Error Handling
echo "⚠️  Test 11: Error Handling"
echo "==========================="

# Test with invalid YAML
INVALID_OUTPUT=$(echo "invalid: yaml: content: [" | ./sops-clean.py)
if echo "$INVALID_OUTPUT" | grep -q "invalid: yaml: content: \["; then
    log_success "Invalid YAML passed through unchanged"
else
    log_error "Invalid YAML not handled correctly"
fi

# Test with non-Secret YAML
NON_SECRET_OUTPUT=$(echo -e "apiVersion: v1\nkind: ConfigMap\ndata:\n  key: value" | ./sops-clean.py)
if echo "$NON_SECRET_OUTPUT" | grep -q "kind: ConfigMap"; then
    log_success "Non-Secret YAML passed through unchanged"
else
    log_error "Non-Secret YAML not handled correctly"
fi

echo ""

# Final Results
echo "🏁 Test Results Summary"
echo "======================="
echo ""

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}🎉 All $TESTS_PASSED tests passed!${NC}"
    echo ""
    if [[ "$TEST_MODE" == "local" ]]; then
        echo "✅ Your SOPS filter scripts are working correctly!"
        echo ""
        echo "Next steps:"
        echo "1. Run '$0 full' to test the complete GitOps workflow with Git"
        echo "2. Copy and modify files in examples/ directory for your secrets"  
        echo "3. Add the 'def.ms/sops-encrypt: \"true\"' annotation to encrypt them"
    else
        echo "✅ Your SOPS GitOps setup is working correctly!"
        echo ""
        echo "Next steps:"
        echo "1. Copy and modify files in examples/ directory for your secrets"
        echo "2. Add the 'def.ms/sops-encrypt: \"true\"' annotation to encrypt them"
        echo "3. Deploy to Kubernetes with your GitOps tool (ArgoCD, Flux, etc.)"
    fi
    echo ""
else
    echo -e "${RED}❌ $TESTS_FAILED out of $TOTAL_TESTS tests failed!${NC}"
    echo ""
    echo "Please fix the issues above before using the system."
    echo "Check the setup guide: docs/advanced-setup.md"
    echo "For troubleshooting: docs/troubleshooting.md"
    echo ""
    exit 1
fi

echo "=================================================="