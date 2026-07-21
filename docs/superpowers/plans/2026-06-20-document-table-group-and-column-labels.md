# Document Table Group And Column Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить колонку группы в таблицу позиций и независимое переименование заголовков колонок каждого табличного блока.

**Architecture:** Расширить существующие определения колонок ключом `group_name`. Пользовательские названия хранить в `block.column_labels`, а получение отображаемого заголовка централизовать в одном helper, который используется панелью свойств, preview и экспортом.

**Tech Stack:** Vanilla JavaScript, CSS, PHP-шаблон подключения ресурсов, Playwright.

---

### Task 1: Регрессионные тесты данных и заголовков

**Files:**
- Modify: `tests/e2e/documents-rendering.spec.js`

- [ ] **Step 1: Write the failing test**

Добавить тест, создающий две таблицы позиций с одинаковыми ключами, но разными `column_labels`. Проверить наличие `group_name`, вывод значения группы, независимые заголовки и возврат стандартного заголовка при пустом значении.

- [ ] **Step 2: Run test to verify it fails**

Run: `npx playwright test tests/e2e/documents-rendering.spec.js --project=edge --workers=1`

Expected: FAIL, потому что `group_name` отсутствует в определениях и `column_labels` не применяется.

### Task 2: Модель колонок и единый resolver заголовков

**Files:**
- Modify: `assets/js/spaces/documents.js`

- [ ] **Step 1: Add the group column**

Добавить `{ key: 'group_name', label: 'Группа', default: false }` в колонки таблицы позиций и обработку `row.group_name`.

- [ ] **Step 2: Preserve backward-compatible defaults**

Изменить `documentsDefaultColumnKeys`, чтобы новые необязательные колонки не включались автоматически.

- [ ] **Step 3: Add per-block labels**

Добавить `documentsGetBlockColumnLabel(block, key)` и `documentsUpdateTableColumnLabel(id, key, value)`. Пустое значение удаляет override.

- [ ] **Step 4: Use labels in renderers**

Перевести `documentsGetExtendedTableColumns` и `block.columns` на единый resolver.

### Task 3: Панель редактирования колонок

**Files:**
- Modify: `assets/js/spaces/documents.js`
- Modify: `assets/css/app.css`

- [ ] **Step 1: Add label input**

В каждой активной строке колонки вывести поле заголовка перед полем ширины.

- [ ] **Step 2: Keep disabled rows compact**

Для выключенных колонок оставить переключатель и статус без полей редактирования.

- [ ] **Step 3: Make the row responsive**

Обновить сетку `.docs-column-row`, чтобы название и ширина не перекрывались на узкой панели.

### Task 4: Проверка и кеш

**Files:**
- Modify: `index.php`

- [ ] **Step 1: Bump asset versions**

Обновить версии `documents.js` и `app.css`.

- [ ] **Step 2: Run syntax checks**

Run: `node --check assets/js/spaces/documents.js`

Run: `E:\Program Files\XAMPP\php\php.exe -l index.php`

Expected: exit code 0.

- [ ] **Step 3: Run focused tests**

Run: `npx playwright test tests/e2e/documents-rendering.spec.js --project=edge --workers=1`

Expected: PASS.
