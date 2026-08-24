using System.Text.Json;
using ClosedXML.Excel;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Spreadsheet;
using DocumentFormat.OpenXml.Validation;
using SkladKomforta.Application.Catalog;
using SkladKomforta.Infrastructure.Catalog;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class CatalogSpreadsheetServiceTests
{
    [Fact]
    public async Task TemplateRequiresAtLeastOneConfiguredCategory()
    {
        var gateway = new SpreadsheetCatalogStub(new CatalogConfiguration([], [], []));
        var service = new CatalogSpreadsheetService(gateway);

        var exception = await Assert.ThrowsAsync<SkladKomforta.Application.Identity.IdentityException>(
            () => service.CreateTemplateAsync(null, CancellationToken.None));

        Assert.Equal("catalog_categories_empty", exception.Code);
    }

    [Fact]
    public async Task ExportedWorkbookCanBeImportedWithoutLosingRussianHeadersOrTypes()
    {
        var gateway = new SpreadsheetCatalogStub();
        var service = new CatalogSpreadsheetService(gateway);

        var exported = await service.ExportAsync(new CatalogItemQuery(null, null, null, null), CancellationToken.None);

        using (var validationStream = new MemoryStream(exported.Content))
        using (var document = SpreadsheetDocument.Open(validationStream, false))
        {
            var validationErrors = new OpenXmlValidator().Validate(document).ToArray();
            Assert.True(
                validationErrors.Length == 0,
                string.Join(Environment.NewLine, validationErrors.Select(error => error.Description)));
            var validations = document.WorkbookPart!.WorksheetParts
                .SelectMany(part => part.Worksheet.Descendants<DataValidation>())
                .ToArray();
            Assert.NotEmpty(validations);
            Assert.All(validations, validation =>
                Assert.StartsWith("catalog_list_", validation.Formula1!.Text));
        }

        using (var stream = new MemoryStream(exported.Content))
        using (var workbook = new XLWorkbook(stream))
        {
            var sheet = workbook.Worksheet("Оборудование");
            Assert.Equal("ID", sheet.Cell(1, 1).GetString());
            Assert.Equal("id", sheet.Cell(2, 1).GetString());
            Assert.Equal("Вентилятор", sheet.Cell(3, 2).GetString());
            Assert.Equal(12500m, sheet.Cell(3, 5).GetValue<decimal>());
            Assert.Equal(SpreadsheetCatalogStub.SourceItemId.ToString(), sheet.Cell(3, 6).GetString());
        }

        using var importStream = new MemoryStream(exported.Content);
        var result = await service.ImportAsync(Guid.NewGuid(), importStream, CancellationToken.None);

        Assert.Equal(1, result.TotalRows);
        var row = Assert.Single(gateway.ImportedRows);
        Assert.Equal("Вентилятор", row.Item.Name);
        Assert.Equal(SpreadsheetCatalogStub.ItemId, row.ItemId);
        Assert.Equal("approved", row.Item.Status);
        Assert.Equal(12500m, row.Item.Values!["base_price"].GetDecimal());
        Assert.Equal(SpreadsheetCatalogStub.SourceItemId, Assert.Single(row.Relations).SourceItemId);
    }

    [Fact]
    public async Task BlankIdInTemplateCreatesANewImportRow()
    {
        var gateway = new SpreadsheetCatalogStub();
        var service = new CatalogSpreadsheetService(gateway);
        var template = await service.CreateTemplateAsync(
            SpreadsheetCatalogStub.CategoryId,
            CancellationToken.None);
        using var editable = new MemoryStream();
        using (var source = new MemoryStream(template.Content))
        using (var workbook = new XLWorkbook(source))
        {
            var sheet = workbook.Worksheet("Оборудование");
            sheet.Cell(3, 2).Value = "Новый вентилятор";
            sheet.Cell(3, 3).Value = "NEW-1";
            sheet.Cell(3, 5).Value = 15000m;
            workbook.SaveAs(editable);
        }
        editable.Position = 0;

        await service.ImportAsync(Guid.NewGuid(), editable, CancellationToken.None);

        var row = Assert.Single(gateway.ImportedRows);
        Assert.Null(row.ItemId);
        Assert.Equal("Новый вентилятор", row.Item.Name);
    }

    private sealed class SpreadsheetCatalogStub : ICatalogService
    {
        internal static readonly Guid CategoryId = Guid.Parse("11111111-1111-1111-1111-111111111111");
        private static readonly Guid SourceCategoryId = Guid.Parse("33333333-3333-3333-3333-333333333333");
        private static readonly Guid DependencyId = Guid.Parse("44444444-4444-4444-4444-444444444444");
        internal static readonly Guid ItemId = Guid.Parse("22222222-2222-2222-2222-222222222222");
        internal static readonly Guid SourceItemId = Guid.Parse("55555555-5555-5555-5555-555555555555");
        private static readonly CatalogConfiguration DefaultConfiguration = new(
            [
                new CatalogCategorySummary(
                    CategoryId,
                    "Оборудование",
                    0,
                    [
                        new CatalogFieldSummary("name", "Наименование", "text", true, true, 0, null),
                        new CatalogFieldSummary("marking", "Маркировка / размер", "text", true, false, 1, null),
                        new CatalogFieldSummary("base_price", "Цена", "money", true, true, 2, null),
                        new CatalogFieldSummary("work_link", "Связанные работы", "relation", true, false, 3, null),
                    ],
                    []),
                new CatalogCategorySummary(SourceCategoryId, "Работы", 1, [], []),
            ],
            [],
            [new CatalogDependencySummary(DependencyId, SourceCategoryId, CategoryId, "work_link", 0)]);

        private readonly CatalogConfiguration configuration;

        public SpreadsheetCatalogStub(CatalogConfiguration? configuration = null)
        {
            this.configuration = configuration ?? DefaultConfiguration;
        }

        public IReadOnlyList<CatalogImportRow> ImportedRows { get; private set; } = [];

        public Task<CatalogConfiguration> GetConfigurationAsync(CancellationToken cancellationToken) =>
            Task.FromResult(configuration);

        public Task<IReadOnlyList<CatalogItemSummary>> GetItemsForExportAsync(
            CatalogItemQuery query,
            CancellationToken cancellationToken) => Task.FromResult<IReadOnlyList<CatalogItemSummary>>(
            [new CatalogItemSummary(
                ItemId,
                CategoryId,
                null,
                null,
                "Вентилятор",
                "V-1",
                "approved",
                new Dictionary<string, JsonElement>
                {
                    ["base_price"] = JsonSerializer.SerializeToElement(12500m),
                },
                null,
                DateTimeOffset.UtcNow,
                null,
                DateTimeOffset.UtcNow)]);

        public Task<IReadOnlyDictionary<Guid, IReadOnlyList<CatalogItemRelationSummary>>> GetRelationsForExportAsync(
            IReadOnlyList<Guid> itemIds,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyDictionary<Guid, IReadOnlyList<CatalogItemRelationSummary>>>(
                new Dictionary<Guid, IReadOnlyList<CatalogItemRelationSummary>>
                {
                    [ItemId] =
                    [
                        new CatalogItemRelationSummary(
                            DependencyId,
                            SourceItemId,
                            "Монтаж",
                            "M-1",
                            0),
                    ],
                });

        public Task<CatalogImportResult> ImportItemsAsync(
            Guid actorUserId,
            IReadOnlyList<CatalogImportRow> rows,
            CancellationToken cancellationToken)
        {
            ImportedRows = rows;
            return Task.FromResult(new CatalogImportResult(rows.Count, rows.Count, 0));
        }

        public Task<CatalogItemPage> GetItemsAsync(CatalogItemQuery query, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<CatalogItemSummary> GetItemAsync(Guid itemId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<CatalogItemSummary> CreateItemAsync(Guid actorUserId, SaveCatalogItemRequest request, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<CatalogItemSummary> UpdateItemAsync(Guid actorUserId, Guid itemId, SaveCatalogItemRequest request, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task DeleteItemAsync(Guid actorUserId, Guid itemId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<IReadOnlyList<CatalogItemImageSummary>> GetImagesAsync(Guid itemId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<CatalogImageUploadTicket> BeginImageUploadAsync(Guid actorUserId, Guid itemId, BeginCatalogImageUploadRequest request, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<CatalogItemImageSummary> ConfirmImageUploadAsync(Guid actorUserId, Guid itemId, Guid imageId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task DeleteImageAsync(Guid actorUserId, Guid itemId, Guid imageId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<IReadOnlyList<CatalogItemRelationSummary>> GetRelationsAsync(Guid itemId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<IReadOnlyList<CatalogRelationCandidate>> SearchRelationCandidatesAsync(Guid dependencyId, string? search, int limit, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<IReadOnlyList<CatalogItemRelationSummary>> ReplaceRelationsAsync(Guid actorUserId, Guid itemId, IReadOnlyList<SaveCatalogItemRelationRequest> relations, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<CatalogBulkResult> ApplyBulkAsync(Guid actorUserId, CatalogBulkRequest request, CancellationToken cancellationToken) => throw new NotSupportedException();
    }
}
