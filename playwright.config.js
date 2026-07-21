const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './tests/e2e',
  timeout: 60000,
  expect: {
    timeout: 10000,
  },
  fullyParallel: false,
  retries: 0,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: 'http://127.0.0.1:8092',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'off',
    headless: true,
  },
  projects: [
    {
      name: 'edge',
      use: {
        ...devices['Desktop Edge'],
        channel: 'msedge',
      },
    },
  ],
  webServer: {
    command: `powershell -NoProfile -Command "$sessionPath='E:\\Program Files\\XAMPP\\htdocs\\test-results\\sessions'; New-Item -ItemType Directory -Force -Path $sessionPath | Out-Null; $env:DB_HOST='localhost'; $env:DB_NAME='kompl_test'; $env:DB_USER='root'; $env:DB_PASS=''; & 'E:\\Program Files\\XAMPP\\php\\php.exe' -d session.save_path=$sessionPath -S 127.0.0.1:8092 -t 'E:\\Program Files\\XAMPP\\htdocs'"`,
    url: 'http://127.0.0.1:8092',
    reuseExistingServer: true,
    timeout: 30000,
  },
});
