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
    [Theory]
    [InlineData("import")]
    [InlineData("name_asc")]
    [InlineData("name_desc")]
    [InlineData("price_asc")]
    [InlineData("price_desc")]
    public async Task ExportPassesSortAndFiltersToCatalog(string sort)
    {
        var gateway = new SpreadsheetCatalogStub();
        var service = new CatalogSpreadsheetService(gateway);
        var query = new CatalogItemQuery(SpreadsheetCatalogStub.CategoryId, null, "approved", "Вентилятор", Sort: sort);
        var file = await service.ExportAsync(query, CancellationToken.None);
        Assert.Equal(query, gateway.ExportQueries[0]);
        using var stream = new MemoryStream(file.Content);
        using var book = new XLWorkbook(stream);
        Assert.Equal("Вентилятор", book.Worksheet("Оборудование").Cell(3, 2).GetString());
    }

    [Fact]
    public async Task ImportPreservesWorksheetRowOrder()
    {
        var gateway = new SpreadsheetCatalogStub();
        var service = new CatalogSpreadsheetService(gateway);
        var file = await service.CreateTemplateAsync(SpreadsheetCatalogStub.CategoryId, CancellationToken.None);
        using var input = new MemoryStream();
        using (var source = new MemoryStream(file.Content))
        using (var book = new XLWorkbook(source))
        {
            var sheet = book.Worksheet("Оборудование");
            foreach (var (row, name) in new[] { (3, "Ящик"), (4, "Болт"), (5, "Анкер") })
            {
                sheet.Cell(row, 2).Value = name;
                sheet.Cell(row, 3).Value = "M-1";
                sheet.Cell(row, 5).Value = 10m;
            }
            book.SaveAs(input);
        }
        input.Position = 0;
        await service.ImportAsync(Guid.NewGuid(), input, CancellationToken.None);
        Assert.Equal(["Ящик", "Болт", "Анкер"], gateway.ImportedRows.Select(row => row.Item.Name));
    }

    [Fact]
    public void SortUsesSystemFieldsAndRejectsUnknownSql()
    {
        Assert.Equal("item.sort_order, item.id", PostgresCatalogService.ItemOrderBy(null));
        Assert.Contains("lower(item.name) ASC, lower(item.marking) ASC", PostgresCatalogService.ItemOrderBy("name_asc"));
        Assert.Contains("lower(item.name) DESC, lower(item.marking) DESC", PostgresCatalogService.ItemOrderBy("name_desc"));
        Assert.Contains("::numeric END ASC NULLS LAST", PostgresCatalogService.ItemOrderBy("price_asc"));
        Assert.Contains("::numeric END DESC NULLS LAST", PostgresCatalogService.ItemOrderBy("price_desc"));
        Assert.Throws<SkladKomforta.Application.Identity.IdentityException>(() => PostgresCatalogService.ItemOrderBy("name; DELETE"));
    }

    [Fact]
    public async Task TemplateLinksNewTargetByRowWithoutTypingIds()
    {
        var gateway = new SpreadsheetCatalogStub();
        var service = new CatalogSpreadsheetService(gateway);
        var file = await service.CreateTemplateAsync(SpreadsheetCatalogStub.CategoryId, CancellationToken.None);
        using var input = new MemoryStream();
        using (var source = new MemoryStream(file.Content))
        using (var book = new XLWorkbook(source))
        {
            var product = book.Worksheet("Оборудование");
            product.Cell(3, 2).Value = "Новый товар";
            product.Cell(3, 3).Value = "NEW";
            product.Cell(3, 5).Value = 15000m;
            var choices = book.Worksheet("_catalog_choices");
            Assert.Equal(XLWorksheetVisibility.VeryHidden, choices.Visibility);
            var label = choices.Cell(1, 3).GetString();
            Assert.Contains("Монтаж | M-1 |", label);
            Assert.Contains("500,00", label);
            var links = book.Worksheet("Связи 1");
            links.Cell(4, 2).Value = label;
            links.Cell(4, 3).Value = 3;
            // Repeated rows must not create duplicate relations.
            links.Cell(5, 2).Value = label;
            links.Cell(5, 3).Value = 3;
            book.SaveAs(input);
        }
        input.Position = 0;
        await service.ImportAsync(Guid.NewGuid(), input, CancellationToken.None);
        var imported = Assert.Single(gateway.ImportedRows);
        Assert.Null(imported.ItemId);
        Assert.Equal(SpreadsheetCatalogStub.SourceItemId, Assert.Single(imported.Relations).SourceItemId);
    }

    [Theory]
    [InlineData("missing")]
    [InlineData("unknown")]
    [InlineData("target")]
    public async Task DamagedLinksRejectImportInsteadOfSilentlyRemovingLinks(string problem)
    {
        var gateway = new SpreadsheetCatalogStub();
        var service = new CatalogSpreadsheetService(gateway);
        var file = await service.ExportAsync(new CatalogItemQuery(null, null, null, null), CancellationToken.None);
        using var input = new MemoryStream();
        using (var source = new MemoryStream(file.Content))
        using (var book = new XLWorkbook(source))
        {
            if (problem == "missing") book.Worksheet("Связи 1").Delete();
            else book.Worksheet("Связи 1").Cell(4, problem == "target" ? 1 : 2).Value = "Неизвестный товар";
            book.SaveAs(input);
        }
        input.Position = 0;
        var error = await Assert.ThrowsAsync<SkladKomforta.Application.Identity.IdentityException>(
            () => service.ImportAsync(Guid.NewGuid(), input, CancellationToken.None));
        Assert.Equal("catalog_import_relation_invalid", error.Code);
        Assert.Empty(gateway.ImportedRows);
    }

    [Fact]
    public async Task LegacyUuidWorkbookStillImports()
    {
        var gateway = new SpreadsheetCatalogStub();
        var service = new CatalogSpreadsheetService(gateway);
        var file = await service.ExportAsync(new CatalogItemQuery(SpreadsheetCatalogStub.CategoryId, null, null, null), CancellationToken.None);
        using var input = new MemoryStream();
        using (var source = new MemoryStream(file.Content))
        using (var book = new XLWorkbook(source))
        {
            book.Worksheet("_catalog_meta").Cell(1, 2).Value = 2;
            var sheet = book.Worksheet("Оборудование");
            sheet.Cell(1, 6).Value = "Связанные работы (ID через ;)";
            sheet.Cell(2, 6).Value = "work_link";
            sheet.Cell(3, 6).Value = SpreadsheetCatalogStub.SourceItemId.ToString();
            book.SaveAs(input);
        }
        input.Position = 0;
        await service.ImportAsync(Guid.NewGuid(), input, CancellationToken.None);
        Assert.Equal(SpreadsheetCatalogStub.SourceItemId, Assert.Single(Assert.Single(gateway.ImportedRows).Relations).SourceItemId);
    }

    [Fact]
    public async Task IdenticalLabelsHaveDistinctChoicesAndPriceChangesDoNotRemapIds()
    {
        var gateway = new SpreadsheetCatalogStub();
        var sourceItem = (await gateway.GetItemsForExportAsync(new CatalogItemQuery(null, null, null, null), CancellationToken.None))[1];
        var duplicate = sourceItem with { Id = Guid.NewGuid() };
        gateway.ExtraCandidates = [duplicate];
        var service = new CatalogSpreadsheetService(gateway);
        var file = await service.ExportAsync(new CatalogItemQuery(SpreadsheetCatalogStub.CategoryId, null, null, null), CancellationToken.None);
        using var input = new MemoryStream();
        using (var source = new MemoryStream(file.Content))
        using (var book = new XLWorkbook(source))
        {
            var choices = book.Worksheet("_catalog_choices");
            var entries = choices.RowsUsed().Where(row => row.Cell(2).GetString() == "source").ToArray();
            Assert.Equal(2, entries.Length);
            Assert.NotEqual(entries[0].Cell(3).GetString(), entries[1].Cell(3).GetString());
            var chosen = entries.Single(row => row.Cell(4).GetString() == duplicate.Id.ToString());
            book.Worksheet("Связи 1").Cell(4, 2).Value = chosen.Cell(3).GetString();
            book.SaveAs(input);
        }
        gateway.ExtraCandidates = [duplicate with { Values = new Dictionary<string, JsonElement> { ["base_price"] = JsonSerializer.SerializeToElement(900m) } }];
        input.Position = 0;
        await service.ImportAsync(Guid.NewGuid(), input, CancellationToken.None);
        Assert.Equal(duplicate.Id, Assert.Single(Assert.Single(gateway.ImportedRows).Relations).SourceItemId);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task MultipleDependenciesForOneFieldExportAndImportAllLinks(bool categoryOnly)
    {
        var original = await new SpreadsheetCatalogStub().GetConfigurationAsync(CancellationToken.None);
        var sourceCategoryId = Guid.NewGuid();
        var dependencyId = Guid.NewGuid();
        var sourceId = Guid.NewGuid();
        var configuration = original with
        {
            Categories = [.. original.Categories, new CatalogCategorySummary(sourceCategoryId, "materials", "Материалы", 2, [], [])],
            Dependencies = [.. original.Dependencies, new CatalogDependencySummary(dependencyId, "materials-to-products", sourceCategoryId, SpreadsheetCatalogStub.CategoryId, "work_link", 1)],
        };
        var gateway = new SpreadsheetCatalogStub(configuration)
        {
            ExtraRelations = [new CatalogItemRelationSummary(dependencyId, sourceId, "Крепёж", "K-1", 1)],
        };
        var service = new CatalogSpreadsheetService(gateway);
        Guid? categoryId = categoryOnly ? SpreadsheetCatalogStub.CategoryId : null;
        var template = await service.CreateTemplateAsync(categoryId, CancellationToken.None);
        Assert.NotEmpty(template.Content);
        var exported = await service.ExportAsync(new CatalogItemQuery(categoryId, null, null, null), CancellationToken.None);
        using (var stream = new MemoryStream(exported.Content))
        using (var workbook = new XLWorkbook(stream))
        {
            var sheet = workbook.Worksheet("Оборудование");
            Assert.True(sheet.Column(1).IsHidden);
            Assert.Contains("Работы", workbook.Worksheet("Связи 1").Cell(1, 1).GetString());
            Assert.Contains("Материалы", workbook.Worksheet("Связи 2").Cell(1, 1).GetString());
            Assert.Contains("Монтаж | M-1 |", workbook.Worksheet("Связи 1").Cell(4, 2).GetString());
            Assert.Contains("Крепёж | K-1 |", workbook.Worksheet("Связи 2").Cell(4, 2).GetString());
        }
        using var input = new MemoryStream(exported.Content);
        await service.ImportAsync(Guid.NewGuid(), input, CancellationToken.None);
        var relations = Assert.Single(gateway.ImportedRows, row => row.ItemId == SpreadsheetCatalogStub.ItemId).Relations;
        Assert.Equal(2, relations.Count);
        Assert.Contains(relations, relation => relation.DependencyId == dependencyId && relation.SourceItemId == sourceId);
        Assert.Contains(relations, relation => relation.DependencyId == original.Dependencies[0].Id && relation.SourceItemId == SpreadsheetCatalogStub.SourceItemId);
    }

    [Fact]
    public async Task TemplateRequiresAtLeastOneConfiguredCategory()
    {
        var gateway = new SpreadsheetCatalogStub(new CatalogConfiguration([], [], [], [], []));
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
            Assert.Contains("Монтаж | M-1 |", workbook.Worksheet("Связи 1").Cell(4, 2).GetString());
        }

        using var importStream = new MemoryStream(exported.Content);
        var result = await service.ImportAsync(Guid.NewGuid(), importStream, CancellationToken.None);

        Assert.Equal(2, result.TotalRows);
        var row = Assert.Single(gateway.ImportedRows, item => item.ItemId == SpreadsheetCatalogStub.ItemId);
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
                    "equipment",
                    "Оборудование",
                    0,
                    [
                        new CatalogFieldSummary("name", "Наименование", "text", true, true, 0, null),
                        new CatalogFieldSummary("marking", "Маркировка / размер", "text", true, false, 1, null),
                        new CatalogFieldSummary("base_price", "Цена", "money", true, true, 2, null),
                        new CatalogFieldSummary("work_link", "Связанные работы", "relation", true, false, 3, null),
                    ],
                    []),
                new CatalogCategorySummary(SourceCategoryId, "works", "Работы", 1, [], []),
            ],
            [],
            [new CatalogDependencySummary(DependencyId, "works-to-products", SourceCategoryId, CategoryId, "work_link", 0)],
            [],
            []);

        private readonly CatalogConfiguration configuration;

        public SpreadsheetCatalogStub(CatalogConfiguration? configuration = null)
        {
            this.configuration = configuration ?? DefaultConfiguration;
        }

        public IReadOnlyList<CatalogImportRow> ImportedRows { get; private set; } = [];
        public List<CatalogItemQuery> ExportQueries { get; } = [];
        public IReadOnlyList<CatalogItemRelationSummary> ExtraRelations { get; init; } = [];
        public IReadOnlyList<CatalogItemSummary> ExtraCandidates { get; set; } = [];

        public Task<CatalogConfiguration> GetConfigurationAsync(CancellationToken cancellationToken) =>
            Task.FromResult(configuration);

        public Task<IReadOnlyList<CatalogItemSummary>> GetItemsForExportAsync(
            CatalogItemQuery query,
            CancellationToken cancellationToken)
        {
            ExportQueries.Add(query);
            var target = new CatalogItemSummary(
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
                DateTimeOffset.UtcNow);
            var sources = configuration.Dependencies.Select(dependency =>
            {
                var relation = ExtraRelations.FirstOrDefault(item => item.DependencyId == dependency.Id);
                return target with {
                    Id = relation?.SourceItemId ?? SourceItemId,
                    CategoryId = dependency.SourceCategoryId,
                    Name = relation?.SourceName ?? "Монтаж", Marking = relation?.SourceMarking ?? "M-1",
                    Values = new Dictionary<string, JsonElement> { ["base_price"] = JsonSerializer.SerializeToElement(500m) },
                };
            });
            return Task.FromResult<IReadOnlyList<CatalogItemSummary>>(
                new[] { target }.Concat(sources).Concat(ExtraCandidates).Where(item => query.CategoryId == null || item.CategoryId == query.CategoryId).ToArray());
        }

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
                        .. ExtraRelations,
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
