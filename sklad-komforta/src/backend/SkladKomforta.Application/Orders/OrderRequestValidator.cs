using SkladKomforta.Application.Identity;

namespace SkladKomforta.Application.Orders;

/// <summary>Проверяет форму команды сохранения комплектации до обращения к базе.</summary>
public static class OrderRequestValidator
{
    /// <summary>Наибольшее допустимое количество одной позиции.</summary>
    public const decimal MaxQuantity = 1_000_000_000m;

    /// <summary>Бросает понятную ошибку 400 при первом нарушении.</summary>
    public static void Validate(SaveOrderRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        RequireText(request.Title, 1, 200, "Адрес объекта");
        if (request.ObjectType is { } objectType && objectType.Trim().Length > 160)
            Fail("order_object_type_invalid", "Тип объекта не должен превышать 160 символов.");
        if (request.ClientId == Guid.Empty)
            Fail("order_client_required", "Выберите заказчика.");
        if (request.ExecutorCompanyId == Guid.Empty)
            Fail("order_executor_required", "Выберите исполнителя.");

        var categories = request.Categories ?? [];
        var catalogCategories = new HashSet<Guid>();
        foreach (var category in categories)
        {
            RequireText(category.Name, 1, 200, "Название категории");
            if (category.CatalogCategoryId is { } catalogCategoryId && !catalogCategories.Add(catalogCategoryId))
                Fail("order_category_duplicate", $"Категория «{category.Name.Trim()}» добавлена дважды.");

            var catalogSections = new HashSet<Guid>();
            foreach (var section in category.Sections ?? [])
            {
                RequireText(section.Name, 1, 200, "Название раздела");
                if (section.CatalogSectionId is { } catalogSectionId && !catalogSections.Add(catalogSectionId))
                    Fail("order_section_duplicate",
                        $"Раздел «{section.Name.Trim()}» уже есть в категории «{category.Name.Trim()}».");
                foreach (var position in section.Positions ?? [])
                {
                    RequireText(position.Name, 1, 300, "Наименование позиции");
                    if ((position.Marking?.Length ?? 0) > 300)
                        Fail("order_position_invalid", $"Маркировка позиции «{position.Name.Trim()}» слишком длинная.");
                    if ((position.Unit?.Length ?? 0) > 50)
                        Fail("order_position_invalid", $"Единица позиции «{position.Name.Trim()}» слишком длинная.");
                    if (position.Quantity <= 0 || position.Quantity > MaxQuantity)
                        Fail("order_quantity_invalid",
                            $"Количество позиции «{position.Name.Trim()}» должно быть больше нуля.");
                }
            }
        }
    }

    private static void RequireText(string? value, int min, int max, string label)
    {
        var length = value?.Trim().Length ?? 0;
        if (length < min || length > max)
            Fail("order_text_invalid", $"{label}: от {min} до {max} символов.");
    }

    private static void Fail(string code, string message) =>
        throw new IdentityException(400, code, message);
}
