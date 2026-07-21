const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const rootDir = path.resolve(__dirname, '..', '..');
const ignoredDirs = new Set([
  '.git',
  'node_modules',
  'vendor',
  'uploads',
  'playwright-report',
  'test-results',
  '_restore',
  '_cmp_ud11',
]);
const checkedExtensions = new Set(['.php', '.js', '.css', '.html', '.sql', '.ps1', '.md']);
const mojibakePattern = new RegExp([
  '\u0420\u040e',
  '\u0420\u045f',
  '\u0420\u00a0',
  '\u0420\u201d',
  '\u0420\u045e',
  '\u0420\u00b0',
  '\u0420\u00b1',
  '\u0420\u00b5',
  '\u0420\u0451',
  '\u0420\u0454',
  '\u0420\u00bb',
  '\u0420\u0405',
  '\u0420\u0455',
  '\u0421\u0453',
  '\u0421\u201a',
  '\u0421\u2020',
  '\u0421\u2039',
  '\u0432\u045c',
  '\u0440\u045f',
].join('|'));

function collectTextFiles(dir, result = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!ignoredDirs.has(entry.name)) collectTextFiles(path.join(dir, entry.name), result);
      continue;
    }
    if (entry.isFile() && checkedExtensions.has(path.extname(entry.name).toLowerCase())) {
      result.push(path.join(dir, entry.name));
    }
  }
  return result;
}

test('project text files do not contain mojibake literals', () => {
  const offenders = [];
  for (const file of collectTextFiles(rootDir)) {
    const text = fs.readFileSync(file, 'utf8');
    const lines = text.split(/\r?\n/);
    lines.forEach((line, index) => {
      if (mojibakePattern.test(line)) {
        offenders.push(`${path.relative(rootDir, file)}:${index + 1}: ${line.trim()}`);
      }
    });
  }
  expect(offenders, offenders.join('\n')).toEqual([]);
});

test('esc escapes HTML-sensitive characters', () => {
  const helpersPath = path.join(rootDir, 'assets', 'js', 'app.helpers.js');
  const source = fs.readFileSync(helpersPath, 'utf8');
  const context = {
    debTimers: {},
    document: {
      getElementById: () => ({ appendChild() {}, addEventListener() {} }),
      addEventListener() {},
    },
    window: { addEventListener() {} },
    MutationObserver: function MutationObserver() {
      return { observe() {}, disconnect() {} };
    },
    init() {},
    setTimeout() {},
  };
  vm.createContext(context);
  vm.runInContext(source, context, { filename: helpersPath });

  expect(context.esc(`<script>alert("x")</script>&'`)).toBe(
    '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;&amp;&#39;'
  );
});
