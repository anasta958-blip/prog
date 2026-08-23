using System.Text.Json;
using ClosedXML.Excel;
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

        using (var stream = new MemoryStream(exported.Content))
        using (var workbook = new XLWorkbook(stream))
        {
            var sheet = workbook.Worksheet("Оборудование");
            Assert.Equal("Наименование", sheet.Cell(1, 1).GetString());
            Assert.Equal("name", sheet.Cell(2, 1).GetString());
            Assert.Equal("Вентилятор", sheet.Cell(3, 1).GetString());
            Assert.Equal(12500m, sheet.Cell(3, 4).GetValue<decimal>());
        }

        using var importStream = new MemoryStream(exported.Content);
        var result = await service.ImportAsync(Guid.NewGuid(), importStream, CancellationToken.None);

        Assert.Equal(1, result.TotalRows);
        var row = Assert.Single(gateway.ImportedRows);
        Assert.Equal("Вентилятор", row.Item.Name);
        Assert.Equal("approved", row.Item.Status);
        Assert.Equal(12500m, row.Item.Values!["base_price"].GetDecimal());
    }

    private sealed class SpreadsheetCatalogStub : ICatalogService
    {
        private static readonly Guid CategoryId = Guid.Parse("11111111-1111-1111-1111-111111111111");
        private static readonly CatalogConfiguration DefaultConfiguration = new(
            [new CatalogCategorySummary(
                CategoryId,
                "Оборудование",
                0,
                [
                    new CatalogFieldSummary("name", "Наименование", "text", true, true, 0, null),
                    new CatalogFieldSummary("marking", "Маркировка / размер", "text", true, false, 1, null),
                    new CatalogFieldSummary("base_price", "Цена", "money", true, true, 2, null),
                ],
                [])],
            [],
            []);

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
                Guid.Parse("22222222-2222-2222-2222-222222222222"),
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
