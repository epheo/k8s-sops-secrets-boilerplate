#!/usr/bin/env python3
"""
Git smudge filter for SOPS decryption
Decrypts SopsSecrets and converts them back to standard Kubernetes Secrets
"""

# Configuration - easily toggle annotation requirement
REQUIRE_ANNOTATION = True  # Set to False to process all secrets
ANNOTATION_KEY = "def.ms/sops-encrypt"  # Annotation key to look for
ANNOTATION_VALUE = "true"  # Expected annotation value
DEFAULT_AGE_KEY_PATH = ".age/age.key"  # Default repository-local path

import sys
import yaml
import base64
import subprocess
import tempfile
import os

def should_process_sops_secret(sops_secret):
    """Check if SopsSecret should be processed based on annotation"""
    if not REQUIRE_ANNOTATION:
        return True
    
    # Check for annotation in SopsSecret metadata first
    annotations = sops_secret.get('metadata', {}).get('annotations', {})
    if annotations.get(ANNOTATION_KEY) == ANNOTATION_VALUE:
        return True
    
    # Also check in secret template annotations (fallback)
    templates = sops_secret.get('spec', {}).get('secretTemplates', [])
    if templates:
        template_annotations = templates[0].get('annotations', {})
        return template_annotations.get(ANNOTATION_KEY) == ANNOTATION_VALUE
    
    return False

def sops_secret_to_secret(sops_secret):
    """Convert a SopsSecret back to standard Kubernetes Secret format"""
    if 'spec' not in sops_secret or 'secretTemplates' not in sops_secret['spec']:
        return sops_secret
    
    templates = sops_secret['spec']['secretTemplates']
    if not templates:
        return sops_secret
    
    # Use the first template (most common case)
    template = templates[0]
    
    # Handle both data and stringData fields
    secret_data = {}
    secret_string_data = {}
    
    # Process data field (base64 encoded)
    for key, value in template.get('data', {}).items():
        secret_data[key] = value
    
    # Process stringData field (plain text)
    for key, value in template.get('stringData', {}).items():
        secret_string_data[key] = value
    
    # Build Secret metadata
    secret_metadata = {
        'name': template.get('name', sops_secret['metadata']['name']),
        'namespace': sops_secret['metadata'].get('namespace')
    }
    
    # Copy labels and annotations from template or SopsSecret metadata
    template_labels = template.get('labels') or sops_secret['metadata'].get('labels')
    template_annotations = template.get('annotations') or sops_secret['metadata'].get('annotations')
    
    if template_labels:
        secret_metadata['labels'] = template_labels
    if template_annotations:
        secret_metadata['annotations'] = template_annotations
    
    # Build the Secret
    secret = {
        'apiVersion': 'v1',
        'kind': 'Secret',
        'metadata': secret_metadata,
        'type': template.get('type', 'Opaque')
    }
    
    # Add data fields if they exist
    if secret_data:
        secret['data'] = secret_data
    if secret_string_data:
        secret['stringData'] = secret_string_data
    
    # Handle immutable field if present
    if 'immutable' in template:
        secret['immutable'] = template['immutable']
    
    return secret

def get_age_key_path():
    """Get AGE key path: ENV var takes precedence, otherwise use configured default"""
    # 1. Check environment variable first (highest precedence)
    env_path = os.environ.get('SOPS_AGE_KEY_FILE')
    if env_path and os.path.exists(env_path):
        return env_path
    
    # 2. Use configured default path
    if os.path.exists(DEFAULT_AGE_KEY_PATH):
        return DEFAULT_AGE_KEY_PATH
    
    return None

def decrypt_with_sops(content):
    """Decrypt YAML content using SOPS"""
    # Get AGE key path using proper precedence
    age_key_path = get_age_key_path()
    if not age_key_path:
        return None
    
    try:
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(content)
            temp_path = f.name
        
        env = os.environ.copy()
        env['SOPS_AGE_KEY_FILE'] = age_key_path
        
        result = subprocess.run(
            ['sops', '-d', temp_path],
            capture_output=True,
            text=True,
            env=env,
            check=True
        )
        
        os.unlink(temp_path)
        return yaml.safe_load(result.stdout)
        
    except subprocess.CalledProcessError:
        # Decryption failed
        os.unlink(temp_path)
        return None
    except Exception:
        # Any other error
        if 'temp_path' in locals():
            os.unlink(temp_path)
        return None

def is_sops_encrypted(content):
    """Check if content appears to be SOPS encrypted"""
    return isinstance(content, str) and 'sops:' in content

def main():
    try:
        # Read content from stdin
        input_content = sys.stdin.read()
        
        # Fast path: Ultra-fast string check to avoid expensive processing
        # for files that definitely aren't SOPS secrets (optimization)
        if not ('kind: SopsSecret' in input_content or 'sops:' in input_content):
            sys.stdout.write(input_content)
            return
        
        # Check for multi-document YAML separators (at start of line)
        # Don't count --- inside encrypted content
        if '\n---\n' in input_content or input_content.startswith('---\n'):
            # Multi-document file detected, pass through unchanged
            sys.stdout.write(input_content)
            return
        
        # Check if this looks like encrypted SOPS content (single document)
        if is_sops_encrypted(input_content):
            # Try to decrypt single SOPS document
            decrypted = decrypt_with_sops(input_content)
            if decrypted and isinstance(decrypted, dict):
                kind = decrypted.get('kind', '')
                if kind == 'SopsSecret':
                    # Check if SopsSecret should be processed
                    if should_process_sops_secret(decrypted):
                        # Convert SopsSecret back to Secret
                        secret = sops_secret_to_secret(decrypted)
                        yaml.dump(secret, sys.stdout, default_flow_style=False)
                    else:
                        # SopsSecret doesn't have required annotation, return as-is
                        yaml.dump(decrypted, sys.stdout, default_flow_style=False)
                    return
                else:
                    # Decrypted but not a SopsSecret, return as-is
                    yaml.dump(decrypted, sys.stdout, default_flow_style=False)
                    return
        
        # Try to parse as single document YAML
        try:
            content = yaml.safe_load(input_content)
            if content and isinstance(content, dict):
                kind = content.get('kind', '')
                if kind == 'SopsSecret':
                    # Check if unencrypted SopsSecret should be processed
                    if should_process_sops_secret(content):
                        # Convert SopsSecret back to Secret
                        secret = sops_secret_to_secret(content)
                        yaml.dump(secret, sys.stdout, default_flow_style=False)
                    else:
                        # SopsSecret doesn't have required annotation, return as-is
                        yaml.dump(content, sys.stdout, default_flow_style=False)
                    return
        except:
            pass
        
        # Not encrypted, not a SopsSecret, or parsing failed - pass through
        sys.stdout.write(input_content)
        
    except Exception:
        # On any error, pass through original input
        sys.stdin.seek(0)
        content = sys.stdin.read()
        sys.stdout.write(content)

if __name__ == '__main__':
    main()