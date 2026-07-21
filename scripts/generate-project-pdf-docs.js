const fs = require('fs');
const path = require('path');
const { chromium } = require('@playwright/test');

const root = path.resolve(__dirname, '..');
const docsDir = path.join(root, 'docs');
const htmlPath = path.join(docsDir, 'PROJECT_DOCUMENTATION.html');
const pdfPath = path.join(docsDir, 'PROJECT_DOCUMENTATION.pdf');

const SKIP_DIRS = new Set(['node_modules', 'playwright-report', 'test-results', '.git', '.codegraph']);
const SOURCE_EXTS = new Set(['.php', '.js', '.css', '.sql', '.md']);
const DOC_OUTPUTS = new Set([
  'docs/PROJECT_FULL_DOCUMENTATION.md',
  'docs/PROJECT_SYMBOL_REFERENCE.md',
  'docs/PROJECT_DOCUMENTATION.html',
  'docs/PROJECT_DOCUMENTATION.pdf',
]);

function rel(file) {
  return path.relative(root, file).replace(/\\/g, '/');
}

function esc(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, out);
      continue;
    }
    if (!SOURCE_EXTS.has(path.extname(entry.name))) continue;
    if (DOC_OUTPUTS.has(rel(full))) continue;
    out.push(full);
  }
  return out.sort((a, b) => rel(a).localeCompare(rel(b), 'ru'));
}

function folderKey(file) {
  const r = rel(file);
  const parts = r.split('/');
  if (parts.length === 1) return 'Корень проекта';
  if (parts[0] === 'assets' && parts[1] === 'js' && parts[2]) {
    if (parts[2] === 'spaces' && parts[3]) return `assets/js/spaces/${parts[3]}`;
    if (parts[2] === 'builder') return 'assets/js/builder';
    return 'assets/js';
  }
  if (parts[0] === 'templates' && parts[1] === 'spaces' && parts[2]) return `templates/spaces/${parts[2]}`;
  if (parts[0] === 'templates') return `templates/${parts[1] || ''}`.replace(/\/$/, '');
  return parts[0];
}

function folderDescription(key) {
  const map = {
    'Корень проекта': 'В корне лежат входные точки приложения, схема базы, package.json, README, версия приложения и общие служебные файлы.',
    api: 'В этой папке хранятся PHP endpoint-файлы. Они принимают HTTP-запросы от frontend, проверяют права и работают с базой.',
    includes: 'Общие backend-модули: подключение к БД, авторизация, права, CSRF, пагинация и переиспользуемая логика КП/ПКП.',
    'includes/quotes': 'Общая серверная логика коммерческих предложений и предварительных КП: payload, нормализация, расчеты, переносы и интеграционные helpers.',
    assets: 'Публичные статические ресурсы приложения.',
    'assets/js': 'Базовые frontend-модули: API-клиент, состояние, навигация, загрузка страниц, helpers и авторизация.',
    'assets/js/builder': 'Общий табличный builder. Через него создаются категории, разделы, товары и работы в КП, ПКП и комплектации.',
    'assets/js/spaces/catalog': 'Frontend общего каталога товаров, работ, комплектов, расходов и справочников каталога.',
    'assets/js/spaces/documents': 'Конструктор документов: блоки, холст, drag/drop, таблицы, печать, QR и версии шаблонов.',
    'assets/js/spaces/kp': 'Пространство КП/ПКП: канбан, карточка, builder, сохранение, клиенты, подрядчики и каталог внутри КП.',
    'assets/js/spaces/orders': 'Комплектация объекта: канбан, карточки заказов, товары объекта, счета и переносы обратно в КП.',
    'assets/js/spaces/settings': 'Настройки: права, единицы, поставщики, группы и служебные справочники.',
    'assets/js/spaces/users': 'Пользователи и визуализация структуры компании.',
    'assets/js/shared': 'Общие frontend-компоненты, используемые несколькими пространствами.',
    'assets/css': 'Основные стили интерфейса.',
    templates: 'PHP-шаблоны layout, страниц и модальных окон. В них почти нет бизнес-логики, только HTML-разметка.',
    'templates/layout': 'Общий каркас приложения: экран входа, shell и боковое меню.',
    'templates/modals': 'Общие модальные окна проекта.',
    'templates/spaces/catalog': 'HTML-разметка пространства общего каталога.',
    'templates/spaces/documents': 'HTML-разметка конструктора документов.',
    'templates/spaces/kp': 'HTML-разметка страниц КП/ПКП, клиентов, подрядчиков, компании и каталога.',
    'templates/spaces/orders': 'HTML-разметка комплектации, новых заявок, сотрудников и заказов.',
    'templates/spaces/settings': 'HTML-разметка разделов настроек.',
    migrations: 'SQL-миграции для точечных обновлений существующей базы.',
    scripts: 'Служебные скрипты: генерация версии и документации.',
    tests: 'Playwright/e2e тесты и тестовые helpers.',
    docs: 'Документация, планы и технические заметки проекта.',
  };
  return map[key] || 'Папка содержит файлы одного функционального участка проекта.';
}

function filePurpose(file) {
  const p = rel(file);
  const map = {
    'index.php': 'Собирает SPA: подключает layout, страницы, модальные окна, lazy assets и стартовые JS/CSS.',
    'quote.php': 'Публичный просмотр КП/ПКП по токену. Клиент выбирает вариант, видит состав и итоговые суммы.',
    'schema.sql': 'Полная актуальная схема создания базы данных.',
    'README.md': 'Краткое описание проекта и базовые инструкции.',
    'api/auth.php': 'Авторизация, выход, получение текущего пользователя и CSRF-токена.',
    'api/catalog.php': 'Каталог: категории, разделы, товары, работы, группы, поставщики, импорт и экспорт.',
    'api/kp.php': 'Коммерческие предложения: список, карточка, сохранение, клиенты, подрядчики, компании и статусы.',
    'api/pkp.php': 'Предварительные КП и переносы между ПКП, КП и комплектацией.',
    'api/orders.php': 'Комплектация объекта: канбан, товары объекта, счета, переносы и статусы.',
    'api/documents.php': 'Шаблоны документов, версии шаблонов и загрузка изображений.',
    'api/users.php': 'Пользователи, роли, связи РОП-менеджер, директор и перенос владения.',
    'api/permissions.php': 'Сохранение и чтение политик прав по ролям.',
    'api/meta.php': 'Единая выдача справочников frontend-у.',
    'api/version.php': 'Версия приложения и текст модального окна обновления.',
    'api/email.php': 'SMTP/email, сборка MIME-писем и генерация PDF-вложений.',
    'api/telegram.php': 'Отправка PDF/документов в Telegram.',
    'includes/auth.php': 'Центральный backend helper: БД, сессия, CSRF, права, справочники, JSON.',
    'includes/assets.php': 'Версионирование assets и расчёт общей версии приложения.',
    'includes/pagination.php': 'Пагинация API: limit/offset, count, формат ответа.',
    'includes/access_middleware.php': 'Компактный middleware для проверки прав действий.',
    'includes/quotes/quote_common.php': 'Общая серверная логика КП/ПКП: payload, каталог, расчёты, PDF/ФНС helpers.',
    'assets/js/app.api.js': 'Frontend API wrapper: fetch, CSRF, единый формат ответа и кеш пользователей.',
    'assets/js/app.auth.js': 'Frontend входа и выхода.',
    'assets/js/app.constants.js': 'Константы ролей, цветов, подписей, прав и пространств.',
    'assets/js/app.helpers.js': 'Общие функции: toast, escape, форматирование, архивы, kanban helpers.',
    'assets/js/app.init.js': 'Старт приложения: auth check, meta, навигация, проверка обновлений.',
    'assets/js/app.loader.js': 'Lazy-load JS-файлов по страницам.',
    'assets/js/app.modals.js': 'Открытие и закрытие модальных окон.',
    'assets/js/app.nav.js': 'SPA-навигация, восстановление страницы и синхронизация бокового меню.',
    'assets/js/app.state.js': 'Глобальное состояние frontend.',
    'assets/js/builder/catalog-fields.js': 'Автокомплиты и выпадающие списки группы, названия, маркировки, единицы, поставщика.',
    'assets/js/builder/core.js': 'Ядро builder-а: категории, разделы, строки, выбор, удаление, синхронизация с каталогом.',
    'assets/js/builder/dom.js': 'Частичная DOM-отрисовка builder-а и сворачивание блоков.',
    'assets/js/builder/drafts.js': 'Локальные черновики КП/ПКП/комплектации.',
    'assets/js/builder/flow.js': 'Расчеты строк, автоработы, цвета, пересчет итогов.',
    'assets/js/builder/render.js': 'HTML-отрисовка категорий, разделов и таблиц builder-а.',
    'assets/js/builder/save.js': 'Сохранение и печать старого/общего builder-документа.',
    'assets/js/spaces/catalog.js': 'UI общего каталога и операции с карточками каталога.',
    'assets/js/spaces/documents.js': 'Полный frontend конструктора документов.',
    'assets/js/spaces/orders.js': 'UI комплектации объекта и канбана заказов.',
    'assets/js/spaces/settings.js': 'UI настроек прав, групп, поставщиков и единиц.',
    'assets/js/spaces/users.js': 'UI пользователей и дерева сотрудников.',
    'assets/js/shared/employees.js': 'Общая визуализация сотрудников и прав.',
    'assets/js/spaces/kp/builder-core.js': 'Специфичная логика builder-а КП/ПКП.',
    'assets/js/spaces/kp/catalog.js': 'Каталог, клиенты, подрядчики и справочники внутри КП.',
    'assets/js/spaces/kp/render.js': 'Отрисовка вариантов, канбана, клиентов, подрядчиков и комплектов.',
    'assets/js/spaces/kp/save.js': 'Сохранение КП/ПКП, печать, preview, drag/drop канбана и переносы.',
    'assets/js/spaces/kp/state.js': 'Состояние, нормализация и helpers КП/ПКП.',
    'assets/css/app.css': 'Единый CSS интерфейса.',
  };
  return map[p] || filePurposeByPattern(p);
}

function filePurposeByPattern(p) {
  if (p.startsWith('templates/')) return 'HTML-шаблон соответствующей страницы или модального окна.';
  if (p.startsWith('migrations/')) return 'SQL-миграция для обновления структуры или справочников базы.';
  if (p.startsWith('tests/')) return 'Автоматический тест или helper для Playwright.';
  if (p.startsWith('docs/')) return 'Документация или техническая заметка.';
  if (p.startsWith('scripts/')) return 'Служебный скрипт проекта.';
  return 'Вспомогательный файл проекта.';
}

function extractSymbols(file) {
  if (!['.js', '.php'].includes(path.extname(file))) return [];
  const lines = read(file).split(/\r?\n/);
  const patterns = [
    ['function', /^\s*(?:async\s+)?function\s+([A-Za-z0-9_$]+)\s*\(([^)]*)\)/],
    ['function', /^\s*([A-Za-z0-9_$]+)\s*=\s*(?:async\s+)?function\s*\(([^)]*)\)/],
    ['function', /^\s*(?:const|let|var)\s+([A-Za-z0-9_$]+)\s*=\s*(?:async\s*)?\(([^)]*)\)\s*=>/],
    ['class', /^\s*class\s+([A-Za-z0-9_$]+)/],
    ['variable', /^\s*(?:var|let|const)\s+([A-Za-z0-9_$]+)\s*=/],
    ['constant', /^\s*define\(\s*['"]([^'"]+)['"]/],
    ['constant', /^\s*const\s+([A-Za-z0-9_]+)\s*=/],
  ];
  const result = [];
  lines.forEach((line, idx) => {
    for (const [kind, re] of patterns) {
      const m = line.match(re);
      if (!m) continue;
      result.push({
        kind,
        name: m[1],
        args: m[2] || '',
        line: idx + 1,
        signature: line.trim(),
        description: symbolDescription(m[1], kind, rel(file)),
      });
      break;
    }
  });
  return result;
}

function symbolDescription(name, kind, file) {
  if (kind === 'class') return `Класс ${name}: группирует состояние и поведение в файле ${file}.`;
  if (kind === 'constant') return `Константа ${name}: фиксированное значение конфигурации или режима.`;
  if (kind === 'variable') return variableDescription(name, file);
  const lower = name.toLowerCase();
  const prefix = file.includes('/kp/') || lower.includes('kp') ? 'КП/ПКП' :
    file.includes('documents') || lower.includes('document') ? 'документов' :
    file.includes('catalog') || lower.includes('catalog') ? 'каталога' :
    file.includes('orders') || lower.includes('order') ? 'комплектации' :
    file.includes('settings') || lower.includes('settings') ? 'настроек' :
    file.includes('users') || lower.includes('user') ? 'пользователей' : 'приложения';

  if (/^load|load/i.test(name)) return `Загружает данные для ${prefix}: обращается к API или кешу и подготавливает состояние для отрисовки.`;
  if (/^render|build.*html|html$/i.test(name)) return `Формирует HTML/разметку для ${prefix} и обновляет соответствующую часть интерфейса.`;
  if (/^save|sync/i.test(name)) return `Сохраняет или синхронизирует данные ${prefix} между интерфейсом, локальным состоянием, каталогом или базой.`;
  if (/^delete|remove/i.test(name)) return `Удаляет сущность или строку ${prefix}, обычно с проверкой прав и подтверждением.`;
  if (/^open|show/i.test(name)) return `Открывает модальное окно, страницу, выпадающий список или визуальное состояние ${prefix}.`;
  if (/^close|hide/i.test(name)) return `Закрывает или скрывает элемент интерфейса ${prefix}.`;
  if (/^get|find|pick/i.test(name)) return `Возвращает рассчитанное значение или ищет сущность ${prefix} по текущему состоянию/параметрам.`;
  if (/^set|apply|update/i.test(name)) return `Применяет изменение к состоянию или DOM ${prefix}.`;
  if (/^normalize|parse|decode|encode/i.test(name)) return `Нормализует, парсит или кодирует данные ${prefix} для безопасного хранения/передачи.`;
  if (/^validate|assert|can/i.test(name)) return `Проверяет корректность данных, права или допустимость действия для ${prefix}.`;
  if (/^collect/i.test(name)) return `Собирает данные ${prefix} из DOM или вложенной структуры в единый payload.`;
  if (/^calculate|calc|sum|total/i.test(name)) return `Выполняет расчет значений ${prefix}: суммы, итоги, маржу или служебные показатели.`;
  if (/^print|export|import/i.test(name)) return `Отвечает за печать, импорт или экспорт данных ${prefix}.`;
  if (/drag|drop|resize|pointer/i.test(lower)) return `Обрабатывает интерактивное перемещение, drop или изменение размеров в интерфейсе ${prefix}.`;
  return `Функция ${name}: вспомогательная логика участка ${prefix}. Точная точка входа указана в сигнатуре и строке файла.`;
}

function variableDescription(name, file) {
  const known = {
    CU: 'Текущий авторизованный пользователь.',
    CSRF_TOKEN: 'CSRF-токен для защищенных POST/DELETE запросов.',
    allCats: 'Справочник категорий каталога.',
    allSecs: 'Справочник разделов каталога.',
    allGroups: 'Справочник групп по разделам.',
    allSuppliers: 'Справочник поставщиков.',
    gcProducts: 'Текущий список карточек общего каталога.',
    orderList: 'Карточки комплектации для канбана.',
    kpClients: 'Список клиентов/заказчиков.',
    kpContractors: 'Список подрядчиков/исполнителей.',
    kpQuotes: 'Список КП/ПКП для канбана.',
    kpBuilder: 'Текущее состояние builder-а КП/ПКП.',
    documentsState: 'Текущее состояние конструктора документов.',
  };
  if (known[name]) return known[name];
  return `Глобальная переменная ${name}: хранит состояние или кеш, используемый модулем ${file}.`;
}

function parseSchema() {
  const schema = read(path.join(root, 'schema.sql'));
  const tables = [];
  for (const m of schema.matchAll(/CREATE TABLE `([^`]+)` \(([\s\S]*?)\) ENGINE/g)) {
    const columns = [];
    for (const c of m[2].matchAll(/^\s*`([^`]+)`\s+([^,\r\n]+)/gm)) {
      columns.push({ name: c[1], definition: c[2].trim(), description: columnDescription(c[1], c[2].trim()) });
    }
    tables.push({ name: m[1], description: tableDescription(m[1]), columns });
  }
  const foreignKeys = [];
  for (const m of schema.matchAll(/CONSTRAINT `([^`]+)` FOREIGN KEY \(`([^`]+)`\) REFERENCES `([^`]+)` \(`([^`]+)`\)([^,;]*)/g)) {
    foreignKeys.push({ name: m[1], column: m[2], ref: `${m[3]}.${m[4]}`, rule: m[5].trim() });
  }
  return { tables, foreignKeys };
}

function tableDescription(name) {
  return {
    users: 'Пользователи, роли, контакты и данные входа.',
    rop_managers: 'Связь РОП с менеджерами.',
    company_director: 'Назначенный директор компании из списка пользователей.',
    role_access_policies: 'JSON-политики доступа по ролям.',
    categories: 'Категории каталога.',
    sections: 'Разделы внутри категорий каталога.',
    catalog_groups: 'Группы товаров внутри разделов.',
    suppliers: 'Поставщики.',
    section_suppliers: 'Связь поставщиков с разделами.',
    measurement_units: 'Единицы измерения.',
    product_names: 'Карточки каталога товаров, расходов и комплектов.',
    products: 'Строки товаров в комплектации объекта.',
    catalog_services: 'Карточки работ и услуг.',
    product_service_links: 'Привязка товаров к автоработам.',
    kp_clients: 'Клиенты/заказчики.',
    kp_contractors: 'Подрядчики/исполнители.',
    company_profiles: 'Собственные компании и реквизиты.',
    kp_quotes: 'Коммерческие предложения.',
    pkp_quotes: 'Предварительные КП.',
    quote_payload_variants: 'Нормализованная сводка вариантов КП/ПКП.',
    quote_payload_items: 'Нормализованные позиции КП/ПКП.',
    orders: 'Карточки комплектации объекта.',
    order_invoices: 'PDF-счета комплектации.',
    documents_templates: 'Шаблоны документов.',
    documents_template_versions: 'Версии шаблонов документов.',
  }[name] || 'Служебная таблица.';
}

function columnDescription(name, definition) {
  const rules = [
    [/^id$/, 'Первичный идентификатор.'],
    [/^user_id$/, 'Владелец записи, users.id.'],
    [/^created_by$/, 'Пользователь, создавший запись.'],
    [/^created_at$/, 'Дата и время создания.'],
    [/^updated_at$/, 'Дата и время последнего изменения.'],
    [/^name$/, 'Название сущности.'],
    [/^code$/, 'Стабильный код для логики.'],
    [/^sort_order$/, 'Порядок сортировки.'],
    [/^status$/, 'Статус записи.'],
    [/^workflow_status$/, 'Статус карточки на канбане.'],
    [/^payload_json$/, 'Полный JSON-снимок структуры.'],
    [/^raw_json$/, 'Исходный JSON строки.'],
    [/^public_token$/, 'Публичный токен доступа.'],
    [/^client_id$/, 'Связанный клиент.'],
    [/^company_type$/, 'Тип компании.'],
    [/^company_name$/, 'Отображаемое название компании.'],
    [/^legal_name$/, 'Юридическое название.'],
    [/^inn$/, 'ИНН.'],
    [/^ogrn$/, 'ОГРН или ОГРНИП.'],
    [/^kpp$/, 'КПП.'],
    [/^phone$/, 'Телефон.'],
    [/^email$/, 'Email.'],
    [/^(address|object_address)$/, 'Адрес.'],
    [/^bank_/, 'Банковские реквизиты.'],
    [/^category_id$/, 'Категория каталога.'],
    [/^section_id$/, 'Раздел каталога.'],
    [/^group_name$/, 'Группа товара.'],
    [/^product_name_id$/, 'Карточка товара каталога.'],
    [/^service_id$/, 'Карточка работы/услуги.'],
    [/^(marking_size|marking|size_value)$/, 'Маркировка или размер.'],
    [/^quantity$/, 'Количество.'],
    [/^unit$/, 'Единица измерения.'],
    [/^supplier$/, 'Поставщик.'],
    [/^(purchase_price|cost)$/, 'Закупочная цена.'],
    [/^minimal_price$/, 'Минимальная цена.'],
    [/^(retail_price|final_price|base_price)$/, 'Розничная или итоговая цена.'],
    [/^(line_sum|total_sum|purchase_sum|margin_sum|margin_percent)$/, 'Расчетная сумма или маржа.'],
    [/^(note|technical_note)$/, 'Примечание.'],
  ];
  const match = rules.find(([re]) => re.test(name));
  return match ? match[1] : `Поле данных: ${definition}`;
}

function groupFiles(files) {
  const map = new Map();
  for (const file of files) {
    const key = folderKey(file);
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(file);
  }
  return [...map.entries()].sort((a, b) => a[0].localeCompare(b[0], 'ru'));
}

function symbolSummary(symbols) {
  const functions = symbols.filter((s) => s.kind === 'function');
  const vars = symbols.filter((s) => s.kind === 'variable' || s.kind === 'constant' || s.kind === 'class');
  return { functions, vars };
}

function renderFile(file) {
  const r = rel(file);
  const stat = fs.statSync(file);
  const symbols = extractSymbols(file);
  const { functions, vars } = symbolSummary(symbols);
  const meta = [
    `${(stat.size / 1024).toFixed(1)} КБ`,
    functions.length ? `${functions.length} функций` : '',
    vars.length ? `${vars.length} переменных/констант/классов` : '',
  ].filter(Boolean).join(' · ');

  return `
    <article class="file-card">
      <h3>${esc(r)}</h3>
      <p class="muted">${esc(meta || 'структурный файл')}</p>
      <p>${esc(filePurpose(file))}</p>
      ${vars.length ? `
        <h4>Состояние, константы и классы</h4>
        <div class="symbol-list">
          ${vars.map((s) => `<div><code>${esc(s.name)}</code><span>стр. ${s.line}</span><p>${esc(s.description)}</p></div>`).join('')}
        </div>` : ''}
      ${functions.length ? `
        <h4>Функции и методы файла</h4>
        <div class="symbol-list">
          ${functions.map((s) => `<div><code>${esc(s.name)}(${esc(s.args)})</code><span>стр. ${s.line}</span><p>${esc(s.description)}</p></div>`).join('')}
        </div>` : ''}
      ${!symbols.length ? '<p class="muted">В файле нет объявленных JS/PHP-функций. Он используется как разметка, стили, SQL или документация.</p>' : ''}
    </article>`;
}

function renderDatabase(schema) {
  return `
    <section class="section page-break" id="database">
      <div class="section-kicker">База данных</div>
      <h2>Схема, таблицы и связи</h2>
      <p>Ниже описаны таблицы из <code>schema.sql</code>, назначение полей и внешние ключи. Это текущая модель хранения каталога, КП/ПКП, комплектации, документов, пользователей и прав.</p>
      ${schema.tables.map((table) => `
        <article class="file-card db-card">
          <h3>${esc(table.name)}</h3>
          <p>${esc(table.description)}</p>
          <table>
            <thead><tr><th>Поле</th><th>SQL</th><th>Что хранит</th></tr></thead>
            <tbody>
              ${table.columns.map((c) => `<tr><td><code>${esc(c.name)}</code></td><td>${esc(c.definition)}</td><td>${esc(c.description)}</td></tr>`).join('')}
            </tbody>
          </table>
        </article>`).join('')}
      <article class="file-card">
        <h3>Внешние ключи</h3>
        <table>
          <thead><tr><th>Constraint</th><th>Поле</th><th>Ссылка</th><th>Правило</th></tr></thead>
          <tbody>
            ${schema.foreignKeys.map((fk) => `<tr><td><code>${esc(fk.name)}</code></td><td><code>${esc(fk.column)}</code></td><td><code>${esc(fk.ref)}</code></td><td>${esc(fk.rule || '—')}</td></tr>`).join('')}
          </tbody>
        </table>
      </article>
    </section>`;
}

function buildHtml() {
  const files = walk(root);
  const groups = groupFiles(files);
  const schema = parseSchema();
  const generatedAt = new Date().toLocaleString('ru-RU');
  const totalSymbols = files.flatMap(extractSymbols).length;

  return `<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <title>Документация проекта</title>
  <style>
    @page { size: A4; margin: 16mm 14mm; }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: "Segoe UI", Arial, sans-serif; color: #172033; background: #f4f7fb; font-size: 12px; line-height: 1.45; }
    .cover { min-height: 930px; padding: 42px; background: linear-gradient(135deg, #0f172a, #1d4ed8); color: #fff; display: flex; flex-direction: column; justify-content: space-between; border-radius: 24px; }
    .cover h1 { margin: 0; font-size: 42px; line-height: 1.05; letter-spacing: -1px; }
    .cover p { max-width: 620px; font-size: 16px; color: rgba(255,255,255,.86); }
    .cover-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; margin-top: 34px; }
    .metric { padding: 18px; border: 1px solid rgba(255,255,255,.18); border-radius: 18px; background: rgba(255,255,255,.08); }
    .metric b { display: block; font-size: 26px; }
    .metric span { color: rgba(255,255,255,.74); }
    .section { margin-top: 22px; padding: 22px; background: #fff; border: 1px solid #dbe4f0; border-radius: 18px; box-shadow: 0 10px 32px rgba(15,23,42,.08); }
    .page-break { page-break-before: always; }
    .section-kicker { color: #2563eb; text-transform: uppercase; font-weight: 800; font-size: 10px; letter-spacing: .12em; }
    h2 { margin: 4px 0 10px; color: #0f172a; font-size: 24px; letter-spacing: -.02em; }
    h3 { margin: 0 0 6px; color: #10203f; font-size: 17px; overflow-wrap: anywhere; }
    h4 { margin: 15px 0 7px; color: #334155; font-size: 12px; text-transform: uppercase; letter-spacing: .08em; }
    p { margin: 7px 0; }
    code { font-family: "Cascadia Mono", Consolas, monospace; background: #eef4ff; color: #1d4ed8; padding: 2px 5px; border-radius: 6px; }
    .muted { color: #64748b; }
    .toc { columns: 2; column-gap: 24px; padding-left: 18px; }
    .toc li { break-inside: avoid; margin: 4px 0; }
    .folder { page-break-before: always; }
    .folder-intro { padding: 16px; border-radius: 14px; background: #eff6ff; border: 1px solid #bfdbfe; margin: 12px 0 16px; }
    .file-card { page-break-inside: avoid; margin: 14px 0; padding: 16px; border: 1px solid #e2e8f0; border-radius: 16px; background: #fff; }
    .symbol-list { display: grid; gap: 8px; }
    .symbol-list > div { padding: 10px 12px; border: 1px solid #e7edf6; border-radius: 12px; background: #f8fbff; page-break-inside: avoid; }
    .symbol-list code { font-weight: 700; }
    .symbol-list span { float: right; color: #64748b; font-size: 10px; }
    .symbol-list p { clear: both; margin: 6px 0 0; color: #334155; }
    table { width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 10px; page-break-inside: auto; }
    tr { page-break-inside: avoid; }
    th { text-align: left; color: #0f172a; background: #eef4ff; border: 1px solid #dbe4f0; padding: 7px; }
    td { vertical-align: top; border: 1px solid #e2e8f0; padding: 7px; overflow-wrap: anywhere; }
    .db-card { page-break-inside: auto; }
    .flow { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }
    .flow div { padding: 13px; border-radius: 14px; background: #f8fbff; border: 1px solid #e2e8f0; }
    .small { font-size: 10px; }
  </style>
</head>
<body>
  <section class="cover">
    <div>
      <div class="section-kicker" style="color:#bfdbfe">Техническая документация</div>
      <h1>Документация проекта<br>CRM / Склад / КП</h1>
      <p>Структура проекта, назначение папок и файлов, функции, переменные, связи frontend/backend и подробная схема базы данных.</p>
      <div class="cover-grid">
        <div class="metric"><b>${files.length}</b><span>файлов описано</span></div>
        <div class="metric"><b>${totalSymbols}</b><span>функций и символов</span></div>
        <div class="metric"><b>${schema.tables.length}</b><span>таблиц БД</span></div>
      </div>
    </div>
    <div class="small">Сгенерировано: ${esc(generatedAt)} · Источник: текущая рабочая директория проекта</div>
  </section>

  <section class="section page-break">
    <div class="section-kicker">Оглавление</div>
    <h2>Как читать документ</h2>
    <p>Документ идет от общего к частному: сначала архитектура и потоки данных, затем папки, файлы и наполнение каждого файла. В конце находится база данных.</p>
    <ol class="toc">
      <li>Архитектура и потоки данных</li>
      ${groups.map(([key]) => `<li>${esc(key)}</li>`).join('')}
      <li>База данных</li>
    </ol>
  </section>

  <section class="section page-break">
    <div class="section-kicker">Архитектура</div>
    <h2>Как связаны части проекта</h2>
    <div class="flow">
      <div><h3>Frontend</h3><p>SPA на vanilla JS. Страницы подгружаются lazy-loader-ом. Глобальное состояние хранится в <code>app.state.js</code>, API-вызовы идут через <code>app.api.js</code>.</p></div>
      <div><h3>Backend</h3><p>PHP endpoint-файлы в <code>api/</code>. Общие проверки авторизации, прав, CSRF и JSON-ответов находятся в <code>includes/auth.php</code>.</p></div>
      <div><h3>Builder</h3><p>Один общий механизм таблиц категорий/разделов/строк используется в КП, ПКП и комплектации.</p></div>
      <div><h3>База</h3><p>MySQL/InnoDB. Справочники каталога нормализованы, КП/ПКП хранят полный JSON и дополнительные нормализованные строки для ускорения.</p></div>
    </div>
  </section>

  ${groups.map(([key, groupFiles]) => `
    <section class="section folder">
      <div class="section-kicker">Папка</div>
      <h2>${esc(key)}</h2>
      <div class="folder-intro">${esc(folderDescription(key))}</div>
      ${groupFiles.map(renderFile).join('')}
    </section>`).join('')}

  ${renderDatabase(schema)}
</body>
</html>`;
}

function findInstalledBrowser() {
  const candidates = [
    process.env.CHROME_PATH,
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  ].filter(Boolean);
  return candidates.find((candidate) => fs.existsSync(candidate)) || null;
}

async function main() {
  fs.mkdirSync(docsDir, { recursive: true });
  const html = buildHtml();
  fs.writeFileSync(htmlPath, html, 'utf8');

  const executablePath = findInstalledBrowser();
  const browser = await chromium.launch(executablePath ? { executablePath } : {});
  try {
    const page = await browser.newPage();
    await page.goto(`file://${htmlPath.replace(/\\/g, '/')}`, { waitUntil: 'load' });
    await page.pdf({
      path: pdfPath,
      format: 'A4',
      printBackground: true,
      preferCSSPageSize: true,
      margin: { top: '0mm', right: '0mm', bottom: '0mm', left: '0mm' },
    });
  } finally {
    await browser.close();
  }

  console.log(`Generated ${rel(htmlPath)}`);
  console.log(`Generated ${rel(pdfPath)}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
