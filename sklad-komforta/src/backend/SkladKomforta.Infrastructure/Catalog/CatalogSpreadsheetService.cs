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
    private const string WorkbookMarker = "SKLAD_KOMFORTA_CATALOG";
    private const int FormatVersion = 1;
    private const int FirstDataRow = 3;

    /// <inheritdoc />
    public async Task<CatalogSpreadsheetFile> CreateTemplateAsync(
        Guid? categoryId,
        CancellationToken cancellationToken)
    {
        var configuration = await catalog.GetConfigurationAsync(cancellationToken);
        var categories = SelectCategories(configuration, categoryId);
        using var workbook = BuildWorkbook(configuration, categories, []);
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
        using var workbook = BuildWorkbook(configuration, categories, items.ToArray());
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
        CatalogItemSummary[] items)
    {
        var workbook = new XLWorkbook();
        var meta = workbook.Worksheets.Add(MetaSheetName);
        meta.Cell(1, 1).Value = WorkbookMarker;
        meta.Cell(1, 2).Value = FormatVersion;
        meta.Cell(2, 1).Value = "sheet";
        meta.Cell(2, 2).Value = "category_id";

        var usedNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { MetaSheetName };
        for (var index = 0; index < categories.Count; index++)
        {
            var category = categories[index];
            var sheetName = UniqueSheetName(category.Name, usedNames);
            meta.Cell(index + 3, 1).Value = sheetName;
            meta.Cell(index + 3, 2).Value = category.Id.ToString();
            var sheetItems = items.Where(item => item.CategoryId == category.Id).ToArray();
            BuildCategorySheet(workbook.Worksheets.Add(sheetName), configuration, category, sheetItems);
        }

        meta.Visibility = XLWorksheetVisibility.VeryHidden;
        return workbook;
    }

    private static void BuildCategorySheet(
        IXLWorksheet sheet,
        CatalogConfiguration configuration,
        CatalogCategorySummary category,
        CatalogItemSummary[] items)
    {
        var columns = BuildColumns(category);
        for (var column = 0; column < columns.Count; column++)
        {
            sheet.Cell(1, column + 1).Value = columns[column].Label;
            sheet.Cell(2, column + 1).Value = columns[column].Code;
        }

        sheet.Row(1).Style.Font.Bold = true;
        sheet.Row(1).Style.Fill.BackgroundColor = XLColor.FromHtml("#DCE9FF");
        sheet.Row(1).Style.Font.FontColor = XLColor.FromHtml("#183153");
        sheet.Row(2).Hide();
        sheet.SheetView.FreezeRows(2);

        for (var rowIndex = 0; rowIndex < items.Length; rowIndex++)
            WriteItem(sheet.Row(FirstDataRow + rowIndex), category, items[rowIndex], columns);

        var validationLastRow = Math.Max(FirstDataRow + items.Length + 200, 500);
        AddValidations(sheet, configuration, category, columns, validationLastRow);
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

    private static List<SheetColumn> BuildColumns(CatalogCategorySummary category)
    {
        var result = new List<SheetColumn>();
        if (category.Sections.Count > 0) result.Add(new("section", "Раздел", "text"));
        if (category.Sections.SelectMany(section => section.Groups).Any())
            result.Add(new("group", "Группа", "text"));
        result.Add(new("name", "Наименование", "text"));
        result.Add(new("marking", "Маркировка / размер", "text"));
        result.Add(new("status", "Статус", "enum"));
        result.AddRange(category.Fields
            .Where(field => field.IsVisible && field.FieldType is not ("relation" or "calculated_money") &&
                            field.Code is not ("group" or "name" or "marking"))
            .OrderBy(field => field.SortOrder)
            .Select(field => new SheetColumn(field.Code, field.Label, field.FieldType)));
        return result;
    }

    private static void WriteItem(
        IXLRow row,
        CatalogCategorySummary category,
        CatalogItemSummary item,
        IReadOnlyList<SheetColumn> columns)
    {
        var section = category.Sections.FirstOrDefault(value => value.Id == item.SectionId);
        var group = section?.Groups.FirstOrDefault(value => value.Id == item.GroupId);
        for (var index = 0; index < columns.Count; index++)
        {
            var column = columns[index];
            var cell = row.Cell(index + 1);
            switch (column.Code)
            {
                case "section": cell.Value = section?.Name ?? string.Empty; break;
                case "group": cell.Value = group?.Name ?? string.Empty; break;
                case "name": cell.Value = item.Name; break;
                case "marking": cell.Value = item.Marking; break;
                case "status": cell.Value = item.Status == "approved" ? "Согласовано" : "Не согласовано"; break;
                default:
                    if (item.Values.TryGetValue(column.Code, out var value)) WriteJsonValue(cell, value);
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
        CatalogConfiguration configuration,
        CatalogCategorySummary category,
        IReadOnlyList<SheetColumn> columns,
        int lastRow)
    {
        for (var index = 0; index < columns.Count; index++)
        {
            var column = columns[index];
            var range = sheet.Range(FirstDataRow, index + 1, lastRow, index + 1);
            IReadOnlyList<string>? allowed = column.Code switch
            {
                "section" => category.Sections.Select(item => item.Name).ToArray(),
                "group" => category.Sections.SelectMany(item => item.Groups).Select(item => item.Name).Distinct().ToArray(),
                "status" => ["Согласовано", "Не согласовано"],
                _ => DictionaryValues(configuration, category, column.Code),
            };
            if (allowed is { Count: > 0 } && string.Join(',', allowed).Length <= 240)
                range.CreateDataValidation().List(string.Join(',', allowed.Select(EscapeValidationValue)), true);
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
            meta.Cell(1, 2).GetValue<int>() != FormatVersion)
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
            ParseSheet(sheet, configuration, category, result);
        }
        return result;
    }

    private static void ParseSheet(
        IXLWorksheet sheet,
        CatalogConfiguration configuration,
        CatalogCategorySummary category,
        List<CatalogImportRow> output)
    {
        var lastColumn = sheet.LastColumnUsed()?.ColumnNumber() ?? 0;
        var codes = Enumerable.Range(1, lastColumn)
            .ToDictionary(column => sheet.Cell(2, column).GetString().Trim(), column => column, StringComparer.Ordinal);
        if (!codes.ContainsKey("name"))
            throw Invalid("catalog_import_template_invalid", $"Лист «{sheet.Name}» не содержит колонку наименования.");
        var allowedCodes = BuildColumns(category).Select(item => item.Code).ToHashSet(StringComparer.Ordinal);
        if (codes.Keys.Any(code => string.IsNullOrWhiteSpace(code) || !allowedCodes.Contains(code)))
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
            output.Add(new CatalogImportRow(
                sheet.Name,
                rowNumber,
                new SaveCatalogItemRequest(
                    category.Id,
                    section?.Id,
                    group?.Id,
                    name,
                    CellText(sheet, rowNumber, codes, "marking"),
                    ParseStatus(CellText(sheet, rowNumber, codes, "status"), sheet.Name, rowNumber),
                    values)));
        }
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

    private static string EscapeValidationValue(string value) => value.Replace(",", " ").Trim();

    private static IdentityException Invalid(string code, string message) => new(400, code, message);

    private sealed record SheetColumn(string Code, string Label, string FieldType);
}
