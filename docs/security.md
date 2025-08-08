# 🔒 Security Best Practices

Security considerations and best practices for SOPS GitOps encrypted secrets.

## 🚨 Critical Security Warnings

### Never Commit These Files
- `.age/age.key` (Private AGE key)
- `.env` files with secrets
- Unencrypted backup copies
- Debug output containing decrypted secrets

## Key Management

### AGE Key Security

**Private Key Protection:**
```bash
# Set restrictive permissions on private key
chmod 600 .age/age.key
```

**Key Rotation Strategy:**
```bash
# Rotate keys regularly (recommended: every 90 days)
# 1. Generate new key pair
age-keygen -o .age/age-new.key

# 2. Update .sops.yaml with new public key
# 3. Re-encrypt all secrets
find . -name "*.yaml" -exec sops updatekeys {} \;

# 4. Test decryption works
./run-e2e-tests.sh

# 5. Replace old key
mv .age/age-new.key .age/age.key
```

**Backup and Recovery:**
```bash
# Create encrypted backup of private key
age -p .age/age.key > age-key-backup.age

# Store backup securely (separate from main system)
# Test recovery process regularly
```

### Multi-Key Setup (Team/Production)

For production environments with multiple team members:

```yaml
# .sops.yaml - Multiple recipients
creation_rules:
  - path_regex: '.*\.ya?ml$'
    age: >-
      age1apsxs6l3u4f6z4ejpcf97kd3st234hl6k9zle5y52fmsrv098q9skpemtf,
      age1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9,
      age1xyz789abc123def456ghi789jkl012mno345pqr678stu901vwx234yz5
    encrypted_regex: '^(data|stringData)$'
```

You can update `.sops.yaml` according to preferences for more granular access.

**Benefits:**
- Any team member can decrypt
- No single point of failure
- Individual key rotation possible

**Setup Process:**
```bash
# Each team member generates their own key
age-keygen -o .age/team-member-1.key

# Collect public keys and update .sops.yaml
# Re-encrypt existing secrets for all keys
sops updatekeys *.yaml
```

## Access Control

### Git Repository Security

**Branch Protection:**
```yaml
# GitHub branch protection rules
branches:
  main:
    required_reviews: 2
    require_code_owner_reviews: true
    dismiss_stale_reviews: true
    require_status_checks: true
    required_status_checks:
      - "security-scan"
      - "secret-validation"
```

**CODEOWNERS Example:**
```bash
# .github/CODEOWNERS
secrets/production/    @security-team @platform-team
secrets/staging/       @platform-team
.sops.yaml            @security-team
sops-*.py             @security-team
```

### Kubernetes RBAC

**SOPS Secrets Operator Permissions:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: sops-secrets-operator
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: ["isindir.github.com"]
  resources: ["sopssecrets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: sops-secrets-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: sops-secrets-operator
subjects:
- kind: ServiceAccount
  name: sops-secrets-operator
  namespace: sops-secrets-operator-system
```

**Application Access (Least Privilege):**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: app-namespace
  name: app-secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["app-database-secret", "app-api-secret"]
  verbs: ["get"]
```

## Operational Security

### CI/CD Security

**Secret Scanning:**
```bash
# Simple pre-commit hook to prevent unencrypted secrets
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Check for unencrypted secrets
if git diff --cached | grep -E "(password|secret|key):" | grep -v "ENC\["; then
    echo "⚠️  Potential unencrypted secrets detected!"
    echo "Add 'def.ms/sops-encrypt: true' annotation to encrypt"
    exit 1
fi
EOF
chmod +x .git/hooks/pre-commit
```

### Monitoring and Auditing

**Log Secret Access:**
```bash
# Monitor SOPS operations
export SOPS_LOGGING=1

# Track Git operations on secrets
git log --follow --patch *.yaml
```

**Kubernetes Secret Monitoring:**
```yaml
# Example: Monitor secret access in Kubernetes
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  omitStages:
  - RequestReceived
  resources:
  - group: ""
    resources: ["secrets"]
  namespaces: ["production", "staging"]
```

### Incident Response

**Compromised AGE Key:**
1. **Immediately rotate all AGE keys**
2. **Re-encrypt all secrets with new keys**
3. **Update all deployment environments**
4. **Review and rotate application secrets**

## Compliance and Governance

### Secret Lifecycle Management

Add governance metadata to track secrets:
```yaml
metadata:
  annotations:
    def.ms/sops-encrypt: "true"
    owner: "platform-team@company.com"
    last-rotated: "2024-08-08"
    rotation-schedule: "monthly"
    purpose: "Database credentials"
```

### Audit Trail

**Git History Protection:**
```bash
# Prevent history rewriting on protected branches
git config receive.denyNonFastForwards true
git config receive.denyDeletes true

# Sign commits for authenticity
git config commit.gpgsign true
```

**Change Tracking:**
```bash
# Track who changed what secrets when
git log --pretty=format:"%h %an %ad %s" --date=short -- *.yaml

# Generate compliance reports
git log --since="2024-01-01" --until="2024-12-31" \
  --pretty=format:"%h,%an,%ad,%s" --date=iso -- *.yaml > secrets-audit.csv
```

## Security Checklist

### Initial Setup
- [ ] Generate AGE key: `age-keygen -o .age/age.key`
- [ ] Set key permissions: `chmod 600 .age/age.key`
- [ ] Configure .sops.yaml with public key
- [ ] Test with: `./run-e2e-tests.sh local`

### Ongoing Operations
- [ ] Rotate AGE keys every 90 days
- [ ] Monitor for unencrypted secrets
- [ ] Review Git access logs
- [ ] Backup and test key recovery

### Production Deployment
- [ ] Set up multi-key encryption for team
- [ ] Configure branch protection
- [ ] Set up SOPS operator RBAC
- [ ] Implement secret scanning in CI/CD
- [ ] Document incident response
