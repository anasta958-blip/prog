using System.Globalization;
using ClosedXML.Excel;
using SkladKomforta.Application.Catalog;
using SkladKomforta.Application.Identity;

namespace SkladKomforta.Infrastructure.Catalog;

internal static class CatalogSpreadsheetLinks
{
    internal const string MetaName = "_catalog_links";
    internal const string ChoicesName = "_catalog_choices";

    internal static void Write(
        XLWorkbook book, CatalogConfiguration config, IReadOnlyDictionary<Guid, string> categorySheets,
        IReadOnlyList<CatalogItemSummary> targets, IReadOnlyList<CatalogItemSummary> candidates,
        IReadOnlyDictionary<Guid, IReadOnlyList<CatalogItemRelationSummary>> relations,
        Func<string, string> sheetName)
    {
        var meta = book.AddWorksheet(MetaName);
        var choices = book.AddWorksheet(ChoicesName);
        var metadataRow = 1;
        var choiceRow = 1;
        var listColumn = 6;
        foreach (var dependency in config.Dependencies.Where(item => categorySheets.ContainsKey(item.TargetCategoryId)))
        {
            var targetCategory = config.Categories.First(item => item.Id == dependency.TargetCategoryId);
            var sourceCategory = config.Categories.First(item => item.Id == dependency.SourceCategoryId);
            var name = sheetName($"Связи {metadataRow}");
            var sheet = book.AddWorksheet(name);
            meta.Cell(metadataRow, 1).Value = name;
            meta.Cell(metadataRow, 2).Value = dependency.Id.ToString();
            meta.Cell(metadataRow, 3).Value = categorySheets[dependency.TargetCategoryId];
            metadataRow++;
            sheet.Cell(1, 1).Value = $"{targetCategory.Name} → {sourceCategory.Name}";
            sheet.Range(1, 1, 1, 3).Merge();
            sheet.Cell(2, 1).Value = $"Одна строка = одна связь. Выберите товар в A или укажите в C номер строки на листе «{categorySheets[dependency.TargetCategoryId]}». В B выберите связанную позицию. Удаление строки снимает связь.";
            sheet.Range(2, 1, 2, 3).Merge().Style.Alignment.WrapText = true;
            sheet.Row(2).Height = 60;
            sheet.Cell(3, 1).Value = "Основной товар";
            sheet.Cell(3, 2).Value = "Связанная позиция";
            sheet.Cell(3, 3).Value = "Строка товара (вместо A)";
            sheet.Range(3, 1, 3, 3).Style.Fill.BackgroundColor = XLColor.FromHtml("#DCE9FF");
            sheet.Range(3, 1, 3, 3).Style.Font.Bold = true;
            sheet.Column(1).Width = 58;
            sheet.Column(2).Width = 58;
            sheet.Column(3).Width = 28;
            sheet.SheetView.FreezeRows(3);
            var targetLabels = Labels(targets.Where(item => item.CategoryId == dependency.TargetCategoryId));
            var sourceLabels = Labels(candidates.Where(item => item.CategoryId == dependency.SourceCategoryId));
            var row = 4;
            foreach (var target in targetLabels)
            {
                foreach (var relation in relations.GetValueOrDefault(target.Key) ?? [])
                {
                    if (relation.DependencyId != dependency.Id) continue;
                    if (!sourceLabels.TryGetValue(relation.SourceItemId, out var label))
                        throw Invalid($"Связанная позиция «{relation.SourceName}» недоступна. Обновите каталог и повторите экспорт.");
                    sheet.Cell(row, 1).Value = target.Value;
                    sheet.Cell(row++, 2).Value = label;
                }
            }
            var lastRow = Math.Max(2000, row + 500);
            AddChoices(targetLabels, "target", 1);
            AddChoices(sourceLabels, "source", 2);

            void AddChoices(Dictionary<Guid, string> labels, string side, int column)
            {
                if (labels.Count == 0) return;
                var listRow = 1;
                foreach (var label in labels)
                {
                    choices.Cell(choiceRow, 1).Value = name;
                    choices.Cell(choiceRow, 2).Value = side;
                    choices.Cell(choiceRow, 3).Value = label.Value;
                    choices.Cell(choiceRow++, 4).Value = label.Key.ToString();
                    choices.Cell(listRow++, listColumn).Value = label.Value;
                }
                var rangeName = $"catalog_list_links_{listColumn}";
                book.DefinedNames.Add(rangeName, choices.Range(1, listColumn, labels.Count, listColumn));
                sheet.Range(4, column, lastRow, column).CreateDataValidation().List(rangeName, true);
                listColumn++;
            }
        }
        // A marker distinguishes an intentionally empty registry from a removed registry.
        meta.Cell(1, 5).Value = "LINKS_V3";
        meta.Visibility = XLWorksheetVisibility.VeryHidden;
        choices.Visibility = XLWorksheetVisibility.VeryHidden;
    }

    private static Dictionary<Guid, string> Labels(IEnumerable<CatalogItemSummary> items)
    {
        var result = new Dictionary<Guid, string>();
        var index = 0;
        foreach (var item in items.OrderBy(item => item.Name, StringComparer.Ordinal).ThenBy(item => item.Id))
        {
            var price = item.Values.TryGetValue("base_price", out var value) && value.ValueKind == System.Text.Json.JsonValueKind.Number && value.TryGetDecimal(out var number)
                ? number.ToString("N2", CultureInfo.GetCultureInfo("ru-RU")) + " ₽" : "цена не указана";
            result.Add(item.Id, $"{item.Name} | {item.Marking} | {price} [№{++index}]");
        }
        return result;
    }

    internal static void Read(XLWorkbook book, CatalogConfiguration config, List<CatalogImportRow> rows)
    {
        if (!book.TryGetWorksheet(MetaName, out var meta) || meta.Cell(1, 5).GetString() != "LINKS_V3" ||
            !book.TryGetWorksheet(ChoicesName, out var choices))
            throw Invalid("Повреждён справочник связей. Скачайте новый шаблон.");
        var labels = new Dictionary<(string Sheet, string Side, string Label), Guid>();
        for (var r = 1; r <= (choices.LastRowUsed()?.RowNumber() ?? 0); r++)
        {
            if (choices.Cell(r, 1).IsEmpty()) continue;
            if (!Guid.TryParse(choices.Cell(r, 4).GetString(), out var id) ||
                !labels.TryAdd((choices.Cell(r, 1).GetString(), choices.Cell(r, 2).GetString(), choices.Cell(r, 3).GetString()), id))
                throw Invalid("Повреждён справочник выбора товаров.");
        }
        var expected = config.Dependencies.Where(dependency => rows.Any(row => row.Item.CategoryId == dependency.TargetCategoryId))
            .Select(dependency => dependency.Id).ToHashSet();
        var seen = new HashSet<Guid>();
        for (var m = 1; m <= (meta.LastRowUsed()?.RowNumber() ?? 0); m++)
        {
            var name = meta.Cell(m, 1).GetString();
            if (name.Length == 0) continue;
            if (!Guid.TryParse(meta.Cell(m, 2).GetString(), out var dependencyId) || !seen.Add(dependencyId))
                throw Invalid("Повреждены настройки листов связей.");
            var dependency = config.Dependencies.FirstOrDefault(item => item.Id == dependencyId)
                ?? throw Invalid($"Зависимость листа «{name}» изменилась. Скачайте новый шаблон.");
            if (!book.TryGetWorksheet(name, out var sheet))
                throw Invalid($"Отсутствует лист «{name}». Восстановите его, чтобы не потерять связи.");
            for (var r = 4; r <= (sheet.LastRowUsed()?.RowNumber() ?? 3); r++)
            {
                var target = sheet.Cell(r, 1).GetString().Trim();
                var source = sheet.Cell(r, 2).GetString().Trim();
                var number = sheet.Cell(r, 3).GetString().Trim();
                if (target.Length + source.Length + number.Length == 0) continue;
                if (source.Length == 0 || (target.Length == 0) == (number.Length == 0))
                    throw RowError(name, r, "выберите связанную позицию и заполните только A или C.");
                if (!labels.TryGetValue((name, "source", source), out var sourceId))
                    throw RowError(name, r, "связанная позиция отсутствует в выпадающем списке.");
                List<int> matches;
                if (target.Length > 0)
                {
                    if (!labels.TryGetValue((name, "target", target), out var targetId))
                        throw RowError(name, r, "основной товар отсутствует в выпадающем списке.");
                    matches = Enumerable.Range(0, rows.Count).Where(i => rows[i].ItemId == targetId).ToList();
                }
                else
                {
                    if (!int.TryParse(number, out var rowNumber) || rowNumber < 3)
                        throw RowError(name, r, "укажите номер строки товара, начиная с 3.");
                    matches = Enumerable.Range(0, rows.Count).Where(i => rows[i].SheetName == meta.Cell(m, 3).GetString() && rows[i].RowNumber == rowNumber).ToList();
                }
                if (matches.Count != 1 || rows[matches[0]].Item.CategoryId != dependency.TargetCategoryId)
                    throw RowError(name, r, "основной товар не найден на листе категории или указан неоднозначно.");
                var index = matches[0];
                var relation = new SaveCatalogItemRelationRequest(dependencyId, sourceId);
                if (!rows[index].Relations.Contains(relation))
                    rows[index] = rows[index] with { Relations = [.. rows[index].Relations, relation] };
            }
        }
        if (!expected.IsSubsetOf(seen)) throw Invalid("Набор зависимостей изменился. Скачайте новый шаблон связей.");
    }

    private static IdentityException RowError(string sheet, int row, string message) =>
        Invalid($"Лист «{sheet}», строка {row}: {message}");
    private static IdentityException Invalid(string message) => new(400, "catalog_import_relation_invalid", message);
}
