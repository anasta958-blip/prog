# Document Canvas Center Snap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the permanent document-canvas center marker with PowerPoint-like center snapping during block dragging.

**Architecture:** Add a pure coordinate helper that compares the dragged block center with the current page content center. The pointer-move handler applies the returned coordinates and toggles temporary CSS guide classes; pointer-up clears those classes.

**Tech Stack:** JavaScript, CSS, Playwright.

---

### Task 1: Cover center snapping with regression tests

**Files:**
- Modify: `tests/e2e/documents-rendering.spec.js`

- [ ] **Step 1: Add assertions for the pure snap calculation**

Test exact snapping within 10 pixels, no snapping outside the threshold, and independent snapping on each axis.

- [ ] **Step 2: Assert permanent center markup is absent**

Render preview pages and verify that `docs-page-center-ruler` and `docs-page-center-label` are not present.

- [ ] **Step 3: Run the focused test**

Run: `npx playwright test tests/e2e/documents-rendering.spec.js --project=edge --workers=1`

Expected: FAIL because the helper does not exist and the permanent marker is still rendered.

### Task 2: Implement snapping and temporary guides

**Files:**
- Modify: `assets/js/spaces/documents.js`
- Modify: `assets/css/app.css`
- Modify: `index.php`

- [ ] **Step 1: Add `documentsApplyCenterSnap`**

Return clamped `x` and `y` plus `snapX` and `snapY` flags. Compare block centers against the current page content center with a 10-pixel threshold.

- [ ] **Step 2: Apply snapping during pointer movement**

Use the rendered block dimensions, apply the helper result, update inline coordinates, and toggle temporary guide classes on the active page content.

- [ ] **Step 3: Clear guides after dragging**

Remove guide classes on pointer-up and before displaying a guide on another page.

- [ ] **Step 4: Remove permanent center markup and CSS**

Delete the old ruler, tick marks, and center label. Add pseudo-element guides visible only while the active snap class is present.

- [ ] **Step 5: Update the CSS cache version**

Increment the `app.css` query version in `index.php`.

### Task 3: Verify

**Files:**
- Test: `tests/e2e/documents-rendering.spec.js`

- [ ] **Step 1: Run JavaScript syntax validation**

Run: `node --check assets/js/spaces/documents.js`

Expected: exit code 0.

- [ ] **Step 2: Run focused Playwright tests**

Run: `npx playwright test tests/e2e/documents-rendering.spec.js --project=edge --workers=1`

Expected: all tests pass.

- [ ] **Step 3: Verify UTF-8**

Read all modified source files with strict UTF-8 decoding.

Expected: every file decodes successfully.

