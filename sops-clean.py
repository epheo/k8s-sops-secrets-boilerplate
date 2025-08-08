#!/usr/bin/env python3
"""
Git clean filter for SOPS encryption
Converts Kubernetes Secrets to SopsSecrets and encrypts them transparently
"""

# Configuration - easily toggle annotation requirement
REQUIRE_ANNOTATION = True  # Set to False to process all secrets
ANNOTATION_KEY = "def.ms/sops-encrypt"  # Annotation key to look for
ANNOTATION_VALUE = "true"  # Expected annotation value
DEFAULT_AGE_KEY_PATH = ".age/age.key"  # Default repository-local path

import sys
import yaml
import subprocess
import tempfile
import os

def should_process_secret(secret):
    """Check if secret should be processed based on annotation"""
    if not REQUIRE_ANNOTATION:
        return True
    
    annotations = secret.get('metadata', {}).get('annotations', {})
    return annotations.get(ANNOTATION_KEY) == ANNOTATION_VALUE

def secret_to_sops_secret(secret):
    """Convert a Kubernetes Secret to SopsSecret format"""
    
    # Generate SopsSecret name (avoid duplicate suffix)
    original_name = secret['metadata']['name']
    sops_name = original_name if original_name.endswith('-sops') else f"{original_name}-sops"
    
    # Preserve metadata (labels, annotations)
    sops_metadata = {
        'name': sops_name,
        'namespace': secret['metadata'].get('namespace')
    }
    
    # Copy labels and annotations from original metadata
    if 'labels' in secret['metadata']:
        sops_metadata['labels'] = secret['metadata']['labels']
    if 'annotations' in secret['metadata']:
        sops_metadata['annotations'] = secret['metadata']['annotations']
    
    # Build secret template - preserve original field types
    secret_template = {
        'name': original_name,
        'type': secret.get('type', 'Opaque')
    }
    
    # Handle 'data' field (base64 encoded values) - keep as data
    if 'data' in secret:
        secret_template['data'] = secret['data']
    
    # Handle 'stringData' field (plain text values) - keep as stringData  
    if 'stringData' in secret:
        secret_template['stringData'] = secret['stringData']
    
    # Handle immutable field if present
    if 'immutable' in secret:
        secret_template['immutable'] = secret['immutable']
    
    
    return {
        'apiVersion': 'isindir.github.com/v1alpha3',
        'kind': 'SopsSecret',
        'metadata': sops_metadata,
        'spec': {
            'secretTemplates': [secret_template]
        }
    }

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

def encrypt_with_sops(content):
    """Encrypt YAML content using SOPS"""
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(content, f, default_flow_style=False)
            temp_path = f.name
        
        # Set up environment with AGE key path
        env = os.environ.copy()
        age_key_path = get_age_key_path()
        if age_key_path:
            env['SOPS_AGE_KEY_FILE'] = age_key_path
        
        result = subprocess.run(
            ['sops', '-e', temp_path],
            capture_output=True,
            text=True,
            env=env,
            check=True
        )
        
        return result.stdout
        
    except subprocess.CalledProcessError:
        # SOPS encryption failed, return original content
        return yaml.dump(content, default_flow_style=False)
    except Exception:
        # Any other error, return original content
        return yaml.dump(content, default_flow_style=False)
    finally:
        # Always cleanup temp file
        if temp_path and os.path.exists(temp_path):
            os.unlink(temp_path)

def main():
    try:
        # Read content from stdin first for fast detection
        input_content = sys.stdin.read()
        
        # Fast path: Skip non-secrets quickly
        if 'kind:' not in input_content or ('Secret' not in input_content and 'SopsSecret' not in input_content):
            sys.stdout.write(input_content)
            return
        
        # Skip multi-document YAML files
        if input_content.startswith('---\n') or '\n---\n' in input_content:
            sys.stdout.write(input_content)
            return
        
        # Parse single YAML document
        content = yaml.safe_load(input_content)
        
        if not content or not isinstance(content, dict):
            sys.stdout.write(input_content)
            return
        
        kind = content.get('kind', '')
        
        if kind == 'Secret':
            # Check if secret should be processed
            if should_process_secret(content):
                # Convert Secret to SopsSecret and encrypt
                sops_secret = secret_to_sops_secret(content)
                encrypted = encrypt_with_sops(sops_secret)
                sys.stdout.write(encrypted)
            else:
                # Secret doesn't have required annotation, pass through unchanged
                sys.stdout.write(input_content)
        elif kind == 'SopsSecret':
            # Already a SopsSecret, just encrypt
            encrypted = encrypt_with_sops(content)
            sys.stdout.write(encrypted)
        else:
            # Not a Secret or SopsSecret, pass through unchanged
            sys.stdout.write(input_content)
            
    except Exception:
        # On any error, pass through original input
        sys.stdout.write(input_content)

if __name__ == '__main__':
    main()