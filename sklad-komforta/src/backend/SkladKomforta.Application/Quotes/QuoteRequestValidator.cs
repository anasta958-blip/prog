using SkladKomforta.Application.Identity;

namespace SkladKomforta.Application.Quotes;

/// <summary>
/// Проверяет структуру команды до открытия транзакции. Проверки существования
/// tenant-ссылок выполняет infrastructure-сервис непосредственно в PostgreSQL.
/// </summary>
public static class QuoteRequestValidator
{
    private const int MaxProposalTypes = 30;
    private const int MaxVariantsPerType = 50;
    private const int MaxCategoriesPerVariant = 100;
    private const int MaxSectionsPerCategory = 200;
    private const int MaxPositionsPerSection = 2_000;

    /// <summary>Проверяет вид предложения, размеры дерева, UUID и денежные значения.</summary>
    public static void Validate(SaveQuoteRequest request)
    {
        if (request.QuoteKind is not (QuoteKindCodes.Quote or QuoteKindCodes.Prequote))
            Invalid("quote_kind_invalid", "Указан неизвестный вид предложения.");
        Required(request.Title, 1, 250, "Название КП");
        if (request.ClientId == Guid.Empty)
            Invalid("quote_client_required", "Выберите заказчика.");
        if (request.ExecutorCompanyId == Guid.Empty)
            Invalid("quote_executor_required", "Выберите исполнителя.");
        if (request.SelectionMode is not ("variant" or "proposal_type"))
            Invalid("quote_selection_mode_invalid", "Указан неизвестный режим выбора предложения.");
        if (request.AdditionalInformation?.Length > 20_000)
            Invalid("quote_additional_information_too_long", "Дополнительная информация не должна превышать 20000 символов.");
        if (request.ProposalTypes.Count > MaxProposalTypes)
            Invalid("quote_structure_too_large", $"В одном КП допускается не более {MaxProposalTypes} типов предложения.");

        var typeIds = new HashSet<Guid>();
        var variantIds = new HashSet<Guid>();
        var categoryIds = new HashSet<Guid>();
        var sectionIds = new HashSet<Guid>();
        var positionIds = new HashSet<Guid>();

        foreach (var type in request.ProposalTypes)
        {
            AddId(type.Id, typeIds);
            Required(type.Name, 1, 200, "Название типа предложения");
            if (type.Variants.Count > MaxVariantsPerType)
                Invalid("quote_structure_too_large", $"В одном типе допускается не более {MaxVariantsPerType} вариантов.");

            var currentVariantIds = type.Variants
                .Where(item => item.Id.HasValue)
                .Select(item => item.Id!.Value)
                .ToHashSet();
            if (type.SelectedVariantId.HasValue && !currentVariantIds.Contains(type.SelectedVariantId.Value))
                Invalid("quote_selected_variant_invalid", "Выбранный вариант не принадлежит своему типу предложения.");

            foreach (var variant in type.Variants)
            {
                AddId(variant.Id, variantIds);
                Required(variant.Name, 1, 200, "Название варианта");
                if (variant.Subtitle?.Length > 500)
                    Invalid("quote_variant_subtitle_too_long", "Подпись варианта не должна превышать 500 символов.");
                if (variant.VatRate is < 0 or > 100)
                    Invalid("quote_vat_rate_invalid", "Ставка НДС должна быть от 0 до 100 процентов.");
                if (variant.Categories.Count > MaxCategoriesPerVariant)
                    Invalid("quote_structure_too_large", $"В одном варианте допускается не более {MaxCategoriesPerVariant} категорий.");

                foreach (var category in variant.Categories)
                {
                    AddId(category.Id, categoryIds);
                    Required(category.Name, 1, 200, "Название категории");
                    if (category.Sections.Count > MaxSectionsPerCategory)
                        Invalid("quote_structure_too_large", $"В одной категории допускается не более {MaxSectionsPerCategory} разделов.");

                    foreach (var section in category.Sections)
                    {
                        AddId(section.Id, sectionIds);
                        Required(section.Name, 1, 200, "Название раздела");
                        ValidatePercent(section.MarkupPercent, "Наценка раздела");
                        ValidatePercent(section.DiscountPercent, "Скидка раздела");
                        if (section.Positions.Count > MaxPositionsPerSection)
                            Invalid("quote_structure_too_large", $"В одном разделе допускается не более {MaxPositionsPerSection} позиций.");

                        foreach (var position in section.Positions)
                        {
                            AddId(position.Id, positionIds);
                            Required(position.Name, 1, 500, "Наименование позиции");
                            if (position.Marking?.Length > 500 || position.Unit?.Length > 100)
                                Invalid("quote_position_text_too_long", "Маркировка или единица измерения имеют недопустимую длину.");
                            if (position.Quantity <= 0)
                                Invalid("quote_quantity_invalid", "Количество позиции должно быть больше нуля.");
                            if (position.PurchasePrice < 0 || position.BasePrice < 0 || position.ManualPrice < 0)
                                Invalid("quote_price_invalid", "Цена позиции не может быть отрицательной.");
                            ValidatePercent(position.MarkupPercent, "Наценка позиции");
                            ValidatePercent(position.DiscountPercent, "Скидка позиции");
                        }
                    }
                }
            }
        }
    }

    private static void ValidatePercent(decimal? value, string label)
    {
        if (value is < -100_000m or > 100_000m)
            Invalid("quote_percent_invalid", $"{label} должна быть в диапазоне от -100000 до 100000 процентов.");
    }

    private static void AddId(Guid? id, HashSet<Guid> ids)
    {
        if (!id.HasValue) return;
        if (id.Value == Guid.Empty || !ids.Add(id.Value))
            Invalid("quote_entity_id_invalid", "В структуре предложения обнаружен пустой или повторяющийся идентификатор.");
    }

    private static void Required(string value, int minimum, int maximum, string label)
    {
        var length = value?.Trim().Length ?? 0;
        if (length < minimum || length > maximum)
            Invalid("quote_text_invalid", $"{label}: допустимо от {minimum} до {maximum} символов.");
    }

    private static void Invalid(string code, string message) =>
        throw new IdentityException(400, code, message);
}

