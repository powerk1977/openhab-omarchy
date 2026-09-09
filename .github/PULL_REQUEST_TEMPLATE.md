<!--
  Delete this block before opening.
  Prefer small PRs. See AGENTS.md for security invariants, coding
  conventions, and the verification suite. Security-sensitive paths
  (token handling, REST/SSE, local-network gate, workflow/CI changes)
  need the red-lane scrutiny from AGENTS.md's code review rules.
-->

## Summary

<!-- What problem does this change solve, and how? -->

## AI assistance in this PR

Per the [ai-disclosure convention](https://github.com/ggfevans/ai-disclosure):

- **Level:** none / ai-assisted / ai-generated / autonomous
- **Model:**
- **Scope:**

## Checks

- [ ] All relevant tests pass (see AGENTS.md → Verification)
- [ ] Secret scan (gitleaks) is clean on this branch
- [ ] No hardcoded credentials, local absolute paths, or private
      server details introduced
- [ ] New dependencies (if any) verified on their registry: name,
      provenance, license
- [ ] No debug artifacts (`console.log`, `print(`, `debugger`, `TODO`)
- [ ] UI text uses `Style`/`Color` tokens; `Text` is `PlainText`
- [ ] CI/security gates were not weakened