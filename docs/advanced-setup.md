# 🔧 Advanced Setup & Verification

Advanced configuration options, testing procedures, and troubleshooting for your SOPS GitOps setup.

> 📝 **Note**: This assumes you've completed the [Quick Start](../README.md#quick-start) setup in the README.

## Verification and Testing

### Test Encryption/Decryption Cycle

1. **Create a test secret**:
   ```bash
   cp examples/basic-secret.yaml examples/test-secret.yaml
   ```

2. **View the secret** (should show plaintext):
   ```bash
   cat examples/test-secret.yaml
   ```

3. **Check what's stored in Git**:
   ```bash
   git add examples/test-secret.yaml
   git show :examples/test-secret.yaml  # Should show encrypted SopsSecret
   ```

4. **Commit and verify**:
   ```bash
   git commit -m "Test encrypted secret"
   cat examples/test-secret.yaml  # Should still show plaintext (smudge filter working)
   ```

5. **Clean up**:
   ```bash
   git reset HEAD~1
   rm examples/test-secret.yaml
   ```

## Advanced Configuration

### Annotation-Based Processing

By default, only secrets with the annotation `def.ms/sops-encrypt: "true"` are encrypted. 

To change this behavior, edit both `sops-clean.py` and `sops-smudge.py`:

```python
# Custom annotation key
ANNOTATION_KEY = "your-company.com/encrypt-secret"

# Disable annotation requirement (encrypt all secrets)
REQUIRE_ANNOTATION = False
```

### AGE Key Location Configuration

The Git filters automatically detect AGE keys using the following precedence:

1. **Environment Variable** (`SOPS_AGE_KEY_FILE`): Highest precedence
2. **Repository-local** (`.age/age.key`): Recommended for team projects
3. **User home directory** (`~/.age/age.key`): Fallback option

```bash
# Use specific AGE key via environment variable
export SOPS_AGE_KEY_FILE=/path/to/project-specific.key

# Repository-local key
mkdir -p .age
age-keygen -o .age/age.key
echo ".age/" >> .gitignore

# Check which key is being used
ls -la .age/age.key
```

### Multiple AGE Keys

To support multiple keys (team members, backup keys), add them to `.sops.yaml`:

```yaml
creation_rules:
  - path_regex: '.*\.ya?ml$'
    age: >-
      age1apsxs6l3u4f6z4ejpcf97kd3st234hl6k9zle5y52fmsrv098q9skpemtf,
      age1another_key_here_for_team_member_or_backup_access_12345,
      age1backup_key_stored_securely_offsite_emergency_access_67890
```

## Security Checklist

- [ ] AGE private key is backed up securely
- [ ] AGE private key is not committed to Git
- [ ] `.sops.yaml` contains only public keys
- [ ] SOPS operator has access to private key in Kubernetes
- [ ] Repository access is properly controlled
- [ ] Team members have their own AGE keys

## Next Steps

After setup is complete:

1. **Read [Usage Guide](./usage.md)** to learn how to create encrypted secrets
2. **Review [Security Guide](./security.md)** for best practices
3. **Run [E2E Tests](../run-e2e-tests.sh)** to validate everything works
4. **Start creating encrypted secrets** for your applications!
