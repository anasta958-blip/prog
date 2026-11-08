using System.Net;
using System.Text.Json.Nodes;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Api.IntegrationTests;

public sealed partial class DatabaseRegressionTests
{
    [DatabaseFact]
    public async Task ManualDocumentProductsAreRegisteredOnceAgainstRealDatabase()
    {
        await using var database = await RegressionDatabase.CreateAsync();
        await using var factory = new RegressionFactory(database.ConnectionString);
        using var staff = factory.CreateClient();
        var draft = OrderDraft();
        draft = draft with { Categories = draft.Categories.Select(category => category.ClientId != "equipment" ? category : category with
        { Sections = [new CatalogSectionDraft("Блоки", [new CatalogGroupDraft("Тестовая группа")])] }).ToArray() };
        draft = draft with { Workflows = draft.Workflows.Select(board => board.Code != "sales" ? board : board with
        {
            Specialization = "quote_and_prequote",
            Columns = board.Columns.Select(column => column.ClientId != "start" ? column : column with
            { CreationActions = ["quote", "prequote"] }).ToArray(),
        }).ToArray() };
        await SignInDirectorAsync(staff, draft);
        var configuration = await Send(staff, HttpMethod.Get, "/catalog/configuration");
        var category = configuration["categories"]!.AsArray().Single(item => Text(item!, "name") == "Оборудование")!;
        var categoryId = Text(category, "id");
        var sectionId = Text(category["sections"]![0]!, "id");
        var groupId = Text(category["sections"]![0]!["groups"]![0]!, "id");
        var client = Text(await Send(staff, HttpMethod.Post, "/company/clients", new { name = "Тестовый клиент", companyType = "person" }), "id");
        var executor = Text(await Send(staff, HttpMethod.Post, "/company/legal-entities", new
        {
            name = "Исполнитель", companyType = "ООО", legalName = "ООО Исполнитель",
            inn = "7707083893", kpp = "773601001", ogrn = "1027700132195", phone = "+79991234567",
            directorName = "Иванов Иван", signatoryName = "Иванов Иван", signatoryTitle = "Директор",
            bankName = "Тестовый банк", bankBik = "044525225", bankAccount = "40702810900000000001",
            corrAccount = "30101810400000000225", vatRates = new decimal?[] { 20 }, isDefault = true,
        }), "id");
        var boards = (await Send(staff, HttpMethod.Get, "/kanbans/")).AsArray();
        foreach (var kind in new[] { "quote", "prequote", "order" })
        {
            var boardId = Text(boards.Single(item => Text(item!, "code") == (kind == "order" ? "orders" : "sales"))!, "id");
            var board = await Send(staff, HttpMethod.Get, $"/kanbans/{boardId}");
            var columnId = Text(board["columns"]![0]!, "id");
            var position = new JsonObject
            {
                ["name"] = "Manual " + kind, ["marking"] = "NEW-1", ["unit"] = "шт",
                ["quantity"] = 2, ["basePrice"] = 100,
                ["values"] = new JsonObject { ["custom_note"] = "Тест", ["base_price"] = 100, ["group"] = "Тестовая группа" },
            };
            var categories = new JsonArray(new JsonObject
            {
                ["catalogCategoryId"] = categoryId, ["name"] = "Оборудование",
                ["sections"] = new JsonArray(new JsonObject
                {
                    ["catalogSectionId"] = sectionId, ["name"] = "Блоки",
                    ["positions"] = new JsonArray(position, position.DeepClone()),
                }),
            });
            var body = new JsonObject { ["title"] = "Manual document", ["clientId"] = client, ["executorCompanyId"] = executor };
            if (kind == "order") body["categories"] = categories;
            else
            {
                body["quoteKind"] = kind;
                body["selectionMode"] = "variant";
                body["proposalTypes"] = new JsonArray(new JsonObject
                {
                    ["name"] = "Тип", ["variants"] = new JsonArray(new JsonObject
                    { ["name"] = "Вариант", ["vatRate"] = 20, ["categories"] = categories }),
                });
            }
            var endpoint = kind == "order" ? "order" : "quote";
            var envelope = new JsonObject { ["columnId"] = columnId, [endpoint] = body.DeepClone() };
            JsonArray Positions(JsonNode document) => (kind == "order" ? document["categories"] :
                document["proposalTypes"]![0]!["variants"]![0]!["categories"])![0]!["sections"]![0]!["positions"]!.AsArray();
            var created = await Send(staff, HttpMethod.Post, $"/kanbans/{boardId}/{endpoint}s", envelope);
            var id = Text(Positions(created)[0]!, "catalogItemId");
            Assert.All(Positions(created), item => Assert.Equal(id, Text(item!, "catalogItemId")));
            var item = await Send(staff, HttpMethod.Get, $"/catalog/items/{id}");
            Assert.Equal("pending", Text(item, "status"));
            Assert.Equal(categoryId, Text(item, "categoryId"));
            Assert.Equal(sectionId, Text(item, "sectionId"));
            Assert.Equal(groupId, Text(item, "groupId"));
            Assert.Equal("Тест", Text(item["values"]!, "custom_note"));
            var path = $"/kanbans/{boardId}/cards/{Text(created, "cardId")}/{endpoint}";
            position["name"] = "  MANUAL " + kind.ToUpperInvariant() + "  ";
            position["values"]!["custom_note"] = "Изменено в документе";
            var saved = await Send(staff, HttpMethod.Put, path, body);
            Assert.All(Positions(saved), row => Assert.Equal(id, Text(row!, "catalogItemId")));
            Assert.True(JsonNode.DeepEquals(item, await Send(staff, HttpMethod.Get, $"/catalog/items/{id}")));
            Assert.Equal(1, (await Send(staff, HttpMethod.Get, $"/catalog/items?search=Manual%20{kind}"))["total"]!.GetValue<int>());

            // Failure after the first row was processed must roll back its catalog insert too.
            position["name"] = "Rollback " + kind;
            Positions(body)[1]!["values"] = new JsonObject { ["base_price"] = -10 };
            if (kind != "order")
            {
                await Send(staff, HttpMethod.Put, path, body, HttpStatusCode.BadRequest);
                Assert.Equal(0, (await Send(staff, HttpMethod.Get, $"/catalog/items?search=Rollback"))["total"]!.GetValue<int>());
            }
        }
    }
}
