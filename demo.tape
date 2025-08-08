# VHS Demo: Kubernetes SOPS Secrets Boilerplate
# Simplified demo showing transparent GitOps workflow

Output demo.gif

Set FontSize 14
Set Width 800
Set Height 600
Set PlaybackSpeed 1.0
Set TypingSpeed 80ms
Set Theme "Dracula"

# Clear terminal and start
Type "clear"
Enter
Sleep 1s

# Show readable YAML
Type "echo"
Enter
Type "echo 'View secret - readable YAML with sensitive data'"
Enter
Type "cat examples/basic-secret.yaml"
Enter
Sleep 3s

# Git add
Type "echo"
Enter
Type "echo 'Add secret to Git'"
Enter
Type "git add examples/basic-secret.yaml"
Enter
Sleep 1s

# Show what Git stores (encrypted)
Type "echo"
Enter
Type "echo 'What Git actually stores (encrypted)'"
Enter
Type "git show :examples/basic-secret.yaml"
Enter
Sleep 4s

# Show working directory (still readable)
Type "echo"
Enter
Type "echo 'Working directory still shows readable version'"
Enter
Type "cat examples/basic-secret.yaml"
Enter
Sleep 2s

# Commit
Type "echo"
Enter
Type "echo 'Commit the encrypted secret'"
Enter
Type "git commit -m 'Add encrypted secret'"
Enter
Sleep 1s

# Demonstrate transparency
Type "echo"
Enter
Type "echo 'Verify transparency - Git stores encrypted:'"
Enter
Type "git show HEAD:examples/basic-secret.yaml | head -8"
Enter
Sleep 2s
Type "echo"
Enter
Type "echo 'Working directory shows decrypted:'"
Enter
Type "cat examples/basic-secret.yaml | head -6"
Enter
Sleep 2s
