using SkladKomforta.Application.Identity;
using System.Net.Mail;

namespace SkladKomforta.Application.Onboarding;

/// <summary>Централизует ограничения черновика, общие для сохранения и активации.</summary>
public static class OnboardingValidator
{
    /// <summary>
    /// Проверяет размеры, уникальность кодов и ссылки переходов. При финальной
    /// активации дополнительно требует заполнения каждого обязательного раздела.
    /// </summary>
    public static void Validate(OrganizationOnboardingDraft draft, bool forActivation)
    {
        if (draft.CurrentStep is < 1 or > 7)
            Fail("onboarding_step_invalid", "Номер шага должен быть от 1 до 7.");

        RequireText(draft.Company.OrganizationName, 2, 200, "Название организации");
        ValidateDigits(draft.Company.Inn, [10, 12], "ИНН должен содержать 10 или 12 цифр.");
        ValidateDigits(draft.Company.Kpp, [9], "КПП должен содержать 9 цифр.");
        ValidateDigits(draft.Company.Ogrn, [13, 15], "ОГРН должен содержать 13 или 15 цифр.");
        ValidatePhone(draft.Company.Phone);
        ValidateEmail(draft.Company.Email);
        ValidateUnique(draft.Workflows.Select(item => item.Code), "Коды канбанов");
        ValidateUnique(draft.Categories.Select(item => item.ClientId), "Идентификаторы категорий");
        ValidateUnique(draft.Categories.Select(item => item.Name), "Названия категорий");
        ValidateUnique(draft.Roles.Select(item => item.Name), "Названия ролей");
        ValidateUnique(draft.Dictionaries.Select(item => item.Code), "Коды справочников");

        foreach (var workflow in draft.Workflows)
        {
            RequireText(workflow.Code, 2, 80, "Код канбана");
            RequireText(workflow.Name, 2, 120, "Название канбана");
            ValidateUnique(workflow.Columns.Select(item => item.ClientId), "Идентификаторы столбцов");
            foreach (var column in workflow.Columns)
            {
                RequireText(column.ClientId, 1, 80, "Идентификатор столбца");
                RequireText(column.Name, 1, 120, "Название столбца");
                if (column.Color.Length != 7 || column.Color[0] != '#' || !column.Color[1..].All(Uri.IsHexDigit))
                    Fail("onboarding_color_invalid", "Цвет столбца должен иметь формат #RRGGBB.");
            }

            var columnIds = workflow.Columns.Select(item => item.ClientId).ToHashSet(StringComparer.Ordinal);
            if (workflow.Transitions.Any(item => item.FromClientId == item.ToClientId ||
                                                 !columnIds.Contains(item.FromClientId) ||
                                                 !columnIds.Contains(item.ToClientId)))
                Fail("onboarding_transition_invalid", "Переход канбана ссылается на неизвестный столбец.");
        }

        foreach (var category in draft.Categories)
        {
            RequireText(category.ClientId, 1, 80, "Идентификатор категории");
            RequireText(category.Name, 1, 120, "Название категории");
            ValidateUnique(category.Fields.Select(item => item.FieldCode), $"Поля категории «{category.Name}»");
            ValidateFieldSelection(category.Fields, $"категории «{category.Name}»");
            ValidateUnique(category.Sections.Select(item => item.Name), "Названия разделов");
            foreach (var section in category.Sections)
            {
                RequireText(section.Name, 1, 120, "Название раздела");
                ValidateUnique(section.Groups.Select(item => item.Name), "Названия групп");
                foreach (var group in section.Groups) RequireText(group.Name, 1, 120, "Название группы");
            }
        }

        ValidateUnique(draft.Fields.Select(item => $"{item.ContextCode}:{item.FieldCode}"), "Коды полей");
        foreach (var field in draft.Fields)
        {
            RequireText(field.ContextCode, 2, 40, "Контекст поля");
            var definition = OnboardingFieldRegistry.Get(field.FieldCode);
            if (!string.Equals(field.Label.Trim(), definition.Label, StringComparison.Ordinal) ||
                !string.Equals(field.FieldType.Trim(), definition.FieldType, StringComparison.Ordinal))
                Fail("onboarding_field_metadata_invalid", $"Метаданные поля «{definition.Label}» нельзя изменять.");
            if (field.IsRequired && !field.IsVisible)
                Fail("onboarding_field_invalid", "Обязательное поле не может быть скрыто.");
            if (field.IsRequired && !definition.CanBeRequired)
                Fail("onboarding_field_invalid", $"Поле «{definition.Label}» нельзя сделать обязательным.");
        }

        foreach (var role in draft.Roles) RequireText(role.Name, 2, 100, "Название роли");
        foreach (var dictionary in draft.Dictionaries)
        {
            RequireText(dictionary.Code, 2, 80, "Код справочника");
            RequireText(dictionary.Name, 2, 120, "Название справочника");
            ValidateUnique(dictionary.Items.Select(item => item.Value), "Значения справочника");
            foreach (var item in dictionary.Items) RequireText(item.Value, 1, 160, "Значение справочника");
        }

        if (forActivation &&
            (draft.Workflows.Count == 0 || draft.Workflows.Any(item => item.Columns.Count == 0) ||
             draft.Categories.Count == 0 || draft.Fields.Count == 0 || draft.Dictionaries.Count == 0))
            Fail("onboarding_incomplete", "Заполните канбаны, каталог, поля и справочники перед активацией.");
    }

    private static void ValidateFieldSelection(IReadOnlyList<CatalogFieldDraft> fields, string owner)
    {
        var selected = fields.Select(item => item.FieldCode).ToHashSet(StringComparer.Ordinal);
        foreach (var field in fields)
        {
            var definition = OnboardingFieldRegistry.Get(field.FieldCode);
            if (field.IsRequired && !field.IsVisible)
                Fail("onboarding_field_invalid", $"Обязательное поле «{definition.Label}» в {owner} не может быть скрыто.");
            if (field.IsRequired && !definition.CanBeRequired)
                Fail("onboarding_field_invalid", $"Поле «{definition.Label}» в {owner} нельзя сделать обязательным.");
        }

        if (!selected.Contains("name"))
            Fail("onboarding_field_dependency", $"В {owner} обязательно поле «Наименование».");
        if (selected.Contains("line_total") && (!selected.Contains("base_price") || !selected.Contains("quantity")))
            Fail("onboarding_field_dependency", $"Для суммы в {owner} необходимы поля «Цена» и «Количество».");
        if ((selected.Contains("markup_value") || selected.Contains("discount_value")) && !selected.Contains("base_price"))
            Fail("onboarding_field_dependency", $"Для наценки и скидки в {owner} необходимо поле «Цена».");
    }

    private static void ValidateUnique(IEnumerable<string> values, string label)
    {
        var normalized = values.Select(value => value.Trim()).ToArray();
        if (normalized.Distinct(StringComparer.OrdinalIgnoreCase).Count() != normalized.Length)
            Fail("onboarding_duplicate", $"{label} не должны повторяться.");
    }

    private static void RequireText(string value, int min, int max, string label)
    {
        var length = value.Trim().Length;
        if (length < min || length > max)
            Fail("onboarding_value_invalid", $"{label}: допустимо от {min} до {max} символов.");
    }

    /// <summary>Проверяет необязательный реквизит: если он заполнен, допускаются только цифры заданной длины.</summary>
    private static void ValidateDigits(string? value, IReadOnlyCollection<int> allowedLengths, string message)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        var normalized = value.Trim();
        if (!normalized.All(char.IsDigit) || !allowedLengths.Contains(normalized.Length))
            Fail("onboarding_company_details_invalid", message);
    }

    /// <summary>Проверяет разумный диапазон цифр телефона, сохраняя возможность пользовательского форматирования.</summary>
    private static void ValidatePhone(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        var normalized = value.Trim();
        if (normalized.Any(character => !char.IsDigit(character) && character is not ('+' or '(' or ')' or '-' or ' ')))
            Fail("onboarding_company_details_invalid", "Телефон содержит недопустимые символы.");

        var digitCount = normalized.Count(char.IsDigit);
        if (digitCount is < 10 or > 15)
            Fail("onboarding_company_details_invalid", "Телефон должен содержать от 10 до 15 цифр.");
    }

    /// <summary>Проверяет синтаксис необязательного email на сервере, не полагаясь только на Flutter-форму.</summary>
    private static void ValidateEmail(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        var normalized = value.Trim();
        try
        {
            var address = new MailAddress(normalized);
            if (!string.Equals(address.Address, normalized, StringComparison.OrdinalIgnoreCase) ||
                !normalized.Contains('.'))
                Fail("onboarding_company_details_invalid", "Введите корректный email.");
        }
        catch (FormatException)
        {
            Fail("onboarding_company_details_invalid", "Введите корректный email.");
        }
    }

    private static void Fail(string code, string message) =>
        throw new IdentityException(400, code, message);
}
