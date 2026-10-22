---
name: secret-pkg
description: Fixture workflow package for tests/capture_workflow/run.sh.
user-invocable: true
---

# Fixture: Embedded Secret

This fixture intentionally embeds a synthetic credential-shaped string below
to exercise the `embedded_secret` check. It is not a real credential.

api_key = "sk-test1234567890abcdefghij"
