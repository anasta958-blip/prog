using System.Globalization;
using System.Text.Json;
using ClosedXML.Excel;
using SkladKomforta.Application.Catalog;
using SkladKomforta.Application.Identity;

namespace SkladKomforta.Infrastructure.Catalog;

/// <summary>
/// Создаёт и разбирает XLSX каталога. Видимая строка содержит русские названия,
/// а скрытая строка кодов делает формат устойчивым к переименованию заголовков.
/// Запись в PostgreSQL делегируется <see cref="ICatalogService"/>, поэтому ручное
/// редактирование и импорт используют одинаковую серверную валидацию.
/// </summary>
internal sealed class CatalogSpreadsheetService(ICatalogService catalog) : ICatalogSpreadsheetService
{
    private const string ContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    private const string MetaSheetName = "_catalog_meta";
    private const string ListsSheetName = "_catalog_lists";
    private const string WorkbookMarker = "SKLAD_KOMFORTA_CATALOG";
    private const int FormatVersion = 3;
    private const int FirstDataRow = 3;

    /// <inheritdoc />
    public async Task<CatalogSpreadsheetFile> CreateTemplateAsync(
        Guid? categoryId,
        CancellationToken cancellationToken)
    {
        var configuration = await catalog.GetConfigurationAsync(cancellationToken);
        var categories = SelectCategories(configuration, categoryId);
        var candidates = await catalog.GetItemsForExportAsync(new CatalogItemQuery(null, null, null, null), cancellationToken);
        using var workbook = BuildWorkbook(
            configuration,
            categories,
            [],
            new Dictionary<Guid, IReadOnlyList<CatalogItemRelationSummary>>(), candidates);
        return ToFile(workbook, "Шаблон каталога.xlsx");
    }

    /// <inheritdoc />
    public async Task<CatalogSpreadsheetFile> ExportAsync(
        CatalogItemQuery query,
        CancellationToken cancellationToken)
    {
        var configuration = await catalog.GetConfigurationAsync(cancellationToken);
        var categories = SelectCategories(configuration, query.CategoryId);
        var items = await catalog.GetItemsForExportAsync(query, cancellationToken);
        var relations = await catalog.GetRelationsForExportAsync(
            items.Select(item => item.Id).ToArray(), cancellationToken);
        var candidates = await catalog.GetItemsForExportAsync(new CatalogItemQuery(null, null, null, null), cancellationToken);
        using var workbook = BuildWorkbook(configuration, categories, items.ToArray(), relations, candidates);
        return ToFile(workbook, $"Каталог {DateTimeOffset.Now:yyyy-MM-dd HH-mm}.xlsx");
    }

    /// <inheritdoc />
    public async Task<CatalogImportResult> ImportAsync(
        Guid actorUserId,
        Stream content,
        CancellationToken cancellationToken)
    {
        if (!content.CanRead) throw Invalid("catalog_import_file_invalid", "Файл импорта недоступен для чтения.");
        var configuration = await catalog.GetConfigurationAsync(cancellationToken);
        try
        {
            using var workbook = new XLWorkbook(content);
            var rows = ParseWorkbook(workbook, configuration);
            return await catalog.ImportItemsAsync(actorUserId, rows, cancellationToken);
        }
        catch (IdentityException)
        {
            throw;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            throw Invalid("catalog_import_file_invalid", "Не удалось прочитать XLSX. Используйте актуальный шаблон каталога.");
        }
    }

    private static XLWorkbook BuildWorkbook(
        CatalogConfiguration configuration,
        IReadOnlyList<CatalogCategorySummary> categories,
        CatalogItemSummary[] items,
        IReadOnlyDictionary<Guid, IReadOnlyList<CatalogItemRelationSummary>> relations,
        IReadOnlyList<CatalogItemSummary> candidates)
    {
        var workbook = new XLWorkbook();
        var meta = workbook.Worksheets.Add(MetaSheetName);
        var lists = workbook.Worksheets.Add(ListsSheetName);
        meta.Cell(1, 1).Value = WorkbookMarker;
        meta.Cell(1, 2).Value = FormatVersion;
        meta.Cell(2, 1).Value = "sheet";
        meta.Cell(2, 2).Value = "category_id";

        var usedNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            MetaSheetName,
            ListsSheetName,
            CatalogSpreadsheetLinks.MetaName,
            CatalogSpreadsheetLinks.ChoicesName,
        };
        var categorySheets = new Dictionary<Guid, string>();
        var validationListIndex = 0;
        for (var index = 0; index < categories.Count; index++)
        {
            var category = categories[index];
            var sheetName = UniqueSheetName(category.Name, usedNames);
            categorySheets.Add(category.Id, sheetName);
            meta.Cell(index + 3, 1).Value = sheetName;
            meta.Cell(index + 3, 2).Value = category.Id.ToString();
            var sheetItems = items.Where(item => item.CategoryId == category.Id).ToArray();
            BuildCategorySheet(
                workbook.Worksheets.Add(sheetName),
                lists,
                configuration,
                category,
                sheetItems,
                relations,
                ref validationListIndex);
        }

        meta.Visibility = XLWorksheetVisibility.VeryHidden;
        lists.Visibility = XLWorksheetVisibility.VeryHidden;
        CatalogSpreadsheetLinks.Write(workbook, configuration, categorySheets, items, candidates, relations,
            name => UniqueSheetName(name, usedNames));
        return workbook;
    }

    private static void BuildCategorySheet(
        IXLWorksheet sheet,
        IXLWorksheet lists,
        CatalogConfiguration configuration,
        CatalogCategorySummary category,
        CatalogItemSummary[] items,
        IReadOnlyDictionary<Guid, IReadOnlyList<CatalogItemRelationSummary>> relations,
        ref int validationListIndex)
    {
        var columns = BuildColumns(configuration, category, false);
        for (var column = 0; column < columns.Count; column++)
        {
            sheet.Cell(1, column + 1).Value = columns[column].Label;
            sheet.Cell(2, column + 1).Value = columns[column].Code;
        }

        sheet.Row(1).Style.Font.Bold = true;
        sheet.Row(1).Style.Fill.BackgroundColor = XLColor.FromHtml("#DCE9FF");
        sheet.Row(1).Style.Font.FontColor = XLColor.FromHtml("#183153");
        sheet.Row(2).Hide();
        sheet.Column(1).Hide();
        sheet.SheetView.FreezeRows(2);

        for (var rowIndex = 0; rowIndex < items.Length; rowIndex++)
            WriteItem(
                sheet.Row(FirstDataRow + rowIndex),
                category,
                items[rowIndex],
                columns,
                relations);

        var validationLastRow = Math.Max(FirstDataRow + items.Length + 200, 500);
        AddValidations(
            sheet,
            lists,
            configuration,
            category,
            columns,
            validationLastRow,
            ref validationListIndex);
        var lastColumn = columns.Count;
        sheet.Range(1, 1, Math.Max(FirstDataRow, FirstDataRow + items.Length - 1), lastColumn)
            .Style.Border.OutsideBorder = XLBorderStyleValues.Thin;
        sheet.Range(1, 1, Math.Max(FirstDataRow, FirstDataRow + items.Length - 1), lastColumn)
            .Style.Border.InsideBorder = XLBorderStyleValues.Hair;
        sheet.Range(1, 1, 1, lastColumn).SetAutoFilter();
        sheet.Columns(1, lastColumn).AdjustToContents();
        foreach (var column in sheet.Columns(1, lastColumn))
        {
            if (column.Width < 12) column.Width = 12;
            if (column.Width > 36) column.Width = 36;
        }
    }

    private static List<SheetColumn> BuildColumns(
        CatalogConfiguration configuration,
        CatalogCategorySummary category,
        bool includeRelations = true)
    {
        var result = new List<SheetColumn> { new("id", "ID", "id") };
        if (category.Sections.Count > 0) result.Add(new("section", "Раздел", "text"));
        if (category.Sections.SelectMany(section => section.Groups).Any())
            result.Add(new("group", "Группа", "text"));
        result.Add(new("name", "Наименование", "text"));
        result.Add(new("marking", "Маркировка / размер", "text"));
        result.Add(new("status", "Статус", "enum"));
        result.AddRange(category.Fields
            .Where(field => field.IsVisible && field.FieldType != "calculated_money" &&
                            (includeRelations || field.FieldType != "relation") &&
                            field.Code is not ("group" or "name" or "marking"))
            .OrderBy(field => field.SortOrder)
            .SelectMany(field => BuildFieldColumns(configuration, category.Id, field)));
        return result;
    }

    private static void WriteItem(
        IXLRow row,
        CatalogCategorySummary category,
        CatalogItemSummary item,
        IReadOnlyList<SheetColumn> columns,
        IReadOnlyDictionary<Guid, IReadOnlyList<CatalogItemRelationSummary>> relations)
    {
        var section = category.Sections.FirstOrDefault(value => value.Id == item.SectionId);
        var group = section?.Groups.FirstOrDefault(value => value.Id == item.GroupId);
        for (var index = 0; index < columns.Count; index++)
        {
            var column = columns[index];
            var cell = row.Cell(index + 1);
            switch (column.Code)
            {
                case "id": cell.Value = item.Id.ToString(); break;
                case "section": cell.Value = section?.Name ?? string.Empty; break;
                case "group": cell.Value = group?.Name ?? string.Empty; break;
                case "name": cell.Value = item.Name; break;
                case "marking": cell.Value = item.Marking; break;
                case "status": cell.Value = item.Status == "approved" ? "Согласовано" : "Не согласовано"; break;
                default:
                    if (column.FieldType == "relation" && column.DependencyId.HasValue)
                    {
                        cell.Value = relations.TryGetValue(item.Id, out var itemRelations)
                            ? string.Join("; ", itemRelations
                                .Where(relation => relation.DependencyId == column.DependencyId.Value)
                                .Select(relation => relation.SourceItemId))
                            : string.Empty;
                    }
                    else if (item.Values.TryGetValue(column.Code, out var value))
                    {
                        WriteJsonValue(cell, value);
                    }
                    break;
            }
        }
    }

    private static void WriteJsonValue(IXLCell cell, JsonElement value)
    {
        switch (value.ValueKind)
        {
            case JsonValueKind.String: cell.Value = value.GetString() ?? string.Empty; break;
            case JsonValueKind.Number when value.TryGetDecimal(out var number): cell.Value = number; break;
            case JsonValueKind.True: cell.Value = true; break;
            case JsonValueKind.False: cell.Value = false; break;
        }
    }

    private static void AddValidations(
        IXLWorksheet sheet,
        IXLWorksheet lists,
        CatalogConfiguration configuration,
        CatalogCategorySummary category,
        IReadOnlyList<SheetColumn> columns,
        int lastRow,
        ref int validationListIndex)
    {
        for (var index = 0; index < columns.Count; index++)
        {
            var column = columns[index];
            var range = sheet.Range(FirstDataRow, index + 1, lastRow, index + 1);
            string[]? allowed = column.Code switch
            {
                "section" => category.Sections.Select(item => item.Name).ToArray(),
                "group" => category.Sections.SelectMany(item => item.Groups).Select(item => item.Name).Distinct().ToArray(),
                "status" => ["Согласовано", "Не согласовано"],
                _ => DictionaryValues(configuration, category, column.Code),
            };
            if (allowed is not { Length: > 0 }) continue;

            validationListIndex++;
            var listColumn = validationListIndex;
            for (var row = 0; row < allowed.Length; row++)
                lists.Cell(row + 1, listColumn).Value = allowed[row];
            var listRange = lists.Range(1, listColumn, allowed.Length, listColumn);
            var rangeName = $"catalog_list_{validationListIndex}";
            sheet.Workbook.DefinedNames.Add(rangeName, listRange);
            range.CreateDataValidation().List(rangeName, true);
        }
    }

    private static IEnumerable<SheetColumn> BuildFieldColumns(
        CatalogConfiguration configuration,
        Guid targetCategoryId,
        CatalogFieldSummary field)
    {
        if (field.FieldType != "relation")
        {
            yield return new SheetColumn(field.Code, field.Label, field.FieldType);
            yield break;
        }
        var dependencies = configuration.Dependencies
            .Where(dependency => dependency.TargetCategoryId == targetCategoryId &&
                                 dependency.TargetFieldCode == field.Code)
            .OrderBy(dependency => dependency.SortOrder).ThenBy(dependency => dependency.Id)
            .ToArray();
        if (dependencies.Length == 0)
            throw Invalid("catalog_dependency_invalid",
                $"Для поля связи «{field.Code}» не настроена зависимость категорий.");
        foreach (var dependency in dependencies)
        {
            // Keep the existing single-dependency format; distinguish all others for lossless import.
            var sourceName = configuration.Categories
                .FirstOrDefault(category => category.Id == dependency.SourceCategoryId)?.Name
                ?? dependency.SourceCategoryId.ToString();
            yield return new SheetColumn(
                dependencies.Length == 1 ? field.Code : $"{field.Code}:{dependency.Id:D}",
                dependencies.Length == 1 ? $"{field.Label} (ID через ;)" : $"{field.Label}: {sourceName} (ID через ;)",
                field.FieldType, dependency.Id);
        }
    }

    private static string[]? DictionaryValues(
        CatalogConfiguration configuration,
        CatalogCategorySummary category,
        string fieldCode)
    {
        var field = category.Fields.FirstOrDefault(value => value.Code == fieldCode);
        if (field?.FieldType != "dictionary" || string.IsNullOrWhiteSpace(field.DictionaryCode)) return null;
        return configuration.Dictionaries
            .FirstOrDefault(value => value.Code == field.DictionaryCode)?.Items
            .Select(value => value.Value)
            .ToArray();
    }

    private static List<CatalogImportRow> ParseWorkbook(
        XLWorkbook workbook,
        CatalogConfiguration configuration)
    {
        if (!workbook.TryGetWorksheet(MetaSheetName, out var meta) ||
            meta.Cell(1, 1).GetString() != WorkbookMarker ||
            meta.Cell(1, 2).GetValue<int>() is not (2 or FormatVersion))
            throw Invalid("catalog_import_template_invalid", "Файл создан не из актуального шаблона каталога.");

        var result = new List<CatalogImportRow>();
        var lastMetaRow = meta.LastRowUsed()?.RowNumber() ?? 2;
        for (var metaRow = 3; metaRow <= lastMetaRow; metaRow++)
        {
            var sheetName = meta.Cell(metaRow, 1).GetString();
            if (!Guid.TryParse(meta.Cell(metaRow, 2).GetString(), out var categoryId))
                throw Invalid("catalog_import_template_invalid", "В шаблоне повреждена категория.");
            var category = configuration.Categories.FirstOrDefault(value => value.Id == categoryId)
                ?? throw Invalid("catalog_import_category_missing", $"Категория листа «{sheetName}» больше не существует.");
            if (!workbook.TryGetWorksheet(sheetName, out var sheet))
                throw Invalid("catalog_import_template_invalid", $"В книге отсутствует лист «{sheetName}».");
            ParseSheet(sheet, configuration, category, result, meta.Cell(1, 2).GetValue<int>() == 2);
        }
        if (meta.Cell(1, 2).GetValue<int>() == FormatVersion)
            CatalogSpreadsheetLinks.Read(workbook, configuration, result);
        return result;
    }

    private static void ParseSheet(
        IXLWorksheet sheet,
        CatalogConfiguration configuration,
        CatalogCategorySummary category,
        List<CatalogImportRow> output,
        bool legacy)
    {
        var lastColumn = sheet.LastColumnUsed()?.ColumnNumber() ?? 0;
        var codes = Enumerable.Range(1, lastColumn)
            .ToDictionary(column => sheet.Cell(2, column).GetString().Trim(), column => column, StringComparer.Ordinal);
        if (!codes.ContainsKey("name"))
            throw Invalid("catalog_import_template_invalid", $"Лист «{sheet.Name}» не содержит колонку наименования.");
        var columns = BuildColumns(configuration, category, legacy);
        var allowedCodes = columns.Select(item => item.Code).ToHashSet(StringComparer.Ordinal);
        if (codes.Count != allowedCodes.Count ||
            codes.Keys.Any(code => string.IsNullOrWhiteSpace(code) || !allowedCodes.Contains(code)))
            throw Invalid("catalog_import_template_invalid", $"Структура колонок листа «{sheet.Name}» изменена.");

        var lastRow = sheet.LastRowUsed()?.RowNumber() ?? 2;
        for (var rowNumber = FirstDataRow; rowNumber <= lastRow; rowNumber++)
        {
            var name = CellText(sheet, rowNumber, codes, "name");
            if (string.IsNullOrWhiteSpace(name))
            {
                if (codes.Values.All(column => sheet.Cell(rowNumber, column).IsEmpty())) continue;
                throw Invalid("catalog_import_row_invalid", $"Лист «{sheet.Name}», строка {rowNumber}: укажите наименование.");
            }
            var section = ResolveSection(category, CellText(sheet, rowNumber, codes, "section"), sheet.Name, rowNumber);
            var group = ResolveGroup(section, CellText(sheet, rowNumber, codes, "group"), sheet.Name, rowNumber);
            var itemId = ParseOptionalId(CellText(sheet, rowNumber, codes, "id"), sheet.Name, rowNumber);
            var values = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var field in category.Fields.Where(field =>
                         field.Code is not ("group" or "name" or "marking") &&
                         field.FieldType is not ("relation" or "calculated_money") &&
                         codes.ContainsKey(field.Code)))
            {
                var cell = sheet.Cell(rowNumber, codes[field.Code]);
                if (cell.IsEmpty()) continue;
                values[field.Code] = ParseValue(cell, field, configuration, sheet.Name, rowNumber);
            }
            var relations = columns
                .Where(column => column.FieldType == "relation" && column.DependencyId.HasValue)
                .SelectMany(column => ParseRelationIds(
                    CellText(sheet, rowNumber, codes, column.Code),
                    column.DependencyId!.Value,
                    column.Label,
                    sheet.Name,
                    rowNumber))
                .ToArray();
            output.Add(new CatalogImportRow(
                sheet.Name,
                rowNumber,
                itemId,
                new SaveCatalogItemRequest(
                    category.Id,
                    section?.Id,
                    group?.Id,
                    name,
                    CellText(sheet, rowNumber, codes, "marking"),
                    ParseStatus(CellText(sheet, rowNumber, codes, "status"), sheet.Name, rowNumber),
                    values),
                relations));
        }
    }

    private static Guid? ParseOptionalId(
        string value,
        string sheetName,
        int rowNumber)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        return Guid.TryParse(value, out var itemId)
            ? itemId
            : throw Invalid(
                "catalog_import_id_invalid",
                $"Лист «{sheetName}», строка {rowNumber}: ID карточки имеет неверный формат.");
    }

    private static List<SaveCatalogItemRelationRequest> ParseRelationIds(
        string value,
        Guid dependencyId,
        string fieldLabel,
        string sheetName,
        int rowNumber)
    {
        if (string.IsNullOrWhiteSpace(value)) return [];
        var result = new List<SaveCatalogItemRelationRequest>();
        foreach (var token in value.Split([';', ',', '\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (!Guid.TryParse(token, out var sourceItemId))
                throw Invalid(
                    "catalog_import_relation_invalid",
                    $"Лист «{sheetName}», строка {rowNumber}, поле «{fieldLabel}»: укажите UUID связанных карточек через точку с запятой.");
            result.Add(new SaveCatalogItemRelationRequest(dependencyId, sourceItemId));
        }
        return result;
    }

    private static JsonElement ParseValue(
        IXLCell cell,
        CatalogFieldSummary field,
        CatalogConfiguration configuration,
        string sheetName,
        int rowNumber)
    {
        try
        {
            return field.FieldType switch
            {
                "number" or "money" or "percent" => JsonSerializer.SerializeToElement(ParseDecimal(cell.GetString())),
                "boolean" => JsonSerializer.SerializeToElement(ParseBoolean(cell.GetString())),
                "dictionary" => JsonSerializer.SerializeToElement(ParseDictionary(cell.GetString(), field, configuration)),
                _ => JsonSerializer.SerializeToElement(cell.GetString().Trim()),
            };
        }
        catch (FormatException exception)
        {
            throw Invalid("catalog_import_value_invalid", $"Лист «{sheetName}», строка {rowNumber}, поле «{field.Label}»: {exception.Message}");
        }
    }

    private static decimal ParseDecimal(string value) =>
        decimal.TryParse(value.Trim().Replace(',', '.'), NumberStyles.Number, CultureInfo.InvariantCulture, out var result)
            ? result
            : throw new FormatException("введите число.");

    private static bool ParseBoolean(string value) => value.Trim().ToLowerInvariant() switch
    {
        "да" or "true" or "1" => true,
        "нет" or "false" or "0" => false,
        _ => throw new FormatException("используйте «Да» или «Нет».")
    };

    private static string ParseDictionary(
        string value,
        CatalogFieldSummary field,
        CatalogConfiguration configuration)
    {
        var normalized = value.Trim();
        var dictionary = configuration.Dictionaries.FirstOrDefault(item => item.Code == field.DictionaryCode)
            ?? throw new FormatException("справочник поля больше не существует.");
        return dictionary.Items.Any(item => string.Equals(item.Value, normalized, StringComparison.OrdinalIgnoreCase))
            ? dictionary.Items.First(item => string.Equals(item.Value, normalized, StringComparison.OrdinalIgnoreCase)).Value
            : throw new FormatException("значение отсутствует в назначенном справочнике.");
    }

    private static CatalogSectionSummary? ResolveSection(
        CatalogCategorySummary category,
        string value,
        string sheetName,
        int rowNumber)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        return category.Sections.FirstOrDefault(item => string.Equals(item.Name, value.Trim(), StringComparison.OrdinalIgnoreCase))
            ?? throw Invalid("catalog_import_section_invalid", $"Лист «{sheetName}», строка {rowNumber}: раздел «{value}» не найден.");
    }

    private static CatalogGroupSummary? ResolveGroup(
        CatalogSectionSummary? section,
        string value,
        string sheetName,
        int rowNumber)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        return section?.Groups.FirstOrDefault(item => string.Equals(item.Name, value.Trim(), StringComparison.OrdinalIgnoreCase))
            ?? throw Invalid("catalog_import_group_invalid", $"Лист «{sheetName}», строка {rowNumber}: группа «{value}» не найдена в выбранном разделе.");
    }

    private static string ParseStatus(string value, string sheetName, int rowNumber) => value.Trim().ToLowerInvariant() switch
    {
        "" or "не согласовано" or "pending" => "pending",
        "согласовано" or "approved" => "approved",
        _ => throw Invalid("catalog_import_status_invalid", $"Лист «{sheetName}», строка {rowNumber}: неизвестный статус «{value}».")
    };

    private static string CellText(IXLWorksheet sheet, int row, Dictionary<string, int> codes, string code) =>
        codes.TryGetValue(code, out var column) ? sheet.Cell(row, column).GetString().Trim() : string.Empty;

    private static IReadOnlyList<CatalogCategorySummary> SelectCategories(
        CatalogConfiguration configuration,
        Guid? categoryId)
    {
        if (configuration.Categories.Count == 0)
            throw Invalid("catalog_categories_empty", "Сначала настройте хотя бы одну категорию каталога.");
        if (categoryId is null) return configuration.Categories;
        var category = configuration.Categories.FirstOrDefault(item => item.Id == categoryId.Value)
            ?? throw Invalid("catalog_category_invalid", "Категория каталога не найдена.");
        return [category];
    }

    private static CatalogSpreadsheetFile ToFile(XLWorkbook workbook, string fileName)
    {
        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return new CatalogSpreadsheetFile(fileName, ContentType, stream.ToArray());
    }

    private static string UniqueSheetName(string source, HashSet<string> used)
    {
        var clean = string.Concat(source.Trim().Select(character => "[]:*?/\\".Contains(character) ? '_' : character));
        if (string.IsNullOrWhiteSpace(clean)) clean = "Категория";
        clean = clean[..Math.Min(31, clean.Length)];
        var candidate = clean;
        var suffix = 2;
        while (!used.Add(candidate))
        {
            var tail = $" ({suffix++})";
            candidate = clean[..Math.Min(clean.Length, 31 - tail.Length)] + tail;
        }
        return candidate;
    }

    private static IdentityException Invalid(string code, string message) => new(400, code, message);

    private sealed record SheetColumn(
        string Code,
        string Label,
        string FieldType,
        Guid? DependencyId = null);
}
