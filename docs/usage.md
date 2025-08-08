# 📚 Usage Guide

Learn how to create and manage encrypted secrets with this SOPS GitOps setup.

## Creating Your First Encrypted Secret

### 1. Basic Secret

Copy and customize from the provided example:

```bash
# Copy from example
cp examples/basic-secret.yaml my-app-secret.yaml

# Edit with your values
vim my-app-secret.yaml
```

**Key requirement**: Add the encryption annotation:
```yaml
annotations:
  def.ms/sops-encrypt: "true"  # ⚠️ Required for encryption!
```

### 2. Commit and Push

```bash
# Add and commit - encryption happens automatically
git add my-app-secret.yaml
git commit -m "Add encrypted database secret"
git push
```

**What happens:** Git automatically encrypts secrets with the annotation, stores encrypted SopsSecret in Git, while your working directory shows the readable Secret.

## Secret Types

Use the provided examples as templates:

### Opaque Secrets (Default)
```bash
# Basic credentials - see examples/basic-secret.yaml
cp examples/basic-secret.yaml my-app-credentials.yaml
```

### Docker Registry Credentials  
```bash
# Container registry auth - see examples/docker-config.yaml
cp examples/docker-config.yaml my-registry-secret.yaml
```

### TLS Certificates
```bash
# TLS certs and keys - see examples/tls-secret.yaml
cp examples/tls-secret.yaml my-tls-secret.yaml
```

## Field Types: data vs stringData

**Use `stringData` for plain text values** (recommended):
```yaml
stringData:
  password: "myplaintextpassword"
  config: |
    server:
      host: api.example.com
```

**Use `data` for base64-encoded values**:
```yaml
data:
  encoded-value: dGVzdA==  # base64: "test"
```

See `examples/mixed-fields.yaml` for both field types in one secret.

## Managing Secrets

### Viewing Secrets
```bash
# View decrypted secret (working directory)
cat my-app-secret.yaml

# View encrypted secret (stored in Git)
git show HEAD:my-app-secret.yaml
```

### Updating Secrets
```bash
# Edit the secret normally
vim my-app-secret.yaml

# Commit changes - re-encryption happens automatically
git add my-app-secret.yaml
git commit -m "Update database password"
```

### Adding New Fields
Simply add new fields to your secret file:
```yaml
stringData:
  username: "myuser"
  password: "mypass"
  new-api-key: "token-12345"  # New field
```

## Selective Encryption

Only secrets with the annotation are encrypted:

**Encrypted secrets:**
```yaml
annotations:
  def.ms/sops-encrypt: "true"  # ✅ Will be encrypted
```

**Unencrypted secrets:**
```yaml
annotations:
  description: "Public configuration"  # ❌ No encryption annotation
```

See `examples/unencrypted-secret.yaml` for an example of unencrypted secrets.

## Multi-line Content

Use YAML's `|` syntax for multi-line content:

```yaml
stringData:
  app-config.yaml: |
    server:
      host: "api.example.com"
      port: 8443
    database:
      host: "db.example.com"
      port: 5432
  config.json: |
    {
      "api": {
        "key": "secret-api-key",
        "endpoint": "https://api.example.com"
      }
    }
```

For certificates and scripts, see the examples in `examples/` directory.

## Best Practices

- **Use descriptive names**: `postgres-primary-credentials` not `secret1`
- **Add helpful annotations**: Include description, owner, rotation policy
- **Use appropriate namespaces**: Environment-specific namespaces
- **Group related secrets**: Multiple related values in one secret
- **Add labels**: For organization and selection

Example with good practices:
```yaml
metadata:
  name: postgres-primary-credentials
  namespace: production
  labels:
    app: my-application
    component: database
  annotations:
    def.ms/sops-encrypt: "true"
    description: "PostgreSQL primary database credentials"
    owner: "platform-team"
stringData:
  postgres-username: "app_user"
  postgres-password: "secret123"
  postgres-host: "postgres.internal.com"
```

## Troubleshooting

**Secret not encrypting?**
```bash
# Check for encryption annotation
grep "def.ms/sops-encrypt" my-secret.yaml

# Verify Git filter is configured  
git config filter.sops.clean
```

**Test filters manually:**
```bash
# Test encryption
cat my-secret.yaml | ./sops-clean.py

# Test decryption
git show HEAD:my-secret.yaml | ./sops-smudge.py
```

**Run full test suite:**
```bash
./run-e2e-tests.sh local
```

## GitOps Integration

Your encrypted secrets work with GitOps tools:

1. **ArgoCD/Flux** syncs encrypted SopsSecret from Git
2. **SOPS Secrets Operator** decrypts and creates target Secret  
3. **Your application** uses the decrypted Secret

Requires [SOPS Secrets Operator](https://github.com/isindir/sops-secrets-operator) in your cluster.
