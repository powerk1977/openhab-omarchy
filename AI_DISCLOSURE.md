---
disclosure-default: ai-generated
models-used:
  - opencode/big-pickle
providers:
  - opencode
scope: |
  The plugin, its QML/JS/Python bridge, and the test suites were generated
  with AI assistance and human-reviewed before release. The openHAB REST/SSE
  contract is verified against a local fake server, never a live instance.
  Documentation is largely human-edited with AI drafting.
last-updated: 2026-09-08
---

# AI Disclosure

This repository follows the
[ai-disclosure convention](https://github.com/ggfevans/ai-disclosure)
([CC0 1.0](https://github.com/ggfevans/ai-disclosure/blob/main/LICENSE)).

The YAML frontmatter is machine-readable; this prose is for humans.

## Summary

The default disclosure for files in this repository is **ai-generated**:
created with AI assistance, then reviewed and verified by a human before
publication (per the convention's vocabulary, "AI-generated with human
prompting and review").

## What "ai-generated" means here

- Code was drafted by an AI coding agent and reviewed/edited by the human
  maintainer before committing.
- No file is shipped **autonomous** — nothing landed without human review and
  no change goes out untested.
- Files substantially rewritten by hand over time should be downgraded to
  `ai-assisted` (or the header removed entirely) as the convention prescribes;
  that is done on a per-file basis going forward.
- Disclosure reflects the current state of the code, not its history.

See per-file `SPDX-AI-Disclosure:` headers (SPDX-style comments at the top of
a file) where present for overrides of this default.