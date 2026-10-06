# Итерация 08. Несколько директоров и организаций

Закрытый endpoint `POST /api/v1/auth/bootstrap/director` (заголовок
`X-Bootstrap-Token` = `BOOTSTRAP_TOKEN` из `.env`) больше не ограничен первым
пользователем: он создаёт директора, если логин свободен. Каждый директор
после первого входа (смена временного пароля, TOTP) создаёт свою организацию и
проходит первичную настройку; организации изолированы схемами
`tenant_<uuid>`.

- Тело: `{ "login", "displayName", "temporaryPassword" }` (пароль — по
  `PasswordPolicy`, логин 3–100 символов).
- Логин уникален во всей системе без учёта регистра: занятый — 409
  `bootstrap_login_taken` (и при гонке двух запросов — по уникальному индексу).
- Неверный или отсутствующий токен — 404, как у несуществующего адреса.
  Токен теперь действует постоянно: хранить его как пароль администратора.
- Один пользователь — одна организация: повторное создание — 409
  `onboarding_completed`.

Пример (PowerShell):

```powershell
Invoke-RestMethod -Method Post -Uri http://localhost:8080/api/v1/auth/bootstrap/director `
  -Headers @{ 'X-Bootstrap-Token' = '<BOOTSTRAP_TOKEN>' } -ContentType 'application/json; charset=utf-8' `
  -Body '{"login":"director2","displayName":"Иванов Иван","temporaryPassword":"Временный-пароль-123!"}'
```

Регрессия: `DatabaseRegressionTests.SeveralDirectorsCreateIsolatedOrganizations`
— два директора в одной базе, отказ повторного логина и запроса без токена,
вторая организация не создаётся, клиенты, канбаны и профиль не видны другой
организации.
