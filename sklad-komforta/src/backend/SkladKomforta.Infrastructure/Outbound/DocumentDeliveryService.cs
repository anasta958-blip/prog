using SkladKomforta.Application.Abstractions.Outbound;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Authorization;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Kanban;
using SkladKomforta.Application.Orders;
using SkladKomforta.Application.Outbound;
using SkladKomforta.Application.Quotes;
using static SkladKomforta.Infrastructure.Orders.OrderStore;

namespace SkladKomforta.Infrastructure.Outbound;

/// <summary>
/// Отправляет PDF КП, ПКП или комплектации в Telegram или на почту. PDF
/// формируется теми же сервисами, что и печать, — по последней сохранённой
/// версии документа.
/// </summary>
internal sealed class DocumentDeliveryService(
    IDatabaseConnectionFactory connectionFactory,
    ITenantContext tenantContext,
    ITenantPermissionEvaluator permissions,
    IKanbanService kanbanService,
    IQuoteService quoteService,
    IQuotePdfService quotePdfService,
    IOrderService orderService,
    IOrderPdfService orderPdfService,
    ICompanyWorkspaceService companyService,
    OutboundSecretProtector protector,
    ITelegramTransport telegram,
    IEmailTransport email) : IDocumentDeliveryService
{
    private const string TelegramCaptionLimitSuffix = "…";
    private const int TelegramCaptionLimit = 1024;

    /// <inheritdoc />
    public async Task<SendDocumentResult> SendAsync(
        Guid actorUserId, Guid boardId, Guid cardId, SendDocumentRequest request, CancellationToken cancellationToken)
    {
        if (request.Channel is not (OutboundChannel.Telegram or OutboundChannel.Email))
            throw new IdentityException(400, "outbound_channel_invalid", "Неизвестный способ отправки.");

        OutboundState state;
        await using (var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken))
            state = await OutboundSettingsStore.ReadAsync(connection, null, cancellationToken);

        // Куда отправлять — проверяется до формирования PDF.
        long? topicId = null;
        string? recipient = null;
        if (request.Channel == OutboundChannel.Telegram)
        {
            if (!state.TelegramReady)
                throw NotConfigured("Отправка в Telegram не настроена. Заполните её в «Настройки организации → Внешняя отправка».");
            if (state.UsesTopics)
            {
                topicId = state.DefaultTopicId ?? request.TopicId
                    ?? throw new IdentityException(400, "outbound_topic_required", "Выберите топик для отправки.");
                if (state.DefaultTopicId is null && state.Topics.All(topic => topic.TopicId != topicId))
                    throw new IdentityException(400, "outbound_topic_invalid", "Топика нет в справочнике настроек.");
            }
        }
        else
        {
            if (!state.EmailReady)
                throw NotConfigured("Отправка по почте не настроена. Заполните её в «Настройки организации → Внешняя отправка».");
            recipient = state.DefaultRecipient ?? request.Recipient?.Trim();
            if (string.IsNullOrEmpty(recipient))
                throw new IdentityException(400, "outbound_recipient_required", "Укажите адрес получателя.");
            if (!OutboundSettingsValidator.IsEmail(recipient))
                throw new IdentityException(400, "outbound_recipient_invalid", "Адрес получателя указан неверно.");
        }

        var document = await PrepareAsync(actorUserId, boardId, cardId, request, cancellationToken);
        var attachment = new OutboundAttachment(OutboundTemplate.FileName(document.Values), "application/pdf", document.Pdf);

        string destination;
        if (request.Channel == OutboundChannel.Telegram)
        {
            var caption = OutboundTemplate.Render(state.CaptionTemplate, document.Values);
            if (caption.Length > TelegramCaptionLimit)
                caption = caption[..(TelegramCaptionLimit - TelegramCaptionLimitSuffix.Length)] + TelegramCaptionLimitSuffix;
            await telegram.SendAsync(new TelegramOutboundMessage(
                protector.Unprotect(state.BotToken!), state.ChatId!, topicId,
                caption.Length == 0 ? null : caption, attachment), cancellationToken);
            destination = PostgresOutboundSettingsService.TelegramDestination(state, topicId);
        }
        else
        {
            var smtp = state.Smtp!;
            await email.SendAsync(new EmailOutboundMessage(
                smtp.Host, smtp.Port, state.Address!, protector.Unprotect(state.Password!), state.SenderName,
                recipient!, OutboundTemplate.Render(state.SubjectTemplate, document.Values),
                state.BodyTemplate is null ? null : OutboundTemplate.Render(state.BodyTemplate, document.Values),
                attachment), cancellationToken);
            destination = recipient!;
        }

        await using (var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken))
        {
            var diff = AuditChanges.Serialize(null, new
            {
                title = document.Values.Title,
                document = $"{document.Values.DocumentKind} №{document.Values.CardNumber}",
                channel = request.Channel == OutboundChannel.Telegram ? "Telegram" : "Почта",
                destination,
                fileName = attachment.FileName,
            });
            await ExecuteAsync(connection, null, """
                INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
                VALUES (@actor, 'kanban_card', @card_id, @action, CAST(@diff AS jsonb))
                """, cancellationToken,
                ("actor", actorUserId), ("card_id", cardId),
                ("action", request.Channel == OutboundChannel.Telegram ? "sent_telegram" : "sent_email"),
                ("diff", diff!));
        }

        return new SendDocumentResult(request.Channel, destination, attachment.FileName);
    }

    private sealed record PreparedDocument(OutboundTemplateValues Values, byte[] Pdf);

    /// <summary>Проверяет право просмотра документа и формирует PDF как при печати.</summary>
    private async Task<PreparedDocument> PrepareAsync(
        Guid actorUserId, Guid boardId, Guid cardId, SendDocumentRequest request, CancellationToken token)
    {
        var board = await kanbanService.GetBoardAsync(boardId, token);
        var card = await kanbanService.GetCardAsync(actorUserId, boardId, cardId, token);
        var date = request.ClientDate ?? DateOnly.FromDateTime(DateTime.UtcNow);
        var clients = await companyService.GetClientsAsync(token);

        switch (board.Specialization)
        {
            case WorkflowSpecializationCodes.Quote or WorkflowSpecializationCodes.Prequote or WorkflowSpecializationCodes.QuoteAndPrequote:
            {
                await RequireAsync(actorUserId, "quotes.view", token);
                var quote = await quoteService.GetAsync(actorUserId, boardId, cardId, token);
                var pdf = await quotePdfService.GenerateAsync(
                    actorUserId, boardId, cardId, request.ProposalTypeId, request.VariantId, token);
                var kind = quote.QuoteKind == QuoteKindCodes.Prequote ? "ПКП" : "КП";
                return new PreparedDocument(
                    new OutboundTemplateValues(kind, card.Number, quote.Title,
                        clients.FirstOrDefault(client => client.Id == quote.ClientId)?.Name, date),
                    pdf.Content);
            }
            case WorkflowSpecializationCodes.Order:
            {
                await RequireAsync(actorUserId, "orders.view", token);
                var order = await orderService.GetAsync(actorUserId, boardId, cardId, token);
                var pdf = await orderPdfService.GenerateAsync(actorUserId, boardId, cardId, token);
                return new PreparedDocument(
                    new OutboundTemplateValues("Комплектация", card.Number, order.Title,
                        clients.FirstOrDefault(client => client.Id == order.ClientId)?.Name, date),
                    pdf.Content);
            }
            default:
                throw new IdentityException(409, "outbound_document_unsupported",
                    "Отправлять можно только КП, ПКП и комплектации.");
        }
    }

    private async Task RequireAsync(Guid actorUserId, string permission, CancellationToken token)
    {
        if (!await permissions.HasPermissionAsync(actorUserId, tenantContext.OrganizationId, permission, token))
            throw new IdentityException(403, "permission_denied", "Недостаточно прав для просмотра документа.");
    }

    private static IdentityException NotConfigured(string message) =>
        new(409, "outbound_not_configured", message);
}
