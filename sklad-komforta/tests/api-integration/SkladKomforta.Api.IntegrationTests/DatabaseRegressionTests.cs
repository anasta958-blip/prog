using System.Buffers.Binary;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Npgsql;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Api.IntegrationTests;

public sealed partial class DatabaseRegressionTests
{
    [DatabaseFact]
    public async Task OrganizationCatalogKanbanAndClientQuoteWorkAgainstRealDatabase()
    {
        await using var database = await RegressionDatabase.CreateAsync();
        await using var factory = new RegressionFactory(database.ConnectionString);
        using var staff = factory.CreateClient();
        await Send(staff, HttpMethod.Post, "/auth/login", new { login = (string?)null, password = (string?)null }, HttpStatusCode.BadRequest);
        staff.DefaultRequestHeaders.Add("X-Bootstrap-Token", RegressionFactory.BootstrapToken);
        await Send(staff, HttpMethod.Post, "/auth/bootstrap/director", new
        {
            login = "regression-director",
            displayName = "Проверка проекта",
            temporaryPassword = "Regression-test-123!",
        });
        staff.DefaultRequestHeaders.Remove("X-Bootstrap-Token");
        var login = await Send(staff, HttpMethod.Post, "/auth/login", new
        {
            login = "regression-director", password = "Regression-test-123!", deviceType = 2,
        });
        var changed = await Send(staff, HttpMethod.Post, "/auth/initial-password", new
        {
            challengeToken = Text(login, "challengeToken"), newPassword = "Regression-final-456!",
        });
        var challenge = Text(changed, "challengeToken");
        var totp = await Send(staff, HttpMethod.Post, "/auth/totp/setup", new { challengeToken = challenge });
        var authenticated = await Send(staff, HttpMethod.Post, "/auth/totp/confirm", new
        {
            challengeToken = challenge, code = Totp(Text(totp, "secret")),
        });
        staff.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer", Text(authenticated["tokens"]!, "accessToken"));
        var organization = await Send(staff, HttpMethod.Post, "/identity/organization", new { name = "Проверка проекта" });
        staff.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Text(organization, "accessToken"));

        var firstCompany = new SaveLegalEntityRequest(
            "Первое юрлицо", "ooo", "ООО Первое юрлицо", "7707083893", "773601001",
            "1027700132195", "Москва", "+79991234567", null, null,
            "Иванов Иван", "Иванов Иван", "Директор", "Тестовый банк", "044525225",
            "40702810900000000001", "30101810400000000225", null, null, [null, 0, 20], true);
        var draft = Draft();
        draft = draft with { Company = draft.Company with { LegalEntity = firstCompany } };
        await Send(staff, HttpMethod.Post, "/onboarding/draft", draft);
        await Send(staff, HttpMethod.Post, "/onboarding/activate");
        await Send(staff, HttpMethod.Post, "/onboarding/activate");
        var firstCompanies = (await Send(staff, HttpMethod.Get, "/company/legal-entities")).AsArray();
        Assert.Single(firstCompanies);
        Assert.Equal(firstCompany.Name, Text(firstCompanies[0]!, "name"));
        Assert.Equal(firstCompany.BankAccount, Text(firstCompanies[0]!, "bankAccount"));
        Assert.True(firstCompanies[0]!["isDefault"]!.GetValue<bool>());
        Assert.Equal(3, firstCompanies[0]!["vatRates"]!.AsArray().Count);
        await using (var schemaConnection = new NpgsqlConnection(database.ConnectionString))
        {
            await schemaConnection.OpenAsync();
            await using var profileTables = new NpgsqlCommand("""
                SELECT count(*) FROM information_schema.tables
                WHERE table_schema LIKE 'tenant_%'
                  AND table_name IN ('organization_profile', 'organization_profile_legacy')
                """, schemaConnection);
            Assert.Equal(0L, await profileTables.ExecuteScalarAsync());
        }
        var workspaceProfile = await Send(staff, HttpMethod.Get, "/company/profile");
        foreach (var clientType in new[] { "person", "ip", "ooo" })
        {
            var emptyClient = new { name = clientType == "person" ? "" : "Test", companyType = clientType };
            var client = await Send(staff, HttpMethod.Post, "/company/clients", emptyClient);
            Assert.Equal(emptyClient.name, Text(client, "name"));
            var clientPath = $"/company/clients/{Text(client, "id")}";
            await Send(staff, HttpMethod.Put, clientPath, emptyClient);
            await Send(staff, HttpMethod.Delete, clientPath);
        }
        Assert.Single(workspaceProfile.AsObject());
        var initialConfiguration = await Send(staff, HttpMethod.Get, "/company/configuration");
        Assert.Single(initialConfiguration["company"]!.AsObject());
        // Старая конфигурация не может перезаписать реквизиты или название пространства.
        var savedConfiguration = await Send(staff, HttpMethod.Put, "/company/configuration", new
        {
            draft = draft with { Company = draft.Company with { OrganizationName = "Устаревшее название" } },
            deleteCategoryData = Array.Empty<string>(),
        });
        Assert.Equal("Проверка проекта", Text(savedConfiguration["company"]!, "organizationName"));
        Assert.Single(savedConfiguration["company"]!.AsObject());
        var unchangedCompany = (await Send(staff, HttpMethod.Get, "/company/legal-entities")).AsArray()[0]!;
        Assert.Equal(firstCompany.BankAccount, Text(unchangedCompany, "bankAccount"));
        // Переименование рабочего пространства не меняет юрлицо.
        await Send(staff, HttpMethod.Put, "/company/profile", new { organizationName = "Новое рабочее пространство" });
        Assert.Equal(firstCompany.Name, Text((await Send(staff, HttpMethod.Get, "/company/legal-entities")).AsArray()[0]!, "name"));
        await Send(staff, HttpMethod.Put, "/company/profile", new { organizationName = "Проверка проекта" });
        foreach (var path in new[]
        {
            "/company/profile", "/company/configuration", "/company/lifecycle",
            "/company/legal-entities", "/company/clients", "/company/employees", "/company/audit",
            "/settings/access/roles", "/identity/sessions", "/catalog/configuration", "/kanbans/card-authors",
        }) await Send(staff, HttpMethod.Get, path);

        var permissions = await Send(staff, HttpMethod.Get, "/settings/access/permissions");
        foreach (var permission in permissions.AsArray())
        {
            Assert.DoesNotContain("?", Text(permission!, "name"), StringComparison.Ordinal);
            Assert.DoesNotContain("?", Text(permission!, "groupName"), StringComparison.Ordinal);
        }
        var roleRequest = new { name = "Просмотр каталога", permissionCodes = (string[])["catalog.view"], subordinateRoleIds = Array.Empty<string>(), cardVisibilityMode = "own" };
        var role = await Send(staff, HttpMethod.Post, "/settings/access/roles", roleRequest);
        var roleId = Text(role, "id");
        var auditBeforeRoleSave = (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray().Count;
        await Send(staff, HttpMethod.Put, $"/settings/access/roles/{roleId}", roleRequest);
        Assert.Equal(auditBeforeRoleSave, (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray().Count);
        await Send(staff, HttpMethod.Get, "/settings/access/members");

        var employeeRole = await Send(staff, HttpMethod.Post, "/settings/access/roles", new
        {
            name = "Проверка пароля сотрудника", permissionCodes = (string[])["catalog.view"],
            subordinateRoleIds = Array.Empty<string>(), cardVisibilityMode = "own",
        });
        var employee = await Send(staff, HttpMethod.Post, "/company/employees", new
        {
            login = "password-test-employee", displayName = "Проверка пароля", temporaryPassword = "Employee-start-123!",
            roleId = Text(employeeRole, "id"), supervisorMembershipId = (string?)null,
        });
        var employeePath = $"/company/employees/{Text(employee, "membershipId")}";
        using var employeeClient = factory.CreateClient();
        var employeeLogin = await Send(employeeClient, HttpMethod.Post, "/auth/login", new
        {
            login = "password-test-employee", password = "Employee-start-123!", deviceType = 2,
        });
        var employeeChanged = await Send(employeeClient, HttpMethod.Post, "/auth/initial-password", new
        {
            challengeToken = Text(employeeLogin, "challengeToken"), newPassword = "Employee-before-123!",
        });
        var employeeChallenge = Text(employeeChanged, "challengeToken");
        var employeeTotp = await Send(employeeClient, HttpMethod.Post, "/auth/totp/setup", new { challengeToken = employeeChallenge });
        var employeeAuthenticated = await Send(employeeClient, HttpMethod.Post, "/auth/totp/confirm", new
        {
            challengeToken = employeeChallenge, code = Totp(Text(employeeTotp, "secret")),
        });
        employeeClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Text(employeeAuthenticated["tokens"]!, "accessToken"));
        var employeeOnboarding = await Send(employeeClient, HttpMethod.Get, "/onboarding/status");
        Assert.True(employeeOnboarding["isCompleted"]!.GetValue<bool>());
        Assert.Null(employeeOnboarding["draft"]);
        await Send(employeeClient, HttpMethod.Get, "/onboarding/", expected: HttpStatusCode.Forbidden);
        await Send(employeeClient, HttpMethod.Post, employeePath + "/password", new { newPassword = "Employee-denied-123!" }, HttpStatusCode.Forbidden);
        await Send(staff, HttpMethod.Post, employeePath + "/password", new { newPassword = "short" }, HttpStatusCode.BadRequest);
        await Send(staff, HttpMethod.Post, $"/company/employees/{Guid.NewGuid()}/password", new { newPassword = "Employee-after-456!" }, HttpStatusCode.NotFound);
        var pendingLogin = await Send(employeeClient, HttpMethod.Post, "/auth/login", new
        {
            login = "password-test-employee", password = "Employee-before-123!", deviceType = 2,
        });
        await Send(staff, HttpMethod.Post, employeePath + "/password", new { newPassword = "Employee-after-456!" });
        await Send(employeeClient, HttpMethod.Get, "/catalog/configuration", expected: HttpStatusCode.Forbidden);
        employeeClient.DefaultRequestHeaders.Authorization = null;
        await Send(employeeClient, HttpMethod.Post, "/auth/totp/verify", new
        {
            challengeToken = Text(pendingLogin, "challengeToken"), code = Totp(Text(employeeTotp, "secret")),
        }, HttpStatusCode.Unauthorized);
        await Send(employeeClient, HttpMethod.Post, "/auth/login", new
        {
            login = "password-test-employee", password = "Employee-before-123!", deviceType = 2,
        }, HttpStatusCode.Unauthorized);
        var resetLogin = await Send(employeeClient, HttpMethod.Post, "/auth/login", new
        {
            login = "password-test-employee", password = "Employee-after-456!", deviceType = 2,
        });
        Assert.Equal(3, resetLogin["step"]!.GetValue<int>());
        var resetAudit = (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray()
            .Single(value => Text(value!, "action") == "password_changed")!;
        Assert.DoesNotContain("Employee-after-456!", resetAudit.ToJsonString());
        Assert.DoesNotContain("password_hash", resetAudit.ToJsonString());
        object QuotaEmployee(int number) => new {
            login = $"quota-employee-{number}", displayName = $"Сотрудник {number}",
            temporaryPassword = "Employee-start-123!", roleId = Text(employeeRole, "id"),
        };
        for (var number = 1; number <= 3; number++)
            await Send(staff, HttpMethod.Post, "/company/employees", QuotaEmployee(number));
        var quotaResponses = await Task.WhenAll(Enumerable.Range(4, 2).Select(number =>
            staff.PostAsJsonAsync("/api/v1/company/employees", QuotaEmployee(number))));
        Assert.Single(quotaResponses, response => response.StatusCode == HttpStatusCode.OK);
        Assert.Single(quotaResponses, response => response.StatusCode == HttpStatusCode.Conflict);
        foreach (var response in quotaResponses) response.Dispose();
        var quotaStatus = await Send(staff, HttpMethod.Get, "/company/lifecycle");
        Assert.Equal(5, quotaStatus["employeeLimit"]!.GetValue<int>());
        Assert.Equal(5, quotaStatus["employeeCount"]!.GetValue<int>());
        await Send(staff, HttpMethod.Delete, employeePath);
        await Send(staff, HttpMethod.Post, "/company/employees", QuotaEmployee(6));

        var roundtrip = await Send(staff, HttpMethod.Put, "/company/configuration", new { draft, deleteCategoryData = Array.Empty<string>() });
        Assert.Single(roundtrip["rules"]!.AsArray());
        Assert.Single(roundtrip["moneyPipelines"]!.AsArray());
        var auditBeforeConfigurationSave = (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray().Count;
        await Send(staff, HttpMethod.Put, "/company/configuration", new { draft, deleteCategoryData = Array.Empty<string>() });
        Assert.Equal(auditBeforeConfigurationSave, (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray().Count);
        Assert.Contains((await Send(staff, HttpMethod.Get, "/settings/access/roles")).AsArray(), value => Text(value!, "id") == roleId);
        await Send(staff, HttpMethod.Delete, $"/settings/access/roles/{roleId}");

        var configuration = await Send(staff, HttpMethod.Get, "/catalog/configuration");
        var category = configuration["categories"]![0]!;
        var categoryId = Text(category, "id");
        var sectionId = Text(category["sections"]![0]!, "id");
        var unitId = Text(configuration["dictionaries"]![0]!["items"]![0]!, "id");
        var productRequest = new
        {
            categoryId, sectionId, name = "Кондиционер", marking = "AC-24", status = "approved",
            values = new Dictionary<string, object> { ["unit"] = unitId, ["base_price"] = 10000m },
        };
        var product = await Send(staff, HttpMethod.Post, "/catalog/items", productRequest);
        var productId = Text(product, "id");
        // Товар может лежать прямо в категории, без раздела.
        var directProduct = await Send(staff, HttpMethod.Post, "/catalog/items", new
        {
            categoryId, sectionId = (string?)null, groupId = (string?)null, name = "Расходник без раздела", marking = "", status = "approved",
            values = new Dictionary<string, object> { ["unit"] = unitId, ["base_price"] = 100m },
        });
        Assert.True(directProduct["sectionId"] is null);
        await Send(staff, HttpMethod.Delete, $"/catalog/items/{Text(directProduct, "id")}");
        var auditBeforeProductSave = (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray().Count;
        await Send(staff, HttpMethod.Put, $"/catalog/items/{productId}", productRequest);
        Assert.Equal(auditBeforeProductSave, (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray().Count);
        await Send(staff, HttpMethod.Get, $"/catalog/items/{productId}");
        Assert.Equal(1, (await Send(staff, HttpMethod.Get, "/catalog/items"))["total"]!.GetValue<int>());
        await CheckBulkRelations(staff, configuration, productId, productRequest, unitId);

        // Пространство «Компания» тоже рассылает сигналы с указанием раздела.
        var companyTicket = Text(await Send(staff, HttpMethod.Post, "/company/realtime-ticket"), "ticket");
        await using var companyEvents = await RealtimeListener.ConnectAsync(factory, companyTicket);
        var company = await Send(staff, HttpMethod.Post, "/company/legal-entities", new
        {
            name = "Исполнитель", companyType = "ООО", legalName = "ООО Исполнитель",
            inn = "7707083893", kpp = "773601001", ogrn = "1027700132195", phone = "+79991234567",
            directorName = "Иванов Иван", signatoryName = "Иванов Иван", signatoryTitle = "Директор",
            bankName = "Тестовый банк", bankBik = "044525225", bankAccount = "40702810900000000001",
            corrAccount = "30101810400000000225", vatRates = new decimal?[] { null, 0, 20 }, isDefault = true,
        });
        var customer = await Send(staff, HttpMethod.Post, "/company/clients", new
        {
            name = "Иванов Иван", companyName = "Иванов Иван", companyType = "person", phone = "+79997654321",
            passportSeries = "1234", passportNumber = "123456", passportIssuedBy = "Тестовый отдел",
        });
        var legalEntityChange = await companyEvents.WaitAsync(message => (string?)message["section"] == "legal_entities");
        Assert.Equal("company", (string?)legalEntityChange["topic"]);
        await companyEvents.WaitAsync(message => (string?)message["section"] == "clients");

        var boards = await Send(staff, HttpMethod.Get, "/kanbans/");
        var boardId = Text(boards[0]!, "id");
        var board = await Send(staff, HttpMethod.Get, $"/kanbans/{boardId}");
        var columnId = Text(board["columns"]![0]!, "id");
        var targetColumnId = Text(board["columns"]![1]!, "id");
        Assert.Equal(2, board["columns"]![0]!["creationActions"]!.AsArray().Count);
        Assert.NotEmpty(board["categories"]![0]!["fields"]!.AsArray());

        // Уведомления в реальном времени: одноразовый билет, сигнал без данных.
        var catalogTicket = Text(await Send(staff, HttpMethod.Post, "/catalog/realtime-ticket"), "ticket");
        await using var catalogEvents = await RealtimeListener.ConnectAsync(factory, catalogTicket);
        await RealtimeListener.ExpectRejectedAsync(factory, catalogTicket);
        await Send(staff, HttpMethod.Put, $"/catalog/items/{productId}", productRequest);
        var catalogChange = await catalogEvents.WaitAsync(message => (string?)message["kind"] == "changed");
        Assert.Equal("catalog", (string?)catalogChange["topic"]);
        Assert.Equal(productId, (string?)catalogChange["entityId"]);
        var kanbanTicket = Text(await Send(staff, HttpMethod.Post, "/kanbans/realtime-ticket"), "ticket");
        await using var kanbanEvents = await RealtimeListener.ConnectAsync(factory, kanbanTicket);
        bool KanbanChange(JsonNode message, string cardId) =>
            (string?)message["topic"] == "kanban" &&
            (string?)message["kind"] == "changed" &&
            ((string?)message["boardId"] == boardId || message["boardId"] is null) &&
            (string?)message["entityId"] == cardId;

        foreach (var kind in new[] { "quote", "prequote" })
        {
            var proposal = QuoteRequest(kind, Text(customer, "id"), Text(company, "id"), categoryId, sectionId, productId);
            var older = await Send(staff, HttpMethod.Post, $"/kanbans/{boardId}/quotes", new { columnId, quote = proposal });
            var created = await Send(staff, HttpMethod.Post, $"/kanbans/{boardId}/quotes", new { columnId, quote = proposal });
            var cardId = Text(created, "cardId");
            var orderedCards = (await Send(staff, HttpMethod.Get, $"/kanbans/{boardId}/cards?columnId={columnId}"))["items"]!.AsArray();
            Assert.Equal(cardId, Text(orderedCards[0]!, "id"));
            Assert.Equal(Text(older, "cardId"), Text(orderedCards[1]!, "id"));
            await Send(staff, HttpMethod.Delete, $"/kanbans/{boardId}/cards/{Text(older, "cardId")}");
            var path = $"/kanbans/{boardId}/cards/{cardId}";
            var quotePath = path + "/quote";
            var saved = await Send(staff, HttpMethod.Get, quotePath);
            Assert.Equal(23760m, saved["proposalTypes"]![0]!["variants"]![0]!["categories"]![0]!["sections"]![0]!["positions"]![0]!["lineTotal"]!.GetValue<decimal>());
            var positionValues = saved["proposalTypes"]![0]!["variants"]![0]!["categories"]![0]!["sections"]![0]!["positions"]![0]!["values"]!;
            Assert.Equal("Проверено правилом", Text(positionValues, "custom_note"));
            Assert.Equal(23760m, positionValues["custom_total"]!.GetValue<decimal>());
            await Send(staff, HttpMethod.Put, quotePath, proposal);
            var moved = await Send(staff, HttpMethod.Post, path + "/move", new { targetColumnId, targetIndex = 0 });
            Assert.Equal(targetColumnId, Text(moved, "columnId"));
            await kanbanEvents.WaitAsync(message => KanbanChange(message, cardId));
            // Перенос записывается отдельно («Статус изменил») и не считается правкой.
            Assert.NotNull(moved["movedByName"]);
            Assert.True(moved["updatedAt"]!.GetValue<DateTimeOffset>() < moved["movedAt"]!.GetValue<DateTimeOffset>());
            await Send(staff, HttpMethod.Get, $"/kanbans/{boardId}/cards?columnId={targetColumnId}");
            var beforeArchive = await Send(staff, HttpMethod.Get, quotePath);
            var archived = await Send(staff, HttpMethod.Post, path + "/archive", new { archived = true });
            Assert.True(archived["isArchived"]!.GetValue<bool>());
            Assert.Empty((await Send(staff, HttpMethod.Get, $"/kanbans/{boardId}/cards?columnId={targetColumnId}"))["items"]!.AsArray());
            var archivePage = await Send(staff, HttpMethod.Get, $"/kanbans/{boardId}/cards?columnId={targetColumnId}&archived=true");
            Assert.Equal(cardId, Text(archivePage["items"]![0]!, "id"));
            Assert.True(JsonNode.DeepEquals(beforeArchive, await Send(staff, HttpMethod.Get, quotePath)));
            await Send(staff, HttpMethod.Post, path + "/move", new { targetColumnId, targetIndex = 0 }, HttpStatusCode.Conflict);
            var auditCount = (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray().Count;
            await Send(staff, HttpMethod.Post, path + "/archive", new { archived = true });
            Assert.Equal(auditCount, (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray().Count);
            var restored = await Send(staff, HttpMethod.Post, path + "/archive", new { archived = false });
            Assert.False(restored["isArchived"]!.GetValue<bool>());
            Assert.Equal(targetColumnId, Text(restored, "columnId"));
            Assert.True(JsonNode.DeepEquals(beforeArchive, await Send(staff, HttpMethod.Get, quotePath)));
            Assert.Empty((await Send(staff, HttpMethod.Get, $"/kanbans/{boardId}/cards?columnId={targetColumnId}&archived=true"))["items"]!.AsArray());
            using var pdf = await staff.GetAsync("/api/v1" + quotePath + "/pdf");
            Assert.Equal(HttpStatusCode.OK, pdf.StatusCode);
            Assert.Equal("application/pdf", pdf.Content.Headers.ContentType?.MediaType);
            Assert.True((await pdf.Content.ReadAsByteArrayAsync()).Length > 1000);
            var savedQuote = await Send(staff, HttpMethod.Get, quotePath);
            var printedTypeId = Text(savedQuote["proposalTypes"]![0]!, "id");
            var printedVariantId = Text(savedQuote["proposalTypes"]![0]!["variants"]![0]!, "id");
            using var variantPdf = await staff.GetAsync(
                $"/api/v1{quotePath}/pdf?proposalTypeId={printedTypeId}&variantId={printedVariantId}");
            Assert.Equal(HttpStatusCode.OK, variantPdf.StatusCode);
            Assert.Equal("application/pdf", variantPdf.Content.Headers.ContentType?.MediaType);
            using var typePdf = await staff.GetAsync(
                $"/api/v1{quotePath}/pdf?proposalTypeId={printedTypeId}");
            Assert.Equal(HttpStatusCode.OK, typePdf.StatusCode);
            Assert.Equal("application/pdf", typePdf.Content.Headers.ContentType?.MediaType);
            using var missingTypePdf = await staff.GetAsync(
                $"/api/v1{quotePath}/pdf?proposalTypeId={Guid.NewGuid()}");
            Assert.Equal(HttpStatusCode.NotFound, missingTypePdf.StatusCode);
            using var missingVariantPdf = await staff.GetAsync(
                $"/api/v1{quotePath}/pdf?proposalTypeId={printedTypeId}&variantId={Guid.NewGuid()}");
            Assert.Equal(HttpStatusCode.NotFound, missingVariantPdf.StatusCode);

            var link = await Send(staff, HttpMethod.Post, quotePath + "/client-access", new { lifetimeDays = 7 });
            // Повторное открытие окна возвращает те же токен и пароль и пишет просмотр в аудит.
            var auditBeforeReveal = (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray().Count;
            var reopened = await Send(staff, HttpMethod.Get, quotePath + "/client-access");
            Assert.True(reopened["isActive"]!.GetValue<bool>());
            Assert.Equal(Text(link, "accessToken"), Text(reopened, "accessToken"));
            Assert.Equal(Text(link, "password"), Text(reopened, "password"));
            var auditAfterReveal = (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray();
            Assert.Equal(auditBeforeReveal + 1, auditAfterReveal.Count);
            Assert.Contains(auditAfterReveal, entry => Text(entry!, "action") == "client_link_secret_viewed");
            await Send(staff, HttpMethod.Post, quotePath + "/client-access/extend", new { additionalDays = 0 }, HttpStatusCode.BadRequest);
            var extended = await Send(staff, HttpMethod.Post, quotePath + "/client-access/extend", new { additionalDays = 3 });
            Assert.Equal(Text(link, "accessToken"), Text(extended, "accessToken"));
            Assert.Equal(Text(link, "password"), Text(extended, "password"));
            Assert.Equal(DateTimeOffset.Parse(Text(reopened, "expiresAt"), System.Globalization.CultureInfo.InvariantCulture).AddDays(3), DateTimeOffset.Parse(Text(extended, "expiresAt"), System.Globalization.CultureInfo.InvariantCulture));
            await using (var expiryConnection = new NpgsqlConnection(database.ConnectionString))
            {
                await expiryConnection.OpenAsync();
                await using var expire = new NpgsqlCommand("UPDATE public.quote_client_access_links SET created_at = now() - interval '2 days', expires_at = now() - interval '1 second' WHERE quote_id = @id AND revoked_at IS NULL", expiryConnection);
                expire.Parameters.AddWithValue("id", Guid.Parse(Text(saved, "id")));
                await expire.ExecuteNonQueryAsync();
            }
            var expiredStatus = await Send(staff, HttpMethod.Get, quotePath + "/client-access");
            Assert.False(expiredStatus["isActive"]!.GetValue<bool>());
            var renewed = await Send(staff, HttpMethod.Post, quotePath + "/client-access/extend", new { additionalDays = 7 });
            Assert.True(renewed["isActive"]!.GetValue<bool>());
            Assert.Equal(Text(link, "accessToken"), Text(renewed, "accessToken"));
            Assert.Equal(Text(link, "password"), Text(renewed, "password"));
            using var guest = factory.CreateClient();
            await Send(guest, HttpMethod.Post, "/client/quotes/login", new
            {
                accessToken = Text(link, "accessToken"), password = "wrong-password",
            }, HttpStatusCode.Unauthorized);
            var clientLogin = await Send(guest, HttpMethod.Post, "/client/quotes/login", new
            {
                accessToken = Text(link, "accessToken"), password = Text(link, "password"),
            });
            // Просмотр ссылки клиентом сразу виден сотрудникам.
            await kanbanEvents.WaitAsync(message => KanbanChange(message, cardId));
            guest.DefaultRequestHeaders.Add("X-Quote-Client-Session", Text(clientLogin, "sessionToken"));
            var clientQuote = await Send(guest, HttpMethod.Get, "/client/quotes/current");
            Assert.Equal("ООО Исполнитель", Text(clientQuote, "executorName"));
            Assert.Equal("Иванов Иван", Text(clientQuote, "clientName"));
            Assert.Equal(2, clientQuote["proposalTypes"]!.AsArray().Count);
            Assert.DoesNotContain("purchasePrice", clientQuote.ToJsonString(), StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("markupPercent", clientQuote.ToJsonString(), StringComparison.OrdinalIgnoreCase);
            await Send(guest, HttpMethod.Get, "/company/clients", expected: HttpStatusCode.Unauthorized);
            await Send(guest, HttpMethod.Put, "/client/quotes/current/selection", new { variants = Array.Empty<object>() }, HttpStatusCode.BadRequest);
            var typeId = Text(clientQuote["proposalTypes"]![0]!, "id");
            var variantId = Text(clientQuote["proposalTypes"]![0]!["variants"]![0]!, "id");
            var typeMode = kind == "prequote";
            var selected = await Send(guest, HttpMethod.Put, "/client/quotes/current/selection", new
            {
                proposalTypeId = typeMode ? typeId : null,
                variants = typeMode ? [] : new[] { new { proposalTypeId = typeId, variantId } },
            });
            Assert.NotNull(selected["selectionSubmittedAt"]);
            await kanbanEvents.WaitAsync(message => KanbanChange(message, cardId));
            var auditBeforeResubmission = (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray().Count;
            await Send(guest, HttpMethod.Put, "/client/quotes/current/selection", new
            {
                proposalTypeId = typeMode ? typeId : null,
                variants = typeMode ? [] : new[] { new { proposalTypeId = typeId, variantId } },
            });
            Assert.Equal(auditBeforeResubmission, (await Send(staff, HttpMethod.Get, "/company/audit")).AsArray().Count);
            var employeeView = await Send(staff, HttpMethod.Get, quotePath);
            if (typeMode)
                Assert.Equal(typeId, Text(employeeView, "clientSelectedProposalTypeId"));
            else
            {
                Assert.True(employeeView["proposalTypes"]![0]!["selectedByClient"]!.GetValue<bool>());
                Assert.Equal(variantId, Text(employeeView["proposalTypes"]![0]!, "selectedVariantId"));
            }

            // Сводка КП на карточке канбана: стороны, выбор с суммой и просмотры ссылки.
            var columnPage = await Send(staff, HttpMethod.Get,
                $"/kanbans/{boardId}/cards?columnId={targetColumnId}");
            Assert.Equal(28512m, columnPage["selectedTotal"]!.GetValue<decimal>());
            var cardWithQuote = columnPage["items"]!
                .AsArray().Single(item => Text(item!, "id") == cardId)!;

            // Поиск по подстроке названия и по номеру; итог столбца учитывает поиск.
            var number = cardWithQuote["number"]!.GetValue<long>();
            foreach (var search in new[] { "тестовое", $"%23{number}", number.ToString(System.Globalization.CultureInfo.InvariantCulture) })
            {
                var found = await Send(staff, HttpMethod.Get,
                    $"/kanbans/{boardId}/cards?columnId={targetColumnId}&search={search}");
                Assert.Contains(found["items"]!.AsArray(), item => Text(item!, "id") == cardId);
            }
            var notFound = await Send(staff, HttpMethod.Get,
                $"/kanbans/{boardId}/cards?columnId={targetColumnId}&search=нет-такой-карточки");
            Assert.Empty(notFound["items"]!.AsArray());
            Assert.Null(notFound["selectedTotal"]);
            var summary = cardWithQuote["quote"]!;
            Assert.Equal(kind, Text(summary, "quoteKind"));
            Assert.Equal("Иванов Иван", Text(summary, "clientName"));
            Assert.Equal("ООО Исполнитель", Text(summary, "executorName"));
            Assert.Equal(1, summary["linkViews"]!.GetValue<int>());
            Assert.NotNull(summary["lastViewedAt"]);
            var chosen = summary["selections"]!.AsArray().Single()!;
            Assert.Equal("Кондиционеры", Text(chosen, "proposalTypeName"));
            Assert.Equal(28512m, chosen["total"]!.GetValue<decimal>());
            if (typeMode) Assert.Null(chosen["variantName"]);
            else Assert.Equal("Оптимальный", Text(chosen, "variantName"));
            Assert.NotNull(cardWithQuote["movedByName"]);

            await Send(staff, HttpMethod.Delete, quotePath + "/client-access");
            await Send(guest, HttpMethod.Get, "/client/quotes/current", expected: HttpStatusCode.Unauthorized);
            var revokedStatus = await Send(staff, HttpMethod.Get, quotePath + "/client-access");
            Assert.False(revokedStatus["isActive"]!.GetValue<bool>());
            Assert.Null(revokedStatus["password"]);
            await Send(staff, HttpMethod.Post, quotePath + "/client-access/extend", new { additionalDays = 7 }, HttpStatusCode.Conflict);
            await Send(staff, HttpMethod.Delete, path);
            await Send(staff, HttpMethod.Get, quotePath, expected: HttpStatusCode.NotFound);
        }

        var impact = await Send(staff, HttpMethod.Get, "/company/configuration/categories/equipment/deletion-impact");
        // Deletion impact includes the soft-deleted second bulk-edit target
        // and the soft-deleted item without a section.
        Assert.Equal(3, impact["itemCount"]!.GetValue<int>());
        var emptyDraft = draft with
        {
            Categories = [],
            Workflows = draft.Workflows.Select(workflow => workflow with { Categories = [] }).ToArray(),
            Rules = [], MoneyPipelines = [], Dependencies = [],
        };
        await Send(staff, HttpMethod.Put, "/company/configuration", new { draft = emptyDraft, deleteCategoryData = Array.Empty<string>() }, HttpStatusCode.Conflict);
        await Send(staff, HttpMethod.Get, $"/catalog/items/{productId}");
        await Send(staff, HttpMethod.Put, "/company/configuration", new { draft = emptyDraft, deleteCategoryData = (string[])["equipment", "services"] });
        Assert.Empty((await Send(staff, HttpMethod.Get, "/catalog/configuration"))["categories"]!.AsArray());
        Assert.NotEmpty((await Send(staff, HttpMethod.Get, "/company/audit")).AsArray());

        var refreshed = await Send(staff, HttpMethod.Post, "/auth/refresh", new
        {
            refreshToken = Text(authenticated["tokens"]!, "refreshToken"),
        });
        staff.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Text(refreshed, "accessToken"));
        await Send(staff, HttpMethod.Post, "/identity/logout");
        await Send(staff, HttpMethod.Get, "/company/profile", expected: HttpStatusCode.Forbidden);
    }

    private static OrganizationOnboardingDraft Draft() => new(
        9, new CompanyProfileDraft("Проверка проекта"),
        [new WorkflowDraft("sales", "Предложения", [
            new WorkflowColumnDraft("start", "Подготовка", "#4D8DFF", ["quote", "prequote"]),
            new WorkflowColumnDraft("finish", "Готово", "#58D68D"),
        ], [new WorkflowTransitionDraft("start", "finish")],
            [new WorkflowCategoryDraft("equipment", ["name", "marking", "unit", "base_price", "quantity"])], "quote_and_prequote")],
        [new CatalogCategoryDraft("equipment", "Оборудование",
            [new CatalogSectionDraft("Блоки", [])],
            [.. OnboardingFieldRegistry.DefaultCatalogFields(),
                new CatalogFieldDraft("markup_value", true, false), new CatalogFieldDraft("discount_value", true, false),
                new CatalogFieldDraft("custom_note", true, false, Label: "Проверка", FieldType: "text"),
                new CatalogFieldDraft("custom_total", true, false, Label: "Итог", FieldType: "calculated_money"),
                new CatalogFieldDraft("linked_services", true, false)]),
            new CatalogCategoryDraft("services", "Работы", [], OnboardingFieldRegistry.DefaultCatalogFields())],
        [new EntityFieldDraft("quote", "name", "Наименование", "text", true, true)],
        [],
        [new DictionaryDraft("units", "Единицы измерения", [new DictionaryItemDraft("шт")])],
        Dependencies: [new CategoryDependencyDraft("services-equipment", "services", "equipment", "linked_services")],
        Rules: [new CalculationRuleDraft("check", "Проверка правила", "equipment", "card_saving", true, null, [],
            [new RuleActionDraft("set_field", TargetFieldCode: "custom_note", ConstantValue: "Проверено правилом")])],
        MoneyPipelines: [new MoneyPipelineDraft("equipment", "base_price", null, "markup_value", "discount_value", "quantity", "custom_total", 2, true, "total")]);

    private static async Task CheckBulkRelations(HttpClient staff, JsonNode configuration, string firstId, object productRequest, string unitId)
    {
        var sourceCategoryId = Text(configuration["categories"]!.AsArray().Single(item => Text(item!, "name") == "Работы")!, "id");
        var dependencyId = Text(configuration["dependencies"]![0]!, "id");
        var secondRequest = JsonSerializer.SerializeToNode(productRequest)!;
        secondRequest["marking"] = "AC-25";
        var secondId = Text(await Send(staff, HttpMethod.Post, "/catalog/items", secondRequest), "id");
        async Task<string> Source(string name) => Text(await Send(staff, HttpMethod.Post, "/catalog/items", new
        {
            categoryId = sourceCategoryId, name, marking = "S-1", status = "approved",
            values = new Dictionary<string, object> { ["unit"] = unitId, ["base_price"] = 100m },
        }), "id");
        var sourceId = await Source("Монтаж");
        var otherId = await Source("Доставка");
        await Send(staff, HttpMethod.Put, $"/catalog/items/{firstId}/relations", new[] {
            new { dependencyId, sourceItemId = otherId }, new { dependencyId, sourceItemId = sourceId },
        });
        var bulk = new { itemIds = new[] { firstId, secondId }, action = "add_relation", dependencyId, sourceItemId = sourceId };
        var added = await Send(staff, HttpMethod.Post, "/catalog/items/bulk", bulk);
        Assert.Equal(1, added["affected"]!.GetValue<int>());
        Assert.Equal(2, (await Send(staff, HttpMethod.Get, $"/catalog/items/{firstId}/relations")).AsArray().Count);
        Assert.Single((await Send(staff, HttpMethod.Get, $"/catalog/items/{secondId}/relations")).AsArray());
        Assert.Equal(0, (await Send(staff, HttpMethod.Post, "/catalog/items/bulk", bulk))["affected"]!.GetValue<int>());
        var savedRelations = await Send(staff, HttpMethod.Get, $"/catalog/items/{firstId}/relations");
        var settings = await Send(staff, HttpMethod.Get, "/company/configuration");
        await Send(staff, HttpMethod.Put, "/company/configuration", new {
            draft = settings, deleteCategoryData = Array.Empty<string>(),
        });
        Assert.True(JsonNode.DeepEquals(savedRelations,
            await Send(staff, HttpMethod.Get, $"/catalog/items/{firstId}/relations")));
        Assert.Equal(dependencyId,
            Text((await Send(staff, HttpMethod.Get, "/catalog/configuration"))["dependencies"]![0]!, "id"));
        Assert.Single((await Send(staff, HttpMethod.Get, $"/catalog/items/{secondId}/relations")).AsArray());
        var fields = settings["categories"]![0]!["fields"]!.AsArray();
        var reorderedFields = fields.Reverse().Select(field => field!.DeepClone()).ToArray();
        fields.Clear();
        foreach (var field in reorderedFields) fields.Add(field);
        await Send(staff, HttpMethod.Put, "/company/configuration", new {
            draft = settings, deleteCategoryData = Array.Empty<string>(),
        });
        Assert.True(JsonNode.DeepEquals(savedRelations,
            await Send(staff, HttpMethod.Get, $"/catalog/items/{firstId}/relations")));
        // The first update must roll back when a later target has an incompatible category.
        await Send(staff, HttpMethod.Post, "/catalog/items/bulk", new {
            itemIds = new[] { secondId, sourceId }, action = "add_relation", dependencyId, sourceItemId = otherId,
        }, HttpStatusCode.BadRequest);
        Assert.Single((await Send(staff, HttpMethod.Get, $"/catalog/items/{secondId}/relations")).AsArray());
        await Send(staff, HttpMethod.Post, "/catalog/items/bulk", new {
            itemIds = new[] { firstId, secondId }, action = "remove_relation", dependencyId, sourceItemId = sourceId,
        });
        Assert.Equal(otherId, Text((await Send(staff, HttpMethod.Get, $"/catalog/items/{firstId}/relations"))[0]!, "sourceItemId"));
        Assert.Empty((await Send(staff, HttpMethod.Get, $"/catalog/items/{secondId}/relations")).AsArray());
        await Send(staff, HttpMethod.Delete, $"/catalog/items/{secondId}");
    }

    private static object QuoteRequest(string kind, string clientId, string executorCompanyId, string categoryId, string sectionId, string productId) => new
    {
        quoteKind = kind, title = "Тестовое предложение", clientId, executorCompanyId, selectionMode = kind == "prequote" ? "proposal_type" : "variant",
        proposalTypes = new[] { new {
            id = Guid.NewGuid(), name = "Кондиционеры", variants = new[] { new {
                id = Guid.NewGuid(), name = "Оптимальный", vatRate = 20m, categories = new[] { new {
                    id = Guid.NewGuid(), catalogCategoryId = categoryId, name = "Оборудование", sections = new[] { new {
                        id = Guid.NewGuid(), catalogSectionId = sectionId, name = "Блоки", positions = new[] { new {
                            id = Guid.NewGuid(), catalogItemId = productId, name = "Кондиционер", marking = "AC-24", unit = "шт",
                            quantity = 2m, purchasePrice = 8000m, basePrice = 10000m, manualPrice = 12000m,
                            markupPercent = 10m, discountPercent = 10m, excludeFromTotals = false,
                        } },
                    } },
                } },
            } },
        }, new {
            id = Guid.NewGuid(), name = "Бойлеры", variants = new[] { new {
                id = Guid.NewGuid(), name = "Базовый", vatRate = 20m, categories = new[] { new {
                    id = Guid.NewGuid(), catalogCategoryId = categoryId, name = "Оборудование", sections = new[] { new {
                        id = Guid.NewGuid(), catalogSectionId = sectionId, name = "Блоки", positions = new[] { new {
                            id = Guid.NewGuid(), catalogItemId = productId, name = "Кондиционер", marking = "AC-24", unit = "шт",
                            quantity = 1m, purchasePrice = 8000m, basePrice = 10000m, manualPrice = 10000m,
                            markupPercent = 0m, discountPercent = 0m, excludeFromTotals = false,
                        } },
                    } },
                } },
            } },
        } },
    };

    private static async Task<JsonNode> Send(HttpClient client, HttpMethod method, string path, object? body = null, HttpStatusCode expected = HttpStatusCode.OK)
    {
        using var request = new HttpRequestMessage(method, "/api/v1" + path);
        if (body != null) request.Content = JsonContent.Create(body);
        using var response = await client.SendAsync(request);
        var content = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == expected, $"{method} {path}: HTTP {(int)response.StatusCode}, expected {(int)expected}. {content}");
        if (!response.IsSuccessStatusCode) return new JsonObject();
        var envelope = JsonNode.Parse(content)!;
        Assert.True(envelope["ok"]!.GetValue<bool>());
        return envelope["data"]!;
    }

    private static string Text(JsonNode node, string key) => node[key]!.GetValue<string>();

    [System.Diagnostics.CodeAnalysis.SuppressMessage("Security", "CA5350", Justification = "RFC 6238 TOTP uses HMAC-SHA1 for authenticator compatibility.")]
    private static string Totp(string base32)
    {
        const string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
        var bytes = new List<byte>();
        var bits = 0;
        var buffer = 0;
        foreach (var symbol in base32.TrimEnd('='))
        {
            buffer = (buffer << 5) | alphabet.IndexOf(symbol);
            bits += 5;
            if (bits < 8) continue;
            bits -= 8;
            bytes.Add((byte)(buffer >> bits));
        }
        Span<byte> counter = stackalloc byte[8];
        BinaryPrimitives.WriteInt64BigEndian(counter, DateTimeOffset.UtcNow.ToUnixTimeSeconds() / 30);
        var hash = HMACSHA1.HashData(bytes.ToArray(), counter);
        var offset = hash[^1] & 15;
        var code = BinaryPrimitives.ReadInt32BigEndian(hash.AsSpan(offset, 4)) & int.MaxValue;
        return (code % 1000000).ToString("D6", System.Globalization.CultureInfo.InvariantCulture);
    }
}

public sealed class DatabaseFactAttribute : FactAttribute
{
    public DatabaseFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SKLAD_TEST_POSTGRES")) ||
            string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SKLAD_TEST_REDIS")))
            Skip = "Set SKLAD_TEST_POSTGRES and SKLAD_TEST_REDIS to run isolated database regression tests.";
    }
}

internal sealed class RegressionFactory(
    string connectionString,
    Action<IServiceCollection>? configureServices = null) : WebApplicationFactory<Program>
{
    internal const string BootstrapToken = "isolated-regression-bootstrap-token";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureLogging(logging => logging.ClearProviders().AddConsole());
        builder.UseSetting("Database:ConnectionString", connectionString);
        builder.UseSetting("Redis:ConnectionString", Environment.GetEnvironmentVariable("SKLAD_TEST_REDIS"));
        builder.UseSetting("Security:BootstrapToken", BootstrapToken);
        builder.UseSetting("Security:TotpEncryptionKey", Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)));
        builder.UseSetting("Jwt:SigningKey", Convert.ToBase64String(RandomNumberGenerator.GetBytes(48)));
        if (configureServices is not null) builder.ConfigureTestServices(configureServices);
    }
}

internal sealed class RegressionDatabase : IAsyncDisposable
{
    private readonly string _name = "sklad_regression_" + Guid.NewGuid().ToString("N");
    private readonly string _adminConnection;
    private bool _created;
    internal string ConnectionString { get; }

    private RegressionDatabase()
    {
        var options = new NpgsqlConnectionStringBuilder(Environment.GetEnvironmentVariable("SKLAD_TEST_POSTGRES"))
        {
            Database = "postgres", Pooling = false,
        };
        _adminConnection = options.ConnectionString;
        options.Database = _name;
        ConnectionString = options.ConnectionString;
    }

    internal static async Task<RegressionDatabase> CreateAsync()
    {
        var database = new RegressionDatabase();
        try
        {
            await using var admin = new NpgsqlConnection(database._adminConnection);
            await admin.OpenAsync();
            await using (var create = new NpgsqlCommand($"CREATE DATABASE {database._name}", admin))
                await create.ExecuteNonQueryAsync();
            database._created = true;
            await using var connection = new NpgsqlConnection(database.ConnectionString);
            await connection.OpenAsync();
            var root = new DirectoryInfo(AppContext.BaseDirectory);
            while (root != null && !File.Exists(Path.Combine(root.FullName, "SkladKomforta.sln"))) root = root.Parent;
            if (root == null) throw new DirectoryNotFoundException("Cannot locate solution migrations.");
            foreach (var file in Directory.GetFiles(Path.Combine(root.FullName, "migrations", "public"), "*.sql").Order(StringComparer.Ordinal))
            {
                await using var migration = new NpgsqlCommand(await File.ReadAllTextAsync(file), connection);
                await migration.ExecuteNonQueryAsync();
            }
            return database;
        }
        catch
        {
            await database.DisposeAsync();
            throw;
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (!_created) return;
        await using var connection = new NpgsqlConnection(_adminConnection);
        await connection.OpenAsync();
        // The name is generated here, never taken from the configured database.
        await using var drop = new NpgsqlCommand($"DROP DATABASE {_name} WITH (FORCE)", connection);
        await drop.ExecuteNonQueryAsync();
        _created = false;
    }
}
