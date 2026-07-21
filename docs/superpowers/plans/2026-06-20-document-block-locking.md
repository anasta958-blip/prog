# Document Block Locking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent block locking, chain movement/resizing, and front/back layer controls to the document canvas.

**Architecture:** Store `locked` and `z_index` in each block payload. Use pure transaction helpers to calculate chain movement and resize displacement before mutating state, then connect them to the existing pointer and native resize handlers. Render one reusable context menu outside the canvas.

**Tech Stack:** JavaScript, CSS, PHP templates, Playwright.

---

### Task 1: Add regression tests

**Files:**
- Modify: `tests/e2e/documents-rendering.spec.js`

- [ ] Test state normalization and default unlocked blocks.
- [ ] Test chain movement, unlocked overlap, diagonal movement, and boundaries.
- [ ] Test resize displacement.
- [ ] Test context-menu commands and persistent layers.
- [ ] Run focused tests and confirm failure.

### Task 2: Implement block state and collision transactions

**Files:**
- Modify: `assets/js/spaces/documents.js`

- [ ] Normalize `locked` and `z_index`.
- [ ] Add pure block rectangle and swept-path helpers.
- [ ] Add transactional locked-chain movement.
- [ ] Add transactional locked resize displacement.
- [ ] Preserve free movement for unlocked blocks.

### Task 3: Implement context menu and layers

**Files:**
- Modify: `assets/js/spaces/documents.js`
- Modify: `assets/css/app.css`

- [ ] Render one context menu on right click.
- [ ] Add lock/unlock command.
- [ ] Add front/back layer commands.
- [ ] Render lock indicator and use stored z-index.
- [ ] Close menu on outside click, scroll, and Escape.

### Task 4: Integrate resizing and verify

**Files:**
- Modify: `assets/js/spaces/documents.js`
- Modify: `index.php`
- Test: `tests/e2e/documents-rendering.spec.js`

- [ ] Apply resize transaction before committing dimensions.
- [ ] Revert invalid resize dimensions.
- [ ] Update asset cache versions.
- [ ] Run JavaScript and PHP syntax checks.
- [ ] Run focused Playwright tests.
- [ ] Verify modified files as strict UTF-8.

