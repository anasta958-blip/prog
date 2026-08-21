namespace SkladKomforta.Application.Onboarding;

/// <summary>
/// Описывает одно поддерживаемое системой поле. Реестр не позволяет tenant-ам
/// создавать неизвестные коды, для которых отсутствуют хранение или бизнес-логика.
/// </summary>
public sealed record OnboardingFieldDefinition(
    string Code,
    string Label,
    string FieldType,
    bool CanBeRequired,
    bool IsCalculated,
    string Group);

/// <summary>
/// Единый серверный реестр полей старого приложения, которые будут последовательно
/// реализованы в каталоге, КП, ПКП и комплектации нового приложения.
/// </summary>
public static class OnboardingFieldRegistry
{
    public static readonly IReadOnlyList<OnboardingFieldDefinition> All =
    [
        new("group", "Группа", "dictionary", false, false, "Основные"),
        new("name", "Наименование", "text", true, false, "Основные"),
        new("marking", "Маркировка / размер", "text", false, false, "Основные"),
        new("note", "Примечание", "text", false, false, "Основные"),
        new("completion", "Комплектация", "text", false, false, "Основные"),
        new("quantity", "Количество", "number", true, false, "Основные"),
        new("unit", "Единица измерения", "dictionary", false, false, "Основные"),
        new("supplier", "Поставщик", "dictionary", false, false, "Основные"),
        new("purchase_price", "Закупочная цена", "money", false, false, "Цены и расчёты"),
        new("minimal_price", "Минимальная цена", "money", false, false, "Цены и расчёты"),
        new("retail_price", "Розничная цена", "money", false, false, "Цены и расчёты"),
        new("price_type", "Тип цены", "enum", false, false, "Цены и расчёты"),
        new("markup_value", "Наценка", "percent", false, false, "Цены и расчёты"),
        new("base_price", "Цена", "money", false, false, "Цены и расчёты"),
        new("discount_value", "Скидка", "percent", false, false, "Цены и расчёты"),
        new("line_total", "Сумма", "calculated_money", false, true, "Цены и расчёты"),
        new("excluded_from_calc", "Не считать", "boolean", false, false, "Служебные"),
        new("technical_note", "Техническая информация", "text", false, false, "Служебные"),
        new("linked_services", "Привязанные работы", "relation", false, false, "Служебные"),
        new("invoice_check", "Проверка счёта", "enum", false, false, "Комплектация"),
        new("shipment_status", "Статус отгрузки", "enum", false, false, "Комплектация"),
    ];

    private static readonly Dictionary<string, OnboardingFieldDefinition> ByCode =
        All.ToDictionary(item => item.Code, StringComparer.Ordinal);

    /// <summary>Возвращает метаданные кода или отклоняет неизвестное поле.</summary>
    public static OnboardingFieldDefinition Get(string code) =>
        ByCode.TryGetValue(code.Trim(), out var definition)
            ? definition
            : throw new Identity.IdentityException(400, "onboarding_field_unknown", $"Неизвестное поле: {code}.");

    /// <summary>Создаёт серверное поле контекста только из доверенных метаданных реестра.</summary>
    public static EntityFieldDraft CreateContextField(
        string contextCode,
        string fieldCode,
        bool isVisible = true,
        bool isRequired = false)
    {
        var definition = Get(fieldCode);
        return new EntityFieldDraft(
            contextCode,
            definition.Code,
            definition.Label,
            definition.FieldType,
            isVisible,
            isRequired && definition.CanBeRequired);
    }

    /// <summary>Стартовый набор карточки категории, соответствующий базовой товарной строке.</summary>
    public static IReadOnlyList<CatalogFieldDraft> DefaultCatalogFields() =>
    [
        new("group", true, false),
        new("name", true, true),
        new("marking", true, false),
        new("note", true, false),
        new("quantity", true, true),
        new("unit", true, false),
        new("supplier", true, false),
        new("purchase_price", true, false),
        new("minimal_price", true, false),
        new("retail_price", true, false),
        new("markup_value", true, false),
        new("base_price", true, false),
        new("discount_value", true, false),
        new("line_total", true, false),
        new("excluded_from_calc", true, false),
    ];
}
