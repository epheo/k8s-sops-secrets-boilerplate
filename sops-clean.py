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
    
    # Generate SopsSecret name
    original_name = secret['metadata']['name']
    sops_name = f"{original_name}-sops" if not original_name.endswith('-sops') else original_name
    
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
    
    # Copy template-level labels/annotations if present
    if 'labels' in secret['metadata']:
        secret_template['labels'] = secret['metadata']['labels']
    if 'annotations' in secret['metadata']:
        secret_template['annotations'] = secret['metadata']['annotations']
    
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
        
        os.unlink(temp_path)
        return result.stdout
        
    except subprocess.CalledProcessError:
        # SOPS encryption failed, return original content
        os.unlink(temp_path)
        return yaml.dump(content, default_flow_style=False)
    except Exception:
        # Any other error, return original content
        if 'temp_path' in locals():
            os.unlink(temp_path)
        return yaml.dump(content, default_flow_style=False)

def main():
    try:
        # Read content from stdin first for fast detection
        input_content = sys.stdin.read()
        
        # Fast path: Ultra-fast string check to avoid expensive processing
        # for files that definitely aren't secrets (optimization)
        if not ('kind: Secret' in input_content or 'kind: SopsSecret' in input_content):
            sys.stdout.write(input_content)
            return
        
        # Check for multi-document YAML separators (at start of line)
        if '\n---\n' in input_content or input_content.startswith('---\n'):
            # Multi-document file detected, pass through unchanged
            sys.stdout.write(input_content)
            return
        
        # Parse single YAML document
        content = yaml.safe_load(input_content)
        
        if not content or not isinstance(content, dict):
            # Not valid YAML or not a dict, pass through
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
                yaml.dump(content, sys.stdout, default_flow_style=False)
        elif kind == 'SopsSecret':
            # Already a SopsSecret, just encrypt
            encrypted = encrypt_with_sops(content)
            sys.stdout.write(encrypted)
        else:
            # Not a Secret or SopsSecret, pass through unchanged
            yaml.dump(content, sys.stdout, default_flow_style=False)
            
    except Exception:
        # On any error, pass through original input
        # input_content is already available from the start of main()
        if 'input_content' in locals():
            sys.stdout.write(input_content)
        else:
            # Fallback if something went wrong very early
            sys.stdin.seek(0)
            sys.stdout.write(sys.stdin.read())

if __name__ == '__main__':
    main()