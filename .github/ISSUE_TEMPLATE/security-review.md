---
name: "\U0001F6E1\uFE0F Security Review"
about: Request or renew a security review for an MCP server
title: "[Security Review] "
labels: ["security", "review"]
assignees: ""
---

## Server Information

| Field | Value |
|-------|-------|
| **Server Name** | |
| **Review Type** | `initial` / `renewal` |
| **Current Risk Level** | `low` / `medium` / `high` / `critical` |

## Review Checklist

### Source Code Review
- [ ] Source repository identified and accessible
- [ ] No known CVEs in dependencies
- [ ] License compatible with usage

### Permissions & Data Flow
- [ ] Required permissions/scopes documented
- [ ] Data flow (input/output) assessed
- [ ] No sensitive data leakage risk
- [ ] Secret management reviewed

### MCP Primitives
- [ ] Available tools documented
- [ ] Destructive tools identified and filtered if needed
- [ ] Resource access patterns reviewed
- [ ] Prompt injection risks assessed

### Network & Infrastructure
- [ ] Backend endpoint secured (HTTPS)
- [ ] Authentication mechanism confirmed
- [ ] Rate limits appropriate

## Risk Assessment

**Proposed Risk Level**: `low` / `medium` / `high` / `critical`

**Notes**:
<!-- Detailed findings and recommendations -->

## Review Decision

- [ ] **Approved** — Server meets security requirements
- [ ] **Conditional** — Approved with restrictions (specify below)
- [ ] **Rejected** — Server does not meet requirements (specify below)

**Conditions/Reasons**:
