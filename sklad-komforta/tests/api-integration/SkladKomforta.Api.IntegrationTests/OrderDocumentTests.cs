using System.Text;
using System.Text.Json;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Kanban;
using SkladKomforta.Application.Orders;
using SkladKomforta.Infrastructure.Orders;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class OrderDocumentTests
{
    private static readonly string[] Letters = ["А", "Б"];

    private static SaveOrderRequest Request(params SaveOrderSectionRequest[] sections) => new(
        "Лесная, 5", "Дом", Guid.NewGuid(), Guid.NewGuid(), null, null,
        [new SaveOrderCategoryRequest(null, Guid.NewGuid(), "Оборудование", sections)]);

    private static SaveOrderSectionRequest Section(Guid? catalogSectionId, decimal quantity = 1) =>
        new(null, catalogSectionId, "Блоки",
            [new SaveOrderPositionRequest(null, null, "Кондиционер", "AC-24", "шт", quantity, null)]);

    [Fact]
    public void ValidatorAcceptsWellFormedOrder() =>
        OrderRequestValidator.Validate(Request(Section(Guid.NewGuid())));

    [Fact]
    public void ValidatorRejectsDuplicateSectionAndNonPositiveQuantity()
    {
        var sectionId = Guid.NewGuid();
        var duplicate = Assert.Throws<IdentityException>(() =>
            OrderRequestValidator.Validate(Request(Section(sectionId), Section(sectionId))));
        Assert.Equal("order_section_duplicate", duplicate.Code);

        var quantity = Assert.Throws<IdentityException>(() =>
            OrderRequestValidator.Validate(Request(Section(null, 0))));
        Assert.Equal("order_quantity_invalid", quantity.Code);

        var title = Assert.Throws<IdentityException>(() =>
            OrderRequestValidator.Validate(Request() with { Title = " " }));
        Assert.Equal("order_text_invalid", title.Code);
    }

    [Fact]
    public void PdfRendersPositionsWithBoardFieldsAndReorderMark()
    {
        var categoryId = Guid.NewGuid();
        var values = new Dictionary<string, JsonElement>
        {
            ["custom_vendor"] = JsonSerializer.SerializeToElement("ВентАид"),
            ["shipment_status"] = JsonSerializer.SerializeToElement("Купить"),
        };
        var positions = Enumerable.Range(1, 60)
            .Select(index => new OrderPositionDetails(
                Guid.NewGuid(), null, $"Позиция {index}", $"М-{index}", "шт", index,
                IsReorder: index == 2, FromQuote: true, values, index - 1))
            .ToArray();
        var order = new OrderDetails(
            Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "Лесная, 5", "Дом",
            Guid.NewGuid(), Guid.NewGuid(), null, null, null,
            [new OrderCategoryDetails(Guid.NewGuid(), categoryId, "Оборудование", 0,
                [new OrderSectionDetails(Guid.NewGuid(), null, "Блоки", 0, positions)])],
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, false, false);
        var board = new KanbanBoard(
            Guid.NewGuid(), "orders", "Комплектация", [], [],
            [new KanbanCategorySummary(categoryId, "Оборудование", 0, [],
            [
                new KanbanFieldSummary("name", "Наименование", "text", true, 0, null, []),
                new KanbanFieldSummary("custom_vendor", "Поставщик", "dictionary", false, 1, "suppliers", []),
                new KanbanFieldSummary("shipment_status", "Статус отгрузки", "dictionary", false, 2, null, []),
            ])],
            "order");

        var pdf = OrderPdfDocumentRenderer.Render(order, board, "Петров", "ООО Исполнитель", "Иван", null, 15);

        Assert.Equal("%PDF", Encoding.ASCII.GetString(pdf, 0, 4));
        Assert.True(pdf.Length > 5_000);
    }

    [Fact]
    public void PdfFormatsFieldValues()
    {
        Assert.Equal("Да", OrderPdfDocumentRenderer.Format(JsonSerializer.SerializeToElement(true)));
        Assert.Equal("2,5", OrderPdfDocumentRenderer.Format(JsonSerializer.SerializeToElement(2.5m)));
        Assert.Equal("А, Б", OrderPdfDocumentRenderer.Format(JsonSerializer.SerializeToElement(Letters)));
    }
}
