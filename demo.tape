# VHS Demo: Kubernetes SOPS Secrets Boilerplate
# Simplified demo showing transparent GitOps workflow

Output demo.gif

Set FontSize 23
Set Width 1200
Set Height 800
Set PlaybackSpeed 1.0
Set TypingSpeed 60ms

# Show readable YAML
Type "cat examples/basic-secret.yaml"
Enter
Sleep 2s

# Git add
Type "git add examples/basic-secret.yaml"
Enter
Sleep 1s

# Show what Git stores (encrypted)
Enter
Type "echo 'What Git actually stores (encrypted)'"
Enter
Type "git diff --cached --name-only"
Enter
Type "git show :examples/basic-secret.yaml"
Enter
Sleep 3s
Space
Sleep 1s
Space
Type "q"

# Show working directory (still readable)
Enter
Type "echo 'Working dir still readable'"
Enter
Type "cat examples/basic-secret.yaml"
Enter
Sleep 2s