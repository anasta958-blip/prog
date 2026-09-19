using System.Buffers.Binary;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Logging;
using Npgsql;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class DatabaseRegressionTests
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

        var draft = Draft();
        await Send(staff, HttpMethod.Post, "/onboarding/draft", draft);
        await Send(staff, HttpMethod.Post, "/onboarding/activate");
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
        await Send(staff, HttpMethod.Put, $"/settings/access/roles/{roleId}", roleRequest);
        await Send(staff, HttpMethod.Get, "/settings/access/members");

        var roundtrip = await Send(staff, HttpMethod.Put, "/company/configuration", new { draft, deleteCategoryData = Array.Empty<string>() });
        Assert.Single(roundtrip["rules"]!.AsArray());
        Assert.Single(roundtrip["moneyPipelines"]!.AsArray());
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
        await Send(staff, HttpMethod.Put, $"/catalog/items/{productId}", productRequest);
        await Send(staff, HttpMethod.Get, $"/catalog/items/{productId}");
        Assert.Equal(1, (await Send(staff, HttpMethod.Get, "/catalog/items"))["total"]!.GetValue<int>());

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

        var boards = await Send(staff, HttpMethod.Get, "/kanbans/");
        var boardId = Text(boards[0]!, "id");
        var board = await Send(staff, HttpMethod.Get, $"/kanbans/{boardId}");
        var columnId = Text(board["columns"]![0]!, "id");
        var targetColumnId = Text(board["columns"]![1]!, "id");
        Assert.Equal(2, board["columns"]![0]!["creationActions"]!.AsArray().Count);
        Assert.NotEmpty(board["categories"]![0]!["fields"]!.AsArray());

        foreach (var kind in new[] { "quote", "prequote" })
        {
            var proposal = QuoteRequest(kind, Text(customer, "id"), Text(company, "id"), categoryId, sectionId, productId);
            var created = await Send(staff, HttpMethod.Post, $"/kanbans/{boardId}/quotes", new { columnId, quote = proposal });
            var cardId = Text(created, "cardId");
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
            await Send(staff, HttpMethod.Get, $"/kanbans/{boardId}/cards?columnId={targetColumnId}");
            using var pdf = await staff.GetAsync("/api/v1" + quotePath + "/pdf");
            Assert.Equal(HttpStatusCode.OK, pdf.StatusCode);
            Assert.Equal("application/pdf", pdf.Content.Headers.ContentType?.MediaType);
            Assert.True((await pdf.Content.ReadAsByteArrayAsync()).Length > 1000);

            var link = await Send(staff, HttpMethod.Post, quotePath + "/client-access", new { lifetimeDays = 7 });
            using var guest = factory.CreateClient();
            await Send(guest, HttpMethod.Post, "/client/quotes/login", new
            {
                accessToken = Text(link, "accessToken"), password = "wrong-password",
            }, HttpStatusCode.Unauthorized);
            var clientLogin = await Send(guest, HttpMethod.Post, "/client/quotes/login", new
            {
                accessToken = Text(link, "accessToken"), password = Text(link, "password"),
            });
            guest.DefaultRequestHeaders.Add("X-Quote-Client-Session", Text(clientLogin, "sessionToken"));
            var clientQuote = await Send(guest, HttpMethod.Get, "/client/quotes/current");
            Assert.Equal("Исполнитель", Text(clientQuote, "executorName"));
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
            var employeeView = await Send(staff, HttpMethod.Get, quotePath);
            if (typeMode)
                Assert.Equal(typeId, Text(employeeView, "clientSelectedProposalTypeId"));
            else
            {
                Assert.True(employeeView["proposalTypes"]![0]!["selectedByClient"]!.GetValue<bool>());
                Assert.Equal(variantId, Text(employeeView["proposalTypes"]![0]!, "selectedVariantId"));
            }

            await Send(staff, HttpMethod.Delete, quotePath + "/client-access");
            await Send(guest, HttpMethod.Get, "/client/quotes/current", expected: HttpStatusCode.Unauthorized);
            await Send(staff, HttpMethod.Delete, path);
            await Send(staff, HttpMethod.Get, quotePath, expected: HttpStatusCode.NotFound);
        }

        var impact = await Send(staff, HttpMethod.Get, "/company/configuration/categories/equipment/deletion-impact");
        Assert.Equal(1, impact["itemCount"]!.GetValue<int>());
        var emptyDraft = draft with
        {
            Categories = [],
            Workflows = draft.Workflows.Select(workflow => workflow with { Categories = [] }).ToArray(),
            Rules = [], MoneyPipelines = [],
        };
        await Send(staff, HttpMethod.Put, "/company/configuration", new { draft = emptyDraft, deleteCategoryData = Array.Empty<string>() }, HttpStatusCode.Conflict);
        await Send(staff, HttpMethod.Get, $"/catalog/items/{productId}");
        await Send(staff, HttpMethod.Put, "/company/configuration", new { draft = emptyDraft, deleteCategoryData = (string[])["equipment"] });
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
        9, new CompanyProfileDraft("Проверка проекта", "ООО", null, null, null, null, null, null, null),
        [new WorkflowDraft("sales", "Предложения", [
            new WorkflowColumnDraft("start", "Подготовка", "#4D8DFF", ["quote", "prequote"]),
            new WorkflowColumnDraft("finish", "Готово", "#58D68D"),
        ], [new WorkflowTransitionDraft("start", "finish")],
            [new WorkflowCategoryDraft("equipment", ["name", "marking", "unit", "base_price", "quantity"])], "quote_and_prequote")],
        [new CatalogCategoryDraft("equipment", "Оборудование",
            [new CatalogSectionDraft("Блоки", [])],
            [.. OnboardingFieldRegistry.DefaultCatalogFields(), new CatalogFieldDraft("quantity", true, false),
                new CatalogFieldDraft("markup_value", true, false), new CatalogFieldDraft("discount_value", true, false),
                new CatalogFieldDraft("custom_note", true, false, Label: "Проверка", FieldType: "text"),
                new CatalogFieldDraft("custom_total", true, false, Label: "Итог", FieldType: "calculated_money")])],
        [new EntityFieldDraft("quote", "name", "Наименование", "text", true, true)],
        [], [new DictionaryDraft("units", "Единицы измерения", [new DictionaryItemDraft("шт")])],
        Rules: [new CalculationRuleDraft("check", "Проверка правила", "equipment", "card_saving", true, null, [],
            [new RuleActionDraft("set_field", TargetFieldCode: "custom_note", ConstantValue: "Проверено правилом")])],
        MoneyPipelines: [new MoneyPipelineDraft("equipment", "base_price", null, "markup_value", "discount_value", "quantity", "custom_total", 2, true, "total")]);

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

internal sealed class RegressionFactory(string connectionString) : WebApplicationFactory<Program>
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
