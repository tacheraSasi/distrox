# Contributing to distrox

Thank you for considering contributing to distrox! This document provides guidelines and instructions for contributing.

## Code of Conduct

This project adheres to a code of conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates. When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce**
- **Expected vs actual behavior**
- **Environment details** (OS, Docker version, etc.)
- **Logs and error messages**

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When suggesting an enhancement:

- **Use a clear title**
- **Provide detailed description**
- **Explain why this would be useful**
- **Include examples if applicable**

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/AmazingFeature`)
3. **Make your changes**
4. **Test thoroughly**
5. **Commit with clear messages** (`git commit -m 'Add some AmazingFeature'`)
6. **Push to your fork** (`git push origin feature/AmazingFeature`)
7. **Open a Pull Request**

#### PR Guidelines

- Follow existing code style
- Update documentation as needed
- Add tests for new features
- Ensure all tests pass
- Keep PRs focused on a single change
- Write clear commit messages

## Development Setup

### Prerequisites

```bash
# Docker (kernel + rootfs compiles)
# xorriso + libarchive/bsdtar (initramfs + ISO steps)
# anyzig (Zig userspace + init builds)
# QEMU (optional, for testing)
sudo pacman -S libisoburn libarchive qemu-desktop  # Arch (omarchy)
brew install xorriso libarchive qemu  # macOS
sudo apt-get install xorriso libarchive-tools qemu-system-x86  # Ubuntu
# anyzig: https://github.com/sno2/anyzig
```

Verify with `make check-deps`.

### Local Development

```bash
# Clone your fork
git clone https://github.com/yourusername/distrox.git
cd distrox

# Build the project
make build

# Sanity-check the build artifacts
./scripts/test.sh

# Test with QEMU
make qemu-nographic
```

## Code Style

### Shell Scripts

- Use `#!/usr/bin/env bash` for bash scripts
- Use `#!/bin/sh` for POSIX shell scripts
- Enable strict mode: `set -euo pipefail`
- Add function documentation
- Use meaningful variable names
- Quote variables: `"${var}"`

### Zig

- Follow the style used in `userspace/` and `init/`
- Keep `userspace/src/commands/listing.zig` and the `ZIG_COMMANDS`
  environment list in `scripts/mkinitramfs.sh` in sync

### Dockerfile

- Use multi-stage builds
- Minimize layers
- Use specific base image tags
- Add comments for complex operations
- Group related commands
- Clean up in the same layer

## Testing

### Running Tests

```bash
# Sanity checks on build artifacts
./scripts/test.sh

# Dependency check
make check-deps

# Full build (the real integration test)
make build

# QEMU boot test
make qemu-nographic
```

### Writing Tests

Add tests to `scripts/test.sh`:

```bash
test_new_feature() {
    log_info "Testing new feature..."
    if some_test_command; then
        log_success "Feature works"
        return 0
    else
        log_error "Feature failed"
        return 1
    fi
}
```

## Documentation

- Update README.md for user-facing changes
- Add comments for complex code
- Update relevant docs in `docs/`
- Include examples where helpful

## Commit Messages

Use clear, descriptive commit messages:

```sh
Short summary (50 chars or less)

More detailed explanatory text if needed. Wrap at 72 characters.
Explain the problem this commit solves and why you chose this solution.

- Bullet points are okay
- Use present tense ("Add feature" not "Added feature")
- Reference issues: "Fixes #123"
```

## Release Process

1. Update version numbers
2. Update CHANGELOG.md
3. Create release tag

CI/CD is not set up yet — a future GitHub Actions workflow should build via
`make build` and publish `build/output.iso` as a release artifact.

## Questions?

Feel free to open an issue for questions or start a discussion.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
