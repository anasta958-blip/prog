using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Api.IntegrationTests;

public sealed partial class DatabaseRegressionTests
{
    [DocumentSaveBenchmarkFact]
    public async Task BenchmarkQuoteAndOrderSaveAgainstRealDatabase()
    {
        foreach (var complex in new[] { false, true })
        {
            await using var database = await RegressionDatabase.CreateAsync();
            await using var factory = new RegressionFactory(database.ConnectionString);
            using var staff = factory.CreateClient();
            var draft = OrderDraft();
            if (complex)
                draft = draft with
                {
                    Rules =
                    [
                        new CalculationRuleDraft("benchmark-extra", "Доплата", "equipment",
                            "row_calculation", true, null, [],
                            [new RuleActionDraft("aggregate_money", SourceFieldCode: "base_price",
                                AggregationOperation: "add", AggregationTarget: "variant_total")]),
                    ],
                };
            await SignInDirectorAsync(staff, draft);

            var configuration = await Send(staff, HttpMethod.Get, "/catalog/configuration");
            var equipment = configuration["categories"]!.AsArray()
                .Single(item => Text(item!, "name") == "Оборудование")!;
            var catalogCategoryId = Text(equipment, "id");
            var catalogSectionId = Text(equipment["sections"]![0]!, "id");
            var executorId = Text(await Send(staff, HttpMethod.Post, "/company/legal-entities", new
            {
                name = "Исполнитель", companyType = "ООО", legalName = "ООО Исполнитель",
                inn = "7707083893", kpp = "773601001", ogrn = "1027700132195", phone = "+79991234567",
                directorName = "Иванов Иван", signatoryName = "Иванов Иван", signatoryTitle = "Директор",
                bankName = "Тестовый банк", bankBik = "044525225", bankAccount = "40702810900000000001",
                corrAccount = "30101810400000000225", vatRates = new decimal?[] { 20 }, isDefault = true,
            }), "id");
            var clientId = Text(await Send(staff, HttpMethod.Post, "/company/clients", new
            {
                name = "Петров Пётр", companyName = "Петров Пётр", companyType = "person", phone = "+79990000000",
                passportSeries = "1234", passportNumber = "123456", passportIssuedBy = "Тестовый отдел",
            }), "id");
            var boards = (await Send(staff, HttpMethod.Get, "/kanbans/")).AsArray();
            var salesId = Text(boards.Single(item => Text(item!, "code") == "sales")!, "id");
            var ordersId = Text(boards.Single(item => Text(item!, "code") == "orders")!, "id");
            var salesBoard = await Send(staff, HttpMethod.Get, $"/kanbans/{salesId}");
            var orderBoard = await Send(staff, HttpMethod.Get, $"/kanbans/{ordersId}");
            var salesColumn = Text(salesBoard["columns"]![0]!, "id");
            var orderColumn = Text(orderBoard["columns"]![0]!, "id");

            var typeId = Guid.NewGuid();
            var variantId = Guid.NewGuid();
            var quote = JsonSerializer.SerializeToNode(new
            {
                quoteKind = "quote", title = "Замер КП", clientId, executorCompanyId = executorId,
                selectionMode = "variant",
                proposalTypes = new[]
                {
                    new
                    {
                        id = typeId, name = "Вариант", selectedVariantId = variantId,
                        variants = new[]
                        {
                            new
                            {
                                id = variantId, name = "Основной", vatRate = 20m,
                                categories = new[]
                                {
                                    new
                                    {
                                        id = Guid.NewGuid(), catalogCategoryId, name = "Оборудование",
                                        sections = new[]
                                        {
                                            new
                                            {
                                                id = Guid.NewGuid(), catalogSectionId, name = "Блоки",
                                                positions = Array.Empty<object>(),
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            })!;
            var quoteCardId = Text(await Send(staff, HttpMethod.Post, $"/kanbans/{salesId}/quotes",
                new { columnId = salesColumn, quote }), "cardId");
            var quotePath = $"/kanbans/{salesId}/cards/{quoteCardId}/quote";
            var quotePositions = quote["proposalTypes"]![0]!["variants"]![0]!["categories"]![0]!["sections"]![0]!["positions"]!.AsArray();

            var order = JsonSerializer.SerializeToNode(new
            {
                title = "Замер комплектации", objectType = "Квартира", clientId,
                executorCompanyId = executorId,
                categories = new[]
                {
                    new
                    {
                        id = Guid.NewGuid(), catalogCategoryId, name = "Оборудование",
                        sections = new[]
                        {
                            new
                            {
                                id = Guid.NewGuid(), catalogSectionId, name = "Блоки",
                                positions = Array.Empty<object>(),
                            },
                        },
                    },
                },
            })!;
            var orderCardId = Text(await Send(staff, HttpMethod.Post, $"/kanbans/{ordersId}/orders",
                new { columnId = orderColumn, order }), "cardId");
            var orderPath = $"/kanbans/{ordersId}/cards/{orderCardId}/order";
            var orderPositions = order["categories"]![0]!["sections"]![0]!["positions"]!.AsArray();

            foreach (var count in new[] { 100, 500, 1000 })
            {
                quotePositions.Clear();
                orderPositions.Clear();
                var quoteIds = new List<string>(count);
                var orderIds = new List<string>(count);
                for (var index = 0; index < count; index++)
                {
                    var quoteId = Guid.NewGuid();
                    var orderId = Guid.NewGuid();
                    quoteIds.Add(quoteId.ToString());
                    orderIds.Add(orderId.ToString());
                    quotePositions.Add(JsonSerializer.SerializeToNode(new
                    {
                        id = quoteId, name = $"Позиция {index}", marking = $"M-{index}",
                        unit = "шт", quantity = 1m, basePrice = 100m,
                        values = new Dictionary<string, object>(),
                    }));
                    orderPositions.Add(JsonSerializer.SerializeToNode(new
                    {
                        id = orderId, name = $"Позиция {index}", marking = $"M-{index}",
                        unit = "шт", quantity = 1m,
                        values = new Dictionary<string, object> { ["base_price"] = 100m },
                    }));
                }

                await Measure("quote", quotePath, quote, quotePositions, quoteIds, count, complex);
                await Measure("order", orderPath, order, orderPositions, orderIds, count, complex);
            }

            async Task Measure(string kind, string path, JsonNode request, JsonArray rows,
                IReadOnlyList<string> ids, int count, bool hasRules)
            {
                var elapsed = new List<double>(5);
                for (var run = 0; run < 6; run++)
                {
                    request["title"] = $"Замер {kind} {count} {run}";
                    var watch = Stopwatch.StartNew();
                    var saved = await Send(staff, HttpMethod.Put, path, request);
                    watch.Stop();
                    if (run > 0) elapsed.Add(watch.Elapsed.TotalMilliseconds);
                    var persisted = kind == "quote"
                        ? saved["proposalTypes"]![0]!["variants"]![0]!["categories"]![0]!["sections"]![0]!["positions"]!.AsArray()
                        : saved["categories"]![0]!["sections"]![0]!["positions"]!.AsArray();
                    Assert.Equal(count, persisted.Count);
                    Assert.Equal(ids[0], Text(persisted[0]!, "id"), ignoreCase: true);
                    Assert.Equal(ids[^1], Text(persisted[^1]!, "id"), ignoreCase: true);
                    if (run == 0)
                        for (var index = 0; index < count; index++)
                            rows[index]!["catalogItemId"] = Text(persisted[index]!, "catalogItemId");
                }
                elapsed.Sort();
                Console.WriteLine($"SAVE kind={kind} complex={hasRules} rows={count} " +
                    $"median_ms={elapsed[elapsed.Count / 2]:F1} min_ms={elapsed[0]:F1} max_ms={elapsed[^1]:F1}");
                var loaded = await Send(staff, HttpMethod.Get, path);
                var loadedRows = kind == "quote"
                    ? loaded["proposalTypes"]![0]!["variants"]![0]!["categories"]![0]!["sections"]![0]!["positions"]!.AsArray()
                    : loaded["categories"]![0]!["sections"]![0]!["positions"]!.AsArray();
                Assert.Equal(rows.Count, loadedRows.Count);
                Assert.Equal(ids, loadedRows.Select(row => Text(row!, "id")),
                    StringComparer.OrdinalIgnoreCase);
            }
        }
    }
}

public sealed class DocumentSaveBenchmarkFactAttribute : FactAttribute
{
    public DocumentSaveBenchmarkFactAttribute()
    {
        if (Environment.GetEnvironmentVariable("SKLAD_BENCH_DOCUMENT_SAVE") != "1" ||
            string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SKLAD_TEST_POSTGRES")) ||
            string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SKLAD_TEST_REDIS")))
            Skip = "Set SKLAD_BENCH_DOCUMENT_SAVE=1, SKLAD_TEST_POSTGRES and SKLAD_TEST_REDIS to benchmark saves.";
    }
}
