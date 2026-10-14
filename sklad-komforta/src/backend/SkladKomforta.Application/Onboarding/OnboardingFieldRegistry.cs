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
    public const string CustomFieldPrefix = "custom_";

    /// <summary>
    /// Поля, доступные в «Поля в канбанах» канбана комплектации без поля в
    /// категории каталога: их значения существуют только в комплектации.
    /// </summary>
    public static readonly IReadOnlySet<string> OrderOnlyFieldCodes =
        new HashSet<string>(StringComparer.Ordinal) { "shipment_status" };

    public static readonly IReadOnlySet<string> CustomFieldTypes = new HashSet<string>(StringComparer.Ordinal)
    {
        "text", "number", "money", "percent", "dictionary", "boolean", "relation",
        "calculated_money"
    };

    private static readonly CatalogFieldDraft[] DefaultCatalogFieldValues =
    [
        new("name", true, true),
        new("marking", true, false),
        new("quantity", true, false),
        new("unit", true, false),
        new("base_price", true, false),
    ];

    public static readonly IReadOnlyList<OnboardingFieldDefinition> All =
    [
        new("group", "Группа", "dictionary", true, false, "Основные"),
        new("name", "Наименование", "text", true, false, "Основные"),
        new("marking", "Маркировка / размер", "text", true, false, "Основные"),
        new("note", "Примечание", "text", true, false, "Основные"),
        new("completion", "Комплектация", "text", true, false, "Основные"),
        new("quantity", "Количество", "number", true, false, "Основные"),
        new("unit", "Единица измерения", "dictionary", true, false, "Основные"),
        new("purchase_price", "Закупочная цена", "money", true, false, "Цены и расчёты"),
        new("minimal_price", "Минимальная цена", "money", true, false, "Цены и расчёты"),
        new("markup_value", "Наценка", "percent", true, false, "Цены и расчёты"),
        new("base_price", "Цена", "money", true, false, "Цены и расчёты"),
        new("discount_value", "Скидка", "percent", true, false, "Цены и расчёты"),
        new("line_total", "Сумма", "calculated_money", false, true, "Цены и расчёты"),
        new("excluded_from_calc", "Не считать", "boolean", true, false, "Служебные"),
        new("technical_note", "Техническая информация", "text", true, false, "Служебные"),
        new("linked_services", "Связанные позиции", "relation", true, false, "Служебные"),
        new("shipment_status", "Статус отгрузки", "dictionary", true, false, "Комплектация"),
    ];

    private static readonly Dictionary<string, OnboardingFieldDefinition> ByCode =
        All.ToDictionary(item => item.Code, StringComparer.Ordinal);

    /// <summary>Возвращает метаданные кода или отклоняет неизвестное поле.</summary>
    public static OnboardingFieldDefinition Get(string code) =>
        ByCode.TryGetValue(code.Trim(), out var definition)
            ? definition
            : throw new Identity.IdentityException(400, "onboarding_field_unknown", $"Неизвестное поле: {code}.");

    public static bool IsSystemField(string code) => ByCode.ContainsKey(code.Trim());

    /// <summary>Возвращает доверенные метаданные системного поля или проверенные метаданные пользовательского поля.</summary>
    public static OnboardingFieldDefinition DefinitionOf(CatalogFieldDraft field)
    {
        var code = field.FieldCode.Trim();
        if (ByCode.TryGetValue(code, out var systemDefinition)) return systemDefinition;
        if (!code.StartsWith(CustomFieldPrefix, StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(field.FieldType) ||
            !CustomFieldTypes.Contains(field.FieldType.Trim()))
            throw new Identity.IdentityException(400, "onboarding_field_unknown", $"Неизвестное поле: {field.FieldCode}.");

        var isCalculated = field.FieldType.Trim() == "calculated_money";
        return new OnboardingFieldDefinition(
            code,
            field.Label?.Trim() ?? string.Empty,
            field.FieldType.Trim(),
            !isCalculated,
            isCalculated,
            "Пользовательские");
    }

    public static string FieldTypeOf(CatalogFieldDraft field) => DefinitionOf(field).FieldType;

    /// <summary>Возвращает пользовательское название либо системное название для старых черновиков.</summary>
    public static string LabelOf(CatalogFieldDraft field)
    {
        if (!string.IsNullOrWhiteSpace(field.Label)) return field.Label.Trim();
        return IsSystemField(field.FieldCode) ? Get(field.FieldCode).Label : string.Empty;
    }

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
        DefaultCatalogFieldValues;
}
