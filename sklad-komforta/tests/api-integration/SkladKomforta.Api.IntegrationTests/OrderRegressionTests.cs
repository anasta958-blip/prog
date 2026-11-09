using System.Net;
using System.Net.Http.Headers;
using System.Text.Json.Nodes;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Api.IntegrationTests;

public sealed partial class DatabaseRegressionTests
{
    /// <summary>
    /// Комплектация на живой базе: перенос из КП со слиянием одинаковых строк,
    /// повторный перенос (количество, дозаказ, удаление), обратный перенос,
    /// пометки связанных карточек, печать, счета и ручное создание.
    /// </summary>
    [DatabaseFact]
    public async Task OrdersTransferFromQuoteAgainstRealDatabase()
    {
        await using var database = await RegressionDatabase.CreateAsync();
        await using var factory = new RegressionFactory(database.ConnectionString);
        using var staff = factory.CreateClient();
        await SignInDirectorAsync(staff, OrderDraft());

        var configuration = await Send(staff, HttpMethod.Get, "/catalog/configuration");
        var categories = configuration["categories"]!.AsArray();
        var equipment = categories.Single(item => Text(item!, "name") == "Оборудование")!;
        var services = categories.Single(item => Text(item!, "name") == "Работы")!;
        var equipmentId = Text(equipment, "id");
        var sectionId = Text(equipment["sections"]![0]!, "id");
        var servicesId = Text(services, "id");
        var unitId = Text(configuration["dictionaries"]![0]!["items"]![0]!, "id");
        async Task<string> Product(string categoryId, string? section, string name, string marking) =>
            Text(await Send(staff, HttpMethod.Post, "/catalog/items", new
            {
                categoryId, sectionId = section, name, marking, status = "approved",
                values = new Dictionary<string, object> { ["unit"] = unitId, ["base_price"] = 1000m },
            }), "id");
        var conditioner = await Product(equipmentId, sectionId, "Кондиционер", "AC-24");
        var pipe = await Product(equipmentId, sectionId, "Труба", "D-12");
        var montage = await Product(servicesId, null, "Монтаж", "M-1");

        var executor = Text(await Send(staff, HttpMethod.Post, "/company/legal-entities", new
        {
            name = "Исполнитель", companyType = "ООО", legalName = "ООО Исполнитель",
            inn = "7707083893", kpp = "773601001", ogrn = "1027700132195", phone = "+79991234567",
            directorName = "Иванов Иван", signatoryName = "Иванов Иван", signatoryTitle = "Директор",
            bankName = "Тестовый банк", bankBik = "044525225", bankAccount = "40702810900000000001",
            corrAccount = "30101810400000000225", vatRates = new decimal?[] { 20 }, isDefault = true,
        }), "id");
        var client = Text(await Send(staff, HttpMethod.Post, "/company/clients", new
        {
            name = "Петров Пётр", companyName = "Петров Пётр", companyType = "person", phone = "+79990000000",
            passportSeries = "1234", passportNumber = "123456", passportIssuedBy = "Тестовый отдел",
        }), "id");

        var boards = (await Send(staff, HttpMethod.Get, "/kanbans/")).AsArray();
        var sales = Text(boards.Single(item => Text(item!, "code") == "sales")!, "id");
        var orders = Text(boards.Single(item => Text(item!, "code") == "orders")!, "id");
        var salesBoard = await Send(staff, HttpMethod.Get, $"/kanbans/{sales}");
        var orderBoard = await Send(staff, HttpMethod.Get, $"/kanbans/{orders}");
        string Column(JsonNode board, string name) =>
            Text(board["columns"]!.AsArray().Single(item => Text(item!, "name") == name)!, "id");
        var start = Column(salesBoard, "Подготовка");
        var buy = Column(salesBoard, "Закупить материал");
        var done = Column(salesBoard, "Завершено");
        var compose = Column(orderBoard, "Составление");
        var montageColumn = Column(orderBoard, "Монтаж");
        var back = Column(orderBoard, "Вернуть в КП");
        Assert.Equal(orders, Text(salesBoard["columns"]![1]!["transferTo"]!, "boardId"));
        Assert.True(orderBoard["columns"]![1]!["reorderFrom"]!.GetValue<bool>());
        Assert.Equal(["Квартира", "Дом"], orderBoard["objectTypes"]!.AsArray().Select(item => item!.GetValue<string>()));
        var shipment = orderBoard["categories"]![0]!["fields"]!.AsArray()
            .Single(item => Text(item!, "code") == "shipment_status")!;
        Assert.Equal("Статус отгрузки", Text(shipment, "label"));
        Assert.Equal(2, shipment["options"]!.AsArray().Count);
        Assert.Equal("custom_vendor", Text(orderBoard["categories"]![0]!, "supplierFilterFieldCode"));

        // Одинаковые позиции выбранных вариантов разных типов суммируются;
        // категория «Работы» в комплектацию не попадает.
        var quoteBody = OrderQuote(client, executor, equipmentId, sectionId, servicesId, conditioner, pipe, montage,
            firstQuantity: 2, withPipe: false);
        var quoteCard = Text(await Send(staff, HttpMethod.Post, $"/kanbans/{sales}/quotes",
            new { columnId = start, quote = quoteBody }), "cardId");
        var quotePath = $"/kanbans/{sales}/cards/{quoteCard}";
        var quote = await Send(staff, HttpMethod.Get, quotePath + "/quote");
        Assert.NotNull(quote["managerUserId"]);
        Assert.True(quote["canChangeManager"]!.GetValue<bool>());
        await Send(staff, HttpMethod.Post, quotePath + "/move", new { targetColumnId = buy, targetIndex = 0 });

        var orderCards = (await Send(staff, HttpMethod.Get, $"/kanbans/{orders}/cards?columnId={compose}"))["items"]!.AsArray();
        var orderCard = Assert.Single(orderCards)!;
        var orderCardId = Text(orderCard, "id");
        var orderPath = $"/kanbans/{orders}/cards/{orderCardId}/order";
        Assert.Equal(1, orderCard["order"]!["positionCount"]!.GetValue<int>());
        var quoteCardSummary = (await Send(staff, HttpMethod.Get, $"/kanbans/{sales}/cards?columnId={buy}"))["items"]![0]!;
        Assert.Equal(orders, Text(quoteCardSummary["linkedCards"]![0]!, "boardId"));
        Assert.Equal(quoteCardSummary["number"]!.GetValue<long>(), orderCard["order"]!["sourceQuoteNumber"]!.GetValue<long>());

        var order = await Send(staff, HttpMethod.Get, orderPath);
        Assert.Equal("Объект на Лесной", Text(order, "title"));
        Assert.Equal(Text(quote, "managerUserId"), Text(order, "managerUserId"));
        var row = Assert.Single(order["categories"]!.AsArray())!["sections"]![0]!["positions"]![0]!;
        Assert.Equal(3m, row["quantity"]!.GetValue<decimal>());
        Assert.True(row["fromQuote"]!.GetValue<bool>());
        Assert.False(row["isReorder"]!.GetValue<bool>());
        Assert.Equal("Белый", Text(row["values"]!, "custom_note"));
        Assert.Null(row["values"]!["base_price"]);

        // Правка комплектации: тип объекта, статус отгрузки, ручная строка.
        order["objectType"] = "Офис";
        await Send(staff, HttpMethod.Put, orderPath, order, HttpStatusCode.BadRequest);
        order["objectType"] = "Дом";
        var positions = order["categories"]![0]!["sections"]![0]!["positions"]!.AsArray();
        positions[0]!["values"]!["shipment_status"] = "Купить";
        positions.Add(new JsonObject
        {
            ["id"] = Guid.NewGuid(), ["catalogItemId"] = pipe, ["name"] = "Труба", ["marking"] = "D-12",
            ["unit"] = "шт", ["quantity"] = 2m, ["values"] = new JsonObject(),
        });
        var saved = await Send(staff, HttpMethod.Put, orderPath, order);
        Assert.Equal("Дом", Text(saved, "objectType"));
        var duplicate = saved.DeepClone();
        duplicate["categories"]![0]!["sections"]!.AsArray().Add(duplicate["categories"]![0]!["sections"]![0]!.DeepClone());
        await Send(staff, HttpMethod.Put, orderPath, duplicate, HttpStatusCode.BadRequest);

        // Повторный перенос из столбца дозаказа: количество из КП, новая строка —
        // дозаказ, заполненные поля и ручная строка сохраняются.
        await Send(staff, HttpMethod.Post, $"/kanbans/{orders}/cards/{orderCardId}/move", new { targetColumnId = montageColumn, targetIndex = 0 });
        var updatedQuote = OrderQuote(client, executor, equipmentId, sectionId, servicesId, conditioner, pipe, montage,
            firstQuantity: 5, withPipe: true);
        await Send(staff, HttpMethod.Put, quotePath + "/quote", updatedQuote);
        await Send(staff, HttpMethod.Post, quotePath + "/move", new { targetColumnId = start, targetIndex = 0 });
        await Send(staff, HttpMethod.Post, quotePath + "/move", new { targetColumnId = buy, targetIndex = 0 });
        var synced = await Send(staff, HttpMethod.Get, orderPath);
        var syncedRows = synced["categories"]![0]!["sections"]![0]!["positions"]!.AsArray();
        Assert.Equal(3, syncedRows.Count);
        var conditionerRow = syncedRows.Single(item => Text(item!, "name") == "Кондиционер")!;
        Assert.Equal(6m, conditionerRow["quantity"]!.GetValue<decimal>());
        Assert.Equal("Купить", Text(conditionerRow["values"]!, "shipment_status"));
        Assert.Single(syncedRows, item => !item!["fromQuote"]!.GetValue<bool>());
        var reorderRow = syncedRows.Single(item => item!["fromQuote"]!.GetValue<bool>() && Text(item!, "name") == "Труба")!;
        Assert.True(reorderRow["isReorder"]!.GetValue<bool>());
        Assert.Equal("Дом", Text(synced, "objectType"));
        Assert.Single((await Send(staff, HttpMethod.Get, $"/kanbans/{orders}/cards?columnId={compose}"))["items"]!.AsArray());

        // Позиция исчезла из КП — исчезает и из комплектации.
        await Send(staff, HttpMethod.Put, quotePath + "/quote", quoteBody);
        await Send(staff, HttpMethod.Post, quotePath + "/move", new { targetColumnId = start, targetIndex = 0 });
        await Send(staff, HttpMethod.Post, quotePath + "/move", new { targetColumnId = buy, targetIndex = 0 });
        var trimmed = (await Send(staff, HttpMethod.Get, orderPath))["categories"]![0]!["sections"]![0]!["positions"]!.AsArray();
        Assert.Equal(2, trimmed.Count);
        Assert.Equal(3m, trimmed.Single(item => Text(item!, "name") == "Кондиционер")!["quantity"]!.GetValue<decimal>());

        // Печать и счета.
        using (var pdf = await staff.GetAsync("/api/v1" + orderPath + "/pdf"))
        {
            Assert.Equal(HttpStatusCode.OK, pdf.StatusCode);
            var bytes = await pdf.Content.ReadAsByteArrayAsync();
            Assert.Equal("%PDF", System.Text.Encoding.ASCII.GetString(bytes, 0, 4));
        }
        await Send(staff, HttpMethod.Post, orderPath + "/invoices/uploads",
            new { fileName = "счёт.png", contentType = "image/png", byteSize = 100 }, HttpStatusCode.BadRequest);
        var ticket = await Send(staff, HttpMethod.Post, orderPath + "/invoices/uploads",
            new { fileName = "счёт.pdf", contentType = "application/pdf", byteSize = 100 });
        Assert.False(string.IsNullOrWhiteSpace(Text(ticket, "uploadUrl")));
        Assert.Empty((await Send(staff, HttpMethod.Get, orderPath + "/invoices")).AsArray());

        // Обратный перенос только перемещает карточку КП.
        await Send(staff, HttpMethod.Post, $"/kanbans/{orders}/cards/{orderCardId}/move", new { targetColumnId = back, targetIndex = 0 });
        Assert.Single((await Send(staff, HttpMethod.Get, $"/kanbans/{sales}/cards?columnId={done}"))["items"]!.AsArray());

        // Без выбранного варианта перенос невозможен, а карточка остаётся на месте.
        var unselected = OrderQuote(client, executor, equipmentId, sectionId, servicesId, conditioner, pipe, montage,
            firstQuantity: 1, withPipe: false, selected: false);
        var unselectedCard = Text(await Send(staff, HttpMethod.Post, $"/kanbans/{sales}/quotes",
            new { columnId = start, quote = unselected }), "cardId");
        await Send(staff, HttpMethod.Post, $"/kanbans/{sales}/cards/{unselectedCard}/move",
            new { targetColumnId = buy, targetIndex = 0 }, HttpStatusCode.Conflict);
        Assert.Contains((await Send(staff, HttpMethod.Get, $"/kanbans/{sales}/cards?columnId={start}"))["items"]!.AsArray(),
            item => Text(item!, "id") == unselectedCard);

        // Создание кнопкой: менеджер — создатель, только в столбце с действием.
        var manual = new
        {
            title = "Склад на Заводской", objectType = "Квартира", clientId = client, executorCompanyId = executor,
            categories = Array.Empty<object>(),
        };
        await Send(staff, HttpMethod.Post, $"/kanbans/{orders}/orders",
            new { columnId = montageColumn, order = manual }, HttpStatusCode.Conflict);
        var created = await Send(staff, HttpMethod.Post, $"/kanbans/{orders}/orders", new { columnId = compose, order = manual });
        Assert.Equal(Text(quote, "managerUserId"), Text(created, "managerUserId"));
        Assert.Null(created["sourceQuote"]);
    }

    /// <summary>Вход директора и активация переданной конфигурации.</summary>
    private static async Task SignInDirectorAsync(HttpClient staff, OrganizationOnboardingDraft draft)
    {
        staff.DefaultRequestHeaders.Add("X-Bootstrap-Token", RegressionFactory.BootstrapToken);
        await Send(staff, HttpMethod.Post, "/auth/bootstrap/director", new
        {
            login = "order-director", displayName = "Директор", temporaryPassword = "Regression-test-123!",
        });
        staff.DefaultRequestHeaders.Remove("X-Bootstrap-Token");
        var login = await Send(staff, HttpMethod.Post, "/auth/login", new
        {
            login = "order-director", password = "Regression-test-123!", deviceType = 2,
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
        var organization = await Send(staff, HttpMethod.Post, "/identity/organization", new { name = "Проверка комплектации" });
        staff.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Text(organization, "accessToken"));
        await Send(staff, HttpMethod.Post, "/onboarding/draft", draft);
        await Send(staff, HttpMethod.Post, "/onboarding/activate");
    }

    [DatabaseFact]
    public async Task QuoteAndPrequoteBoardsTransferCopiesDocumentAndReusesLinkedCard()
    {
        await using var database = await RegressionDatabase.CreateAsync();
        await using var factory = new RegressionFactory(database.ConnectionString);
        using var staff = factory.CreateClient();
        var draft = OrderDraft();
        var sales = draft.Workflows[0] with
        {
            Columns =
            [
                draft.Workflows[0].Columns[0],
                draft.Workflows[0].Columns[1] with
                {
                    TransferTo = new WorkflowTransferDraft("prequotes", "pre-start"),
                },
                draft.Workflows[0].Columns[2],
            ],
        };
        var prequotes = new WorkflowDraft("prequotes", "Предварительные предложения",
            [
                new WorkflowColumnDraft("pre-start", "Подготовка ПКП", "#4D8DFF", ["prequote"]),
                new WorkflowColumnDraft("pre-back", "Вернуть в КП", "#F59E0B",
                    TransferTo: new WorkflowTransferDraft("sales", "done")),
            ],
            [new WorkflowTransitionDraft("pre-start", "pre-back")],
            Specialization: "prequote");
        await SignInDirectorAsync(staff, draft with { Workflows = [sales, prequotes] });

        var configuration = await Send(staff, HttpMethod.Get, "/catalog/configuration");
        var categories = configuration["categories"]!.AsArray();
        var equipment = categories.Single(item => Text(item!, "name") == "Оборудование")!;
        var services = categories.Single(item => Text(item!, "name") == "Работы")!;
        var equipmentId = Text(equipment, "id");
        var sectionId = Text(equipment["sections"]![0]!, "id");
        var servicesId = Text(services, "id");
        var unitId = Text(configuration["dictionaries"]![0]!["items"]![0]!, "id");
        async Task<string> Product(string categoryId, string? section, string name) =>
            Text(await Send(staff, HttpMethod.Post, "/catalog/items", new
            {
                categoryId, sectionId = section, name, marking = "T-1", status = "approved",
                values = new Dictionary<string, object> { ["unit"] = unitId, ["base_price"] = 1000m },
            }), "id");
        var conditioner = await Product(equipmentId, sectionId, "Кондиционер");
        var montage = await Product(servicesId, null, "Монтаж");
        var executor = Text(await Send(staff, HttpMethod.Post, "/company/legal-entities", new
        {
            name = "Исполнитель", companyType = "ООО", legalName = "ООО Исполнитель",
            inn = "7707083893", kpp = "773601001", ogrn = "1027700132195", phone = "+79991234567",
            directorName = "Иванов Иван", signatoryName = "Иванов Иван", signatoryTitle = "Директор",
            bankName = "Тестовый банк", bankBik = "044525225", bankAccount = "40702810900000000001",
            corrAccount = "30101810400000000225", vatRates = new decimal?[] { 20 }, isDefault = true,
        }), "id");
        var client = Text(await Send(staff, HttpMethod.Post, "/company/clients", new
        {
            name = "Петров Пётр", companyName = "Петров Пётр", companyType = "person", phone = "+79990000000",
            passportSeries = "1234", passportNumber = "123456", passportIssuedBy = "Тестовый отдел",
        }), "id");

        var boards = (await Send(staff, HttpMethod.Get, "/kanbans/")).AsArray();
        var salesId = Text(boards.Single(item => Text(item!, "code") == "sales")!, "id");
        var prequotesId = Text(boards.Single(item => Text(item!, "code") == "prequotes")!, "id");
        var salesBoard = await Send(staff, HttpMethod.Get, $"/kanbans/{salesId}");
        var prequotesBoard = await Send(staff, HttpMethod.Get, $"/kanbans/{prequotesId}");
        string Column(JsonNode board, string name) =>
            Text(board["columns"]!.AsArray().Single(item => Text(item!, "name") == name)!, "id");
        var start = Column(salesBoard, "Подготовка");
        var buy = Column(salesBoard, "Закупить материал");
        var done = Column(salesBoard, "Завершено");
        var preStart = Column(prequotesBoard, "Подготовка ПКП");
        var preBack = Column(prequotesBoard, "Вернуть в КП");
        var quoteBody = OrderQuote(client, executor, equipmentId, sectionId, servicesId,
            conditioner, conditioner, montage, firstQuantity: 2, withPipe: false);
        var quoteCardId = Text(await Send(staff, HttpMethod.Post, $"/kanbans/{salesId}/quotes",
            new { columnId = start, quote = quoteBody }), "cardId");
        var quote = await Send(staff, HttpMethod.Get,
            $"/kanbans/{salesId}/cards/{quoteCardId}/quote");
        await Send(staff, HttpMethod.Post, $"/kanbans/{salesId}/cards/{quoteCardId}/move",
            new { targetColumnId = buy, targetIndex = 0 });

        var prequoteCards = (await Send(staff, HttpMethod.Get,
            $"/kanbans/{prequotesId}/cards?columnId={preStart}"))["items"]!.AsArray();
        var prequoteCardId = Text(Assert.Single(prequoteCards)!, "id");
        var prequote = await Send(staff, HttpMethod.Get,
            $"/kanbans/{prequotesId}/cards/{prequoteCardId}/quote");
        Assert.Equal("prequote", Text(prequote, "quoteKind"));
        Assert.Equal(Text(quote, "title"), Text(prequote, "title"));
        Assert.Equal(quote["proposalTypes"]!.AsArray().Count, prequote["proposalTypes"]!.AsArray().Count);
        Assert.NotEqual(Text(quote["proposalTypes"]![0]!, "id"),
            Text(prequote["proposalTypes"]![0]!, "id"));
        Assert.Equal(Text(prequote["proposalTypes"]![0]!["variants"]![0]!, "id"),
            Text(prequote["proposalTypes"]![0]!, "selectedVariantId"));
        Assert.Equal(quote["proposalTypes"]![0]!["variants"]![0]!["categories"]![0]!["sections"]![0]!["positions"]!.AsArray().Count,
            prequote["proposalTypes"]![0]!["variants"]![0]!["categories"]![0]!["sections"]![0]!["positions"]!.AsArray().Count);

        await Send(staff, HttpMethod.Post, $"/kanbans/{prequotesId}/cards/{prequoteCardId}/move",
            new { targetColumnId = preBack, targetIndex = 0 });
        Assert.Equal(quoteCardId, Text(Assert.Single((await Send(staff, HttpMethod.Get,
            $"/kanbans/{salesId}/cards?columnId={done}"))["items"]!.AsArray())!, "id"));
        await Send(staff, HttpMethod.Post, $"/kanbans/{salesId}/cards/{quoteCardId}/move",
            new { targetColumnId = start, targetIndex = 0 });
        await Send(staff, HttpMethod.Post, $"/kanbans/{salesId}/cards/{quoteCardId}/move",
            new { targetColumnId = buy, targetIndex = 0 });
        Assert.Equal(prequoteCardId, Text(Assert.Single((await Send(staff, HttpMethod.Get,
            $"/kanbans/{prequotesId}/cards?columnId={preStart}"))["items"]!.AsArray())!, "id"));
    }

    /// <summary>
    /// Канбан КП со столбцом-триггером «Закупить материал» и канбан комплектации
    /// со столбцом дозаказа «Монтаж» и обратным триггером «Вернуть в КП».
    /// </summary>
    private static OrganizationOnboardingDraft OrderDraft() => new(
        9, new CompanyProfileDraft("Проверка комплектации"),
        [
            new WorkflowDraft("sales", "Предложения", [
                new WorkflowColumnDraft("start", "Подготовка", "#4D8DFF", ["quote"]),
                new WorkflowColumnDraft("buy", "Закупить материал", "#F59E0B",
                    TransferTo: new WorkflowTransferDraft("orders", "compose")),
                new WorkflowColumnDraft("done", "Завершено", "#58D68D"),
            ], [
                new WorkflowTransitionDraft("start", "buy"), new WorkflowTransitionDraft("buy", "start"),
                new WorkflowTransitionDraft("buy", "done"), new WorkflowTransitionDraft("done", "start"),
            ], [
                new WorkflowCategoryDraft("equipment", ["name", "marking", "unit", "quantity", "base_price", "custom_note"]),
                new WorkflowCategoryDraft("services", ["name", "quantity"]),
            ], "quote"),
            new WorkflowDraft("orders", "Комплектация", [
                new WorkflowColumnDraft("compose", "Составление", "#4D8DFF", ["order"]),
                new WorkflowColumnDraft("montage", "Монтаж", "#F59E0B", ReorderFrom: true),
                new WorkflowColumnDraft("back", "Вернуть в КП", "#EF4444",
                    TransferTo: new WorkflowTransferDraft("sales", "done")),
            ], [
                new WorkflowTransitionDraft("compose", "montage"), new WorkflowTransitionDraft("montage", "compose"),
                new WorkflowTransitionDraft("compose", "back"), new WorkflowTransitionDraft("montage", "back"),
                new WorkflowTransitionDraft("back", "compose"),
            ], [
                new WorkflowCategoryDraft("equipment", ["name", "marking", "quantity", "unit", "custom_note", "shipment_status", "custom_vendor"], "custom_vendor"),
            ], "order", new WorkflowOrderSettingsDraft(["Квартира", "Дом"], ["Купить", "На складе"])),
        ],
        [
            new CatalogCategoryDraft("equipment", "Оборудование", [new CatalogSectionDraft("Блоки", [])],
                [.. OnboardingFieldRegistry.DefaultCatalogFields(),
                    new CatalogFieldDraft("custom_note", true, false, Label: "Цвет", FieldType: "text"),
                    new CatalogFieldDraft("custom_vendor", true, false, "units", "Продавец", "dictionary")]),
            new CatalogCategoryDraft("services", "Работы", [], OnboardingFieldRegistry.DefaultCatalogFields()),
        ],
        [new EntityFieldDraft("quote", "name", "Наименование", "text", true, true)],
        [],
        [new DictionaryDraft("units", "Единицы измерения", [new DictionaryItemDraft("шт")])]);

    /// <summary>
    /// КП «Объект на Лесной» в режиме выбора вариантов: тип «Кондиционеры»
    /// (выбран вариант с кондиционером, работой и, при необходимости, трубой;
    /// невыбранный вариант с большим количеством) и тип «Резерв» с тем же
    /// кондиционером.
    /// </summary>
    private static object OrderQuote(
        string clientId, string executorId, string equipmentId, string sectionId, string servicesId,
        string conditioner, string pipe, string montage, decimal firstQuantity, bool withPipe, bool selected = true)
    {
        object Position(string itemId, string name, string marking, decimal quantity, string? note) => new
        {
            catalogItemId = itemId, name, marking, unit = "шт", quantity, basePrice = 1000m,
            excludeFromTotals = false,
            values = note is null ? new Dictionary<string, object>() : new Dictionary<string, object> { ["custom_note"] = note },
        };
        object Equipment(params object[] positions) => new
        {
            catalogCategoryId = equipmentId, name = "Оборудование",
            sections = new[] { new { catalogSectionId = sectionId, name = "Блоки", positions } },
        };
        var chosen = Guid.NewGuid();
        var reserve = Guid.NewGuid();
        var firstPositions = new List<object> { Position(conditioner, "Кондиционер", "AC-24", firstQuantity, "Белый") };
        if (withPipe) firstPositions.Add(Position(pipe, "Труба", "D-12", 1, null));
        return new
        {
            quoteKind = "quote", title = "Объект на Лесной", clientId, executorCompanyId = executorId,
            selectionMode = "variant",
            proposalTypes = new object[]
            {
                new
                {
                    name = "Кондиционеры", selectedVariantId = selected ? chosen : (Guid?)null,
                    variants = new object[]
                    {
                        new
                        {
                            id = chosen, name = "Оптимальный", vatRate = 20m,
                            categories = new object[]
                            {
                                Equipment([.. firstPositions]),
                                new
                                {
                                    catalogCategoryId = servicesId, name = "Работы",
                                    sections = new[] { new
                                    {
                                        catalogSectionId = (string?)null, name = "Работы",
                                        positions = new[] { Position(montage, "Монтаж", "M-1", 1, null) },
                                    } },
                                },
                            },
                        },
                        new
                        {
                            name = "Премиум", vatRate = 20m,
                            categories = new[] { Equipment(Position(conditioner, "Кондиционер", "AC-24", 10, "Белый")) },
                        },
                    },
                },
                new
                {
                    name = "Резерв", selectedVariantId = selected ? reserve : (Guid?)null,
                    variants = new[]
                    {
                        new
                        {
                            id = reserve, name = "Базовый", vatRate = 20m,
                            categories = new[] { Equipment(Position(conditioner, "Кондиционер", "AC-24", 1, "Белый")) },
                        },
                    },
                },
            },
        };
    }
}
