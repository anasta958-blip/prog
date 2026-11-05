using System.Data.Common;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;
using Npgsql;
using StackExchange.Redis;
using SkladKomforta.Application.Abstractions.Realtime;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Quotes;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Kanban;
using SkladKomforta.Infrastructure.Company;
using SkladKomforta.Domain.Tenancy;
using SkladKomforta.Infrastructure.Configuration;
using SkladKomforta.Infrastructure.Identity;

namespace SkladKomforta.Infrastructure.Quotes;

/// <summary>
/// Обслуживает внешние парольные ссылки без создания пользователя, роли или
/// tenant-JWT. Открытые токены и пароли не записываются в PostgreSQL: вход
/// проверяется по хешам, а для повторного показа сотруднику хранятся копии,
/// зашифрованные AES-GCM отдельным ключом, выведенным из TOTP-ключа.
/// </summary>
internal sealed class PostgresQuoteClientAccessService : IQuoteClientAccessService
{
    private static readonly TimeSpan ClientSessionLifetime = TimeSpan.FromHours(1);
    private static readonly TimeSpan LoginAttemptWindow = TimeSpan.FromMinutes(15);
    private const int MaximumLoginAttempts = 8;
    private const string PasswordAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
    private const string SecretKeyPurpose = "quote-client-access";

    private readonly NpgsqlDataSource _dataSource;
    private readonly IDatabase _redis;
    private readonly ITenantContext _tenantContext;
    private readonly IQuoteService _quoteService;
    private readonly IDocumentLayoutService _layouts;
    private readonly IRealtimeNotifier _realtime;
    private readonly PasswordHasher<string> _passwordHasher = new();
    private readonly byte[] _secretKey;

    public PostgresQuoteClientAccessService(
        NpgsqlDataSource dataSource,
        IConnectionMultiplexer redis,
        ITenantContext tenantContext,
        IQuoteService quoteService,
        IDocumentLayoutService layouts,
        IRealtimeNotifier realtime,
        IOptions<SecurityOptions> securityOptions)
    {
        _realtime = realtime;
        _dataSource = dataSource;
        _redis = redis.GetDatabase();
        _tenantContext = tenantContext;
        _quoteService = quoteService;
        _layouts = layouts;
        _secretKey = IdentitySecurity.DeriveKey(
            Convert.FromBase64String(securityOptions.Value.TotpEncryptionKey),
            SecretKeyPurpose);
    }

    /// <inheritdoc />
    public async Task<CreatedQuoteClientAccess> CreateAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        CreateQuoteClientAccessRequest request,
        CancellationToken cancellationToken)
    {
        if (request.LifetimeDays is < 1 or > 30)
            throw Failure(400, "quote_client_link_lifetime_invalid", "Срок ссылки должен быть от 1 до 30 дней.");

        var quote = await _quoteService.GetAsync(actorUserId, boardId, cardId, cancellationToken);
        if (await _layouts.GetTemplateAsync(boardId, cancellationToken) is null)
            throw Failure(409, "document_layout_required",
                "Настройте внешний вид ссылки и PDF для этого канбана в разделе «Компания → Конструктор ссылки и PDF».");
        if (quote.ProposalTypes.Count == 0 || quote.ProposalTypes.Any(type => type.Variants.Count == 0))
            throw Failure(
                409,
                "quote_client_link_content_incomplete",
                "Перед отправкой клиенту добавьте хотя бы один вариант в каждый тип предложения.");
        var accessToken = CreateToken(32);
        var password = CreatePassword(10);
        var linkId = Guid.NewGuid();
        var expiresAt = DateTimeOffset.UtcNow.AddDays(request.LifetimeDays);
        var passwordHash = _passwordHasher.HashPassword(linkId.ToString("N"), password);

        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using (var revoke = new NpgsqlCommand("""
            UPDATE public.quote_client_access_links
               SET revoked_at = now()
             WHERE organization_id = @organization_id
               AND quote_id = @quote_id
               AND revoked_at IS NULL
            """, connection, transaction))
        {
            revoke.Parameters.AddWithValue("organization_id", _tenantContext.OrganizationId);
            revoke.Parameters.AddWithValue("quote_id", quote.Id);
            await revoke.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var insert = new NpgsqlCommand("""
            INSERT INTO public.quote_client_access_links
                (id, organization_id, quote_id, token_hash, password_hash,
                 token_ciphertext, password_ciphertext, expires_at, created_by)
            VALUES
                (@id, @organization_id, @quote_id, @token_hash, @password_hash,
                 @token_ciphertext, @password_ciphertext, @expires_at, @created_by)
            """, connection, transaction))
        {
            insert.Parameters.AddWithValue("id", linkId);
            insert.Parameters.AddWithValue("organization_id", _tenantContext.OrganizationId);
            insert.Parameters.AddWithValue("quote_id", quote.Id);
            insert.Parameters.AddWithValue("token_hash", HashToken(accessToken));
            insert.Parameters.AddWithValue("password_hash", passwordHash);
            insert.Parameters.AddWithValue("token_ciphertext", Protect(accessToken));
            insert.Parameters.AddWithValue("password_ciphertext", Protect(password));
            insert.Parameters.AddWithValue("expires_at", expiresAt);
            insert.Parameters.AddWithValue("created_by", actorUserId);
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return new CreatedQuoteClientAccess(accessToken, password, expiresAt);
    }

    /// <inheritdoc />
    public async Task<QuoteClientAccessStatus> GetStatusAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        CancellationToken cancellationToken)
    {
        var quote = await _quoteService.GetAsync(actorUserId, boardId, cardId, cancellationToken);
        QuoteClientAccessStatus status;
        await using (var connection = await _dataSource.OpenConnectionAsync(cancellationToken))
        await using (var command = new NpgsqlCommand("""
            SELECT created_at, expires_at, last_accessed_at, token_ciphertext, password_ciphertext
              FROM public.quote_client_access_links
             WHERE organization_id = @organization_id
               AND quote_id = @quote_id
               AND revoked_at IS NULL
             ORDER BY created_at DESC
             LIMIT 1
            """, connection))
        {
            command.Parameters.AddWithValue("organization_id", _tenantContext.OrganizationId);
            command.Parameters.AddWithValue("quote_id", quote.Id);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
                return new QuoteClientAccessStatus(false, null, null, null);
            status = new QuoteClientAccessStatus(
                ReadTimestamp(reader, 1) > DateTimeOffset.UtcNow,
                ReadTimestamp(reader, 0),
                ReadTimestamp(reader, 1),
                reader.IsDBNull(2) ? null : ReadTimestamp(reader, 2),
                reader.IsDBNull(3) ? null : Unprotect(reader.GetFieldValue<byte[]>(3)),
                reader.IsDBNull(4) ? null : Unprotect(reader.GetFieldValue<byte[]>(4)));
        }

        // Каждый показ пароля сотруднику фиксируется в журнале организации.
        if (status.Password is not null)
        {
            await using var tenant = await OpenTenantConnectionAsync(_tenantContext.SchemaName, cancellationToken);
            await using var audit = new NpgsqlCommand("""
                INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action)
                VALUES (@actor_user_id, 'quote', @quote_id, 'client_link_secret_viewed')
                """, tenant);
            audit.Parameters.AddWithValue("actor_user_id", actorUserId);
            audit.Parameters.AddWithValue("quote_id", quote.Id);
            await audit.ExecuteNonQueryAsync(cancellationToken);
        }

        return status;
    }

    /// <inheritdoc />
    public async Task<QuoteClientAccessStatus> ExtendAsync(Guid actorUserId, Guid boardId, Guid cardId,
        ExtendQuoteClientAccessRequest request, CancellationToken cancellationToken)
    {
        if (request.AdditionalDays is < 1 or > 30)
            throw Failure(400, "quote_client_link_lifetime_invalid", "Продлить ссылку можно на срок от 1 до 30 дней.");
        var quote = await _quoteService.GetAsync(actorUserId, boardId, cardId, cancellationToken);
        await using var connection = await OpenTenantConnectionAsync(_tenantContext.SchemaName, cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using var command = new NpgsqlCommand("""
            UPDATE public.quote_client_access_links
               SET expires_at = GREATEST(expires_at, now()) + make_interval(days => @days)
             WHERE id = (SELECT id FROM public.quote_client_access_links
                          WHERE organization_id = @organization_id AND quote_id = @quote_id
                            AND revoked_at IS NULL ORDER BY created_at DESC LIMIT 1)
               AND revoked_at IS NULL
            RETURNING expires_at
            """, connection, transaction);
        command.Parameters.AddWithValue("days", request.AdditionalDays);
        command.Parameters.AddWithValue("organization_id", _tenantContext.OrganizationId);
        command.Parameters.AddWithValue("quote_id", quote.Id);
        var expires = await command.ExecuteScalarAsync(cancellationToken);
        if (expires is null)
            throw Failure(409, "quote_client_link_missing", "Нет ссылки для продления. Создайте новую ссылку.");
        await using var audit = new NpgsqlCommand("""
            INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
            VALUES (@actor, 'quote', @quote, 'client_link_extended', CAST(@diff AS jsonb))
            """, connection, transaction);
        audit.Parameters.AddWithValue("actor", actorUserId);
        audit.Parameters.AddWithValue("quote", quote.Id);
        audit.Parameters.AddWithValue("diff", JsonSerializer.Serialize(new { after = new { expiresAt = expires } }));
        await audit.ExecuteNonQueryAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return await GetStatusAsync(actorUserId, boardId, cardId, cancellationToken);
    }

    public async Task RevokeAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        CancellationToken cancellationToken)
    {
        var quote = await _quoteService.GetAsync(actorUserId, boardId, cardId, cancellationToken);
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand("""
            UPDATE public.quote_client_access_links
               SET revoked_at = now()
             WHERE organization_id = @organization_id
               AND quote_id = @quote_id
               AND revoked_at IS NULL
            """, connection);
        command.Parameters.AddWithValue("organization_id", _tenantContext.OrganizationId);
        command.Parameters.AddWithValue("quote_id", quote.Id);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <inheritdoc />
    public async Task<QuoteClientLoginResult> LoginAsync(
        QuoteClientLoginRequest request,
        string? ipAddress,
        CancellationToken cancellationToken)
    {
        var accessToken = request.AccessToken?.Trim() ?? string.Empty;
        var password = request.Password ?? string.Empty;
        if (accessToken.Length < 32 || password.Length == 0)
            throw Failure(401, "quote_client_credentials_invalid", "Неверная ссылка или пароль.");

        await EnforceLoginRateLimitAsync(accessToken, ipAddress);
        var link = await FindLinkByTokenAsync(accessToken, cancellationToken);
        if (link is null ||
            _passwordHasher.VerifyHashedPassword(
                link.Id.ToString("N"), link.PasswordHash, password) == PasswordVerificationResult.Failed)
            throw Failure(401, "quote_client_credentials_invalid", "Неверная ссылка или пароль.");

        await _redis.KeyDeleteAsync(LoginAttemptKey(accessToken, ipAddress));
        var sessionToken = CreateToken(48);
        var expiresAt = DateTimeOffset.UtcNow.Add(ClientSessionLifetime);
        if (expiresAt > link.ExpiresAt) expiresAt = link.ExpiresAt;
        var session = new ClientSession(link.Id, link.OrganizationId, link.QuoteId, link.SchemaName.Value, expiresAt);
        await _redis.StringSetAsync(
            SessionKey(sessionToken),
            JsonSerializer.Serialize(session),
            expiresAt - DateTimeOffset.UtcNow);

        await using (var connection = await _dataSource.OpenConnectionAsync(cancellationToken))
        await using (var command = new NpgsqlCommand(
                         "UPDATE public.quote_client_access_links SET last_accessed_at = now(), access_count = access_count + 1 WHERE id = @id",
                         connection))
        {
            command.Parameters.AddWithValue("id", link.Id);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        // Счётчик просмотров виден на карточке канбана.
        await PublishQuoteChangedAsync(link.OrganizationId, link.SchemaName, link.QuoteId, cancellationToken);

        return new QuoteClientLoginResult(
            sessionToken,
            expiresAt,
            await ReadClientViewAsync(link.SchemaName, link.QuoteId, cancellationToken));
    }

    /// <inheritdoc />
    public async Task<QuoteClientView> GetAsync(string sessionToken, CancellationToken cancellationToken)
    {
        var session = await RequireSessionAsync(sessionToken, cancellationToken);
        return await ReadClientViewAsync(TenantSchemaName.Parse(session.SchemaName), session.QuoteId, cancellationToken);
    }

    /// <inheritdoc />
    public async Task<QuoteClientView> SubmitSelectionAsync(
        string sessionToken,
        SubmitQuoteClientSelectionRequest request,
        CancellationToken cancellationToken)
    {
        var session = await RequireSessionAsync(sessionToken, cancellationToken);
        var schema = TenantSchemaName.Parse(session.SchemaName);
        var selections = request.Variants ?? [];
        await using var connection = await OpenTenantConnectionAsync(schema, cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        string mode;
        await using (var header = new NpgsqlCommand("""
            SELECT selection_mode
              FROM quotes
             WHERE id = @quote_id AND deleted_at IS NULL
             FOR UPDATE
            """, connection, transaction))
        {
            header.Parameters.AddWithValue("quote_id", session.QuoteId);
            mode = await header.ExecuteScalarAsync(cancellationToken) as string
                ?? throw Failure(404, "quote_client_link_unavailable", "Предложение больше недоступно.");
        }

        async Task<JsonElement> ReadSelectionSnapshotAsync()
        {
            await using var snapshot = new NpgsqlCommand("""
                SELECT jsonb_build_object(
                    'selectionMode', quote.selection_mode,
                    'submitted', quote.client_selection_submitted_at IS NOT NULL,
                    'proposalTypeId', (SELECT proposal_type_id FROM quote_client_type_selections WHERE quote_id = quote.id),
                    'variants', COALESCE((
                        SELECT jsonb_agg(jsonb_build_object(
                            'proposalTypeId', selection.proposal_type_id, 'variantId', selection.variant_id)
                            ORDER BY selection.proposal_type_id)
                        FROM quote_proposal_type_selections AS selection
                        JOIN quote_proposal_types AS type ON type.id = selection.proposal_type_id
                        WHERE type.quote_id = quote.id
                    ), '[]'::jsonb))::text
                FROM quotes AS quote WHERE quote.id = @quote_id
                """, connection, transaction);
            snapshot.Parameters.AddWithValue("quote_id", session.QuoteId);
            return JsonSerializer.Deserialize<JsonElement>((string)(await snapshot.ExecuteScalarAsync(cancellationToken))!);
        }
        var selectionBefore = await ReadSelectionSnapshotAsync();

        if (mode == "proposal_type")
        {
            if (!request.ProposalTypeId.HasValue || selections.Count != 0)
                throw Failure(400, "quote_client_type_selection_invalid", "Выберите один тип предложения.");
            if (!await ProposalTypeBelongsToQuoteAsync(
                    connection, transaction, session.QuoteId, request.ProposalTypeId.Value, cancellationToken))
                throw Failure(400, "quote_client_type_selection_invalid", "Выбранный тип недоступен.");

            await ExecuteAsync(connection, transaction,
                "DELETE FROM quote_proposal_type_selections WHERE proposal_type_id IN (SELECT id FROM quote_proposal_types WHERE quote_id = @quote_id)",
                cancellationToken, ("quote_id", session.QuoteId));
            await ExecuteAsync(connection, transaction, """
                INSERT INTO quote_client_type_selections (quote_id, proposal_type_id, selected_at)
                VALUES (@quote_id, @type_id, now())
                ON CONFLICT (quote_id) DO UPDATE SET
                    proposal_type_id = EXCLUDED.proposal_type_id,
                    selected_at = now()
                """, cancellationToken,
                ("quote_id", session.QuoteId), ("type_id", request.ProposalTypeId.Value));
        }
        else
        {
            if (request.ProposalTypeId.HasValue)
                throw Failure(400, "quote_client_variant_selection_invalid", "Выберите варианты в нужных типах.");
            await ValidateVariantSelectionsAsync(
                connection, transaction, session.QuoteId, selections, cancellationToken);
            await ExecuteAsync(connection, transaction,
                "DELETE FROM quote_client_type_selections WHERE quote_id = @quote_id",
                cancellationToken, ("quote_id", session.QuoteId));
            await ExecuteAsync(connection, transaction,
                "DELETE FROM quote_proposal_type_selections WHERE proposal_type_id IN (SELECT id FROM quote_proposal_types WHERE quote_id = @quote_id)",
                cancellationToken, ("quote_id", session.QuoteId));
            foreach (var selection in selections)
            {
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO quote_proposal_type_selections
                        (proposal_type_id, variant_id, selected_by, selected_at)
                    VALUES (@type_id, @variant_id, NULL, now())
                    """, cancellationToken,
                    ("type_id", selection.ProposalTypeId), ("variant_id", selection.VariantId));
            }
        }

        await ExecuteAsync(connection, transaction,
            "UPDATE quotes SET client_selection_submitted_at = now(), updated_at = now() WHERE id = @quote_id",
            cancellationToken, ("quote_id", session.QuoteId));
        var selectionDiff = AuditChanges.Serialize(selectionBefore, await ReadSelectionSnapshotAsync());
        if (selectionDiff is not null)
            await ExecuteAsync(connection, transaction, """
            INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
            VALUES (NULL, 'quote', @quote_id, 'client_selection_submitted', CAST(@diff AS jsonb))
            """, cancellationToken,
            ("quote_id", session.QuoteId),
            ("diff", selectionDiff));
        await transaction.CommitAsync(cancellationToken);
        await PublishQuoteChangedAsync(session.OrganizationId, schema, session.QuoteId, cancellationToken);
        return await ReadClientViewAsync(schema, session.QuoteId, cancellationToken);
    }

    /// <summary>
    /// Сообщает сотрудникам организации, что изменилась карточка предложения:
    /// клиент открыл ссылку или отправил выбор. Действия клиента идут без JWT
    /// сотрудника, поэтому общий middleware уведомлений их не видит.
    /// </summary>
    private async Task PublishQuoteChangedAsync(
        Guid organizationId,
        TenantSchemaName schema,
        Guid quoteId,
        CancellationToken cancellationToken)
    {
        Guid? boardId = null;
        Guid? cardId = null;
        await using (var connection = await OpenTenantConnectionAsync(schema, cancellationToken))
        await using (var command = new NpgsqlCommand("""
            SELECT card.workflow_id, card.id
              FROM quotes AS quote
              JOIN kanban_cards AS card ON card.id = quote.card_id
             WHERE quote.id = @quote_id
            """, connection))
        {
            command.Parameters.AddWithValue("quote_id", quoteId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                boardId = reader.GetGuid(0);
                cardId = reader.GetGuid(1);
            }
        }
        await _realtime.PublishAsync(
            new RealtimeChange(organizationId, RealtimeTopics.Kanban, RealtimeChange.Changed, boardId, cardId),
            cancellationToken);
    }

    private async Task<ClientLink?> FindLinkByTokenAsync(string token, CancellationToken cancellationToken)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand("""
            SELECT link.id, link.organization_id, link.quote_id, link.password_hash,
                   link.expires_at, organization.schema_name
              FROM public.quote_client_access_links AS link
              JOIN public.organizations AS organization ON organization.id = link.organization_id
             WHERE link.token_hash = @token_hash
               AND link.revoked_at IS NULL
               AND link.expires_at > now()
               AND organization.is_active
               AND organization.active_until > now()
               AND organization.deleted_at IS NULL
            """, connection);
        command.Parameters.AddWithValue("token_hash", HashToken(token));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;
        return new ClientLink(
            reader.GetGuid(0), reader.GetGuid(1), reader.GetGuid(2), reader.GetString(3),
            ReadTimestamp(reader, 4), TenantSchemaName.Parse(reader.GetString(5)));
    }

    private async Task<ClientSession> RequireSessionAsync(string rawToken, CancellationToken cancellationToken)
    {
        var token = rawToken.Trim();
        if (token.Length < 32)
            throw Failure(401, "quote_client_session_invalid", "Сессия клиента недействительна.");
        var json = await _redis.StringGetAsync(SessionKey(token));
        var session = json.HasValue
            ? JsonSerializer.Deserialize<ClientSession>(json.ToString())
            : null;
        if (session is null || session.ExpiresAt <= DateTimeOffset.UtcNow)
            throw Failure(401, "quote_client_session_expired", "Сессия истекла. Введите пароль повторно.");

        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand("""
            SELECT EXISTS (
                SELECT 1
                  FROM public.quote_client_access_links AS link
                  JOIN public.organizations AS organization ON organization.id = link.organization_id
                 WHERE link.id = @link_id
                   AND link.organization_id = @organization_id
                   AND link.quote_id = @quote_id
                   AND link.revoked_at IS NULL
                   AND link.expires_at > now()
                   AND organization.is_active
                   AND organization.active_until > now()
                   AND organization.deleted_at IS NULL)
            """, connection);
        command.Parameters.AddWithValue("link_id", session.LinkId);
        command.Parameters.AddWithValue("organization_id", session.OrganizationId);
        command.Parameters.AddWithValue("quote_id", session.QuoteId);
        if (await command.ExecuteScalarAsync(cancellationToken) is not true)
            throw Failure(401, "quote_client_session_revoked", "Доступ к предложению отозван.");
        return session;
    }

    private async Task EnforceLoginRateLimitAsync(string token, string? ipAddress)
    {
        var key = LoginAttemptKey(token, ipAddress);
        var attempts = await _redis.StringIncrementAsync(key);
        if (attempts == 1) await _redis.KeyExpireAsync(key, LoginAttemptWindow);
        if (attempts > MaximumLoginAttempts)
            throw Failure(429, "quote_client_login_rate_limited", "Слишком много попыток. Повторите позже.");
    }

    private static async Task ValidateVariantSelectionsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid quoteId,
        IReadOnlyList<QuoteClientVariantSelection> selections,
        CancellationToken cancellationToken)
    {
        // Клиент выбирает по одному варианту только в нужных ему типах: пропуск
        // типа допустим, но хотя бы один выбор и не больше одного варианта на тип.
        if (selections.Count == 0)
            throw Failure(400, "quote_client_variant_selection_invalid", "Выберите хотя бы один вариант.");
        if (selections.Select(item => item.ProposalTypeId).Distinct().Count() != selections.Count)
            throw Failure(400, "quote_client_variant_selection_invalid", "В каждом типе можно выбрать только один вариант.");
        await using var command = new NpgsqlCommand("""
            SELECT proposal_type.id, variant.id
              FROM quote_proposal_types AS proposal_type
              JOIN quote_variants AS variant ON variant.proposal_type_id = proposal_type.id
             WHERE proposal_type.quote_id = @quote_id
            """, connection, transaction);
        command.Parameters.AddWithValue("quote_id", quoteId);
        var allowed = new HashSet<(Guid TypeId, Guid VariantId)>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            allowed.Add((reader.GetGuid(0), reader.GetGuid(1)));
        }
        if (selections.Any(item => !allowed.Contains((item.ProposalTypeId, item.VariantId))))
            throw Failure(400, "quote_client_variant_selection_invalid", "Выбранный вариант недоступен.");
    }

    private static async Task<bool> ProposalTypeBelongsToQuoteAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid quoteId,
        Guid proposalTypeId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "SELECT EXISTS (SELECT 1 FROM quote_proposal_types WHERE id = @type_id AND quote_id = @quote_id)",
            connection, transaction);
        command.Parameters.AddWithValue("type_id", proposalTypeId);
        command.Parameters.AddWithValue("quote_id", quoteId);
        return await command.ExecuteScalarAsync(cancellationToken) is true;
    }

    private async Task<QuoteClientView> ReadClientViewAsync(
        TenantSchemaName schema,
        Guid quoteId,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenTenantConnectionAsync(schema, cancellationToken);
        ClientHeader header;
        Guid workflowId;
        await using (var command = new NpgsqlCommand("""
            SELECT quote.id, quote.quote_kind, quote.title,
                   COALESCE(NULLIF(btrim(company.legal_name), ''), company.name),
                   quote.selection_mode, quote.additional_information,
                   selected_type.proposal_type_id, quote.client_selection_submitted_at,
                   quote.updated_at, client.name, quote.workflow_id
              FROM quotes AS quote
              JOIN companies AS company ON company.id = quote.executor_company_id
              LEFT JOIN clients AS client ON client.id = quote.client_id
              LEFT JOIN quote_client_type_selections AS selected_type ON selected_type.quote_id = quote.id
             WHERE quote.id = @quote_id AND quote.deleted_at IS NULL
            """, connection))
        {
            command.Parameters.AddWithValue("quote_id", quoteId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
                throw Failure(404, "quote_client_link_unavailable", "Предложение больше недоступно.");
            header = new ClientHeader(
                reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
                reader.GetString(4), reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetGuid(6),
                reader.IsDBNull(7) ? null : ReadTimestamp(reader, 7), ReadTimestamp(reader, 8),
                reader.IsDBNull(9) ? null : reader.GetString(9));
            workflowId = reader.GetGuid(10);
        }

        var layouts = await PostgresDocumentLayoutService.ReadFieldsAsync(connection, workflowId, cancellationToken);
        var template = await PostgresDocumentLayoutService.ReadTemplateAsync(connection, workflowId, cancellationToken);
        if (template is null)
            throw Failure(409, "document_layout_required",
                "Внешний вид предложения пока не настроен. Обратитесь к отправителю ссылки.");

        var types = new List<MutableClientType>();
        var typesById = new Dictionary<Guid, MutableClientType>();
        await using (var command = new NpgsqlCommand("""
            SELECT type.id, type.name, selection.variant_id
              FROM quote_proposal_types AS type
              LEFT JOIN quote_proposal_type_selections AS selection ON selection.proposal_type_id = type.id
             WHERE type.quote_id = @quote_id
             ORDER BY type.sort_order, type.id
            """, connection))
        {
            command.Parameters.AddWithValue("quote_id", quoteId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var item = new MutableClientType(
                    reader.GetGuid(0), reader.GetString(1), reader.IsDBNull(2) ? null : reader.GetGuid(2));
                types.Add(item);
                typesById[item.Id] = item;
            }
        }

        var variantsById = new Dictionary<Guid, MutableClientVariant>();
        await using (var command = new NpgsqlCommand("""
            SELECT variant.id, variant.proposal_type_id, variant.name, variant.subtitle, variant.vat_rate
              FROM quote_variants AS variant
              JOIN quote_proposal_types AS type ON type.id = variant.proposal_type_id
             WHERE type.quote_id = @quote_id
             ORDER BY type.sort_order, variant.sort_order, variant.id
            """, connection))
        {
            command.Parameters.AddWithValue("quote_id", quoteId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var item = new MutableClientVariant(
                    reader.GetGuid(0), reader.GetString(2), reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetDecimal(4));
                typesById[reader.GetGuid(1)].Variants.Add(item);
                variantsById[item.Id] = item;
            }
        }

        var categoriesById = new Dictionary<Guid, MutableClientCategory>();
        await using (var command = new NpgsqlCommand("""
            SELECT category.id, category.variant_id, category.name_snapshot, category.catalog_category_id
              FROM quote_variant_categories AS category
              JOIN quote_variants AS variant ON variant.id = category.variant_id
              JOIN quote_proposal_types AS type ON type.id = variant.proposal_type_id
             WHERE type.quote_id = @quote_id
             ORDER BY type.sort_order, variant.sort_order, category.sort_order, category.id
            """, connection))
        {
            command.Parameters.AddWithValue("quote_id", quoteId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var item = new MutableClientCategory(reader.GetGuid(0), reader.GetString(2));
                item.CatalogCategoryId = reader.IsDBNull(3) ? null : reader.GetGuid(3);
                if (!reader.IsDBNull(3) && layouts.TryGetValue(reader.GetGuid(3), out var fields)) item.Fields = fields;
                if (template is not null) item.Fields ??= [];
                variantsById[reader.GetGuid(1)].Categories.Add(item);
                categoriesById[item.Id] = item;
            }
        }

        var sectionsById = new Dictionary<Guid, MutableClientSection>();
        await using (var command = new NpgsqlCommand("""
            SELECT section.id, section.variant_category_id, section.name_snapshot
              FROM quote_variant_sections AS section
              JOIN quote_variant_categories AS category ON category.id = section.variant_category_id
              JOIN quote_variants AS variant ON variant.id = category.variant_id
              JOIN quote_proposal_types AS type ON type.id = variant.proposal_type_id
             WHERE type.quote_id = @quote_id
             ORDER BY type.sort_order, variant.sort_order, category.sort_order, section.sort_order, section.id
            """, connection))
        {
            command.Parameters.AddWithValue("quote_id", quoteId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var item = new MutableClientSection(reader.GetGuid(0), reader.GetString(2))
                    { Fields = categoriesById[reader.GetGuid(1)].Fields };
                categoriesById[reader.GetGuid(1)].Sections.Add(item);
                sectionsById[item.Id] = item;
            }
        }

        await using (var command = new NpgsqlCommand("""
            SELECT position.id, position.variant_section_id, position.name_snapshot,
                   position.marking_snapshot, position.unit_snapshot, position.quantity,
                   position.line_total, position.values::text, position.base_price, position.manual_price,
                   position.purchase_price, position.markup_percent, position.discount_percent
              FROM quote_positions AS position
              JOIN quote_variant_sections AS section ON section.id = position.variant_section_id
              JOIN quote_variant_categories AS category ON category.id = section.variant_category_id
              JOIN quote_variants AS variant ON variant.id = category.variant_id
              JOIN quote_proposal_types AS type ON type.id = variant.proposal_type_id
             WHERE type.quote_id = @quote_id AND NOT position.exclude_from_totals
             ORDER BY type.sort_order, variant.sort_order, category.sort_order,
                      section.sort_order, position.sort_order, position.id
            """, connection))
        {
            command.Parameters.AddWithValue("quote_id", quoteId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var quantity = reader.GetDecimal(5);
                var total = reader.GetDecimal(6);
                var section = sectionsById[reader.GetGuid(1)];
                IReadOnlyList<string>? cells = null;
                if (section.Fields is { } fields)
                {
                    var values = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(reader.GetString(7)) ?? [];
                    var row = new QuotePositionDetails(reader.GetGuid(0), null, reader.GetString(2), reader.GetString(3), reader.GetString(4),
                        quantity, reader.IsDBNull(10) ? null : reader.GetDecimal(10), reader.GetDecimal(8),
                        reader.IsDBNull(9) ? null : reader.GetDecimal(9), reader.IsDBNull(11) ? null : reader.GetDecimal(11),
                        reader.IsDBNull(12) ? null : reader.GetDecimal(12), total, false, values, 0);
                    cells = fields.Select(field => DocumentFieldValue.Quote(field, row)).ToArray();
                }
                section.Positions.Add(new QuoteClientPosition(
                    reader.GetGuid(0), reader.GetString(2), reader.GetString(3), reader.GetString(4),
                    quantity, quantity == 0 ? 0 : decimal.Round(total / quantity, 2), total, cells));
            }
        }

        var details = types.Select(item => item.ToDetails()).ToArray();
        DocumentCanvasContent? headerDocument = null;
        if (template is not null)
        {
            IReadOnlyDictionary<string, string?> clientValues = new Dictionary<string, string?>();
            IReadOnlyDictionary<string, string?> executorValues = new Dictionary<string, string?>();
            await using (var command = new NpgsqlCommand("""
                SELECT to_jsonb(client)::text, to_jsonb(company)::text
                FROM quotes AS quote
                JOIN companies AS company ON company.id = quote.executor_company_id
                LEFT JOIN clients AS client ON client.id = quote.client_id
                WHERE quote.id = @quote
                """, connection))
            {
                command.Parameters.AddWithValue("quote", quoteId);
                await using var reader = await command.ExecuteReaderAsync(cancellationToken);
                if (await reader.ReadAsync(cancellationToken))
                {
                    using var clientJson = JsonDocument.Parse(reader.IsDBNull(0) ? "{}" : reader.GetString(0));
                    using var executorJson = JsonDocument.Parse(reader.GetString(1));
                    clientValues = DocumentCanvasBuilder.JsonParty(clientJson.RootElement);
                    executorValues = DocumentCanvasBuilder.JsonParty(executorJson.RootElement);
                }
            }
            if (template.Blocks.Any(block => block.Kind is "client" or "executor"))
                headerDocument = DocumentCanvasBuilder.Parties(template, clientValues, executorValues);
            details = details.Select(type => type with { Variants = type.Variants.Select(variant => variant with {
                Document = DocumentCanvasBuilder.WithoutParties(DocumentCanvasBuilder.Build(template, clientValues, executorValues,
                    variant.Categories.SelectMany(category => category.Sections.Where(section => section.Columns is { Count: > 0 })
                        .Select(section => new DocumentCanvasTable($"{category.Name} / {section.Name}",
                            section.Columns!.Select(c => c.Label).ToArray(),
                            DocumentCanvasBuilder.Widths(template, categoriesById[category.Id].CatalogCategoryId, section.Columns!.Select(c => c.Code)),
                            section.Positions.Select(p => p.Cells ?? (IReadOnlyList<string>)[]).ToArray(),
                            categoriesById[category.Id].CatalogCategoryId,
                            section.Total ?? section.Positions.Sum(position => position.LineTotal),
                            category.Sections.Sum(part => part.Total ?? part.Positions.Sum(position => position.LineTotal))))).ToArray(),
                    DocumentCanvasBuilder.Totals(variant.Subtotal, variant.VatAmount))),
                Categories = []
            }).ToArray() }).ToArray();
        }
        return new QuoteClientView(
            header.Id, header.Kind, header.Title, template is null ? header.ExecutorName : "", header.SelectionMode,
            header.AdditionalInformation, header.SelectedProposalTypeId,
            details, header.SubmittedAt, header.UpdatedAt,
            template is null ? header.ClientName : null, headerDocument);
    }

    private async Task<NpgsqlConnection> OpenTenantConnectionAsync(
        TenantSchemaName schema,
        CancellationToken cancellationToken)
    {
        var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        try
        {
            await using var command = new NpgsqlCommand($"SET search_path TO {schema.Value}, public", connection);
            await command.ExecuteNonQueryAsync(cancellationToken);
            return connection;
        }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }
    }

    private static async Task ExecuteAsync(
        DbConnection connection,
        DbTransaction transaction,
        string sql,
        CancellationToken token,
        params (string Name, object Value)[] parameters)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        foreach (var (name, value) in parameters)
        {
            var parameter = command.CreateParameter();
            parameter.ParameterName = name;
            parameter.Value = value;
            command.Parameters.Add(parameter);
        }
        await command.ExecuteNonQueryAsync(token);
    }

    private byte[] Protect(string value) =>
        IdentitySecurity.ProtectSecret(Encoding.UTF8.GetBytes(value), _secretKey);

    private string Unprotect(byte[] value) =>
        Encoding.UTF8.GetString(IdentitySecurity.UnprotectSecret(value, _secretKey));

    private static string CreateToken(int byteCount) =>
        WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(byteCount));

    private static byte[] HashToken(string token) => SHA256.HashData(Encoding.UTF8.GetBytes(token));

    private static string CreatePassword(int length)
    {
        var bytes = RandomNumberGenerator.GetBytes(length);
        return string.Create(length, bytes, static (buffer, source) =>
        {
            for (var index = 0; index < buffer.Length; index++)
                buffer[index] = PasswordAlphabet[source[index] % PasswordAlphabet.Length];
        });
    }

    private static string SessionKey(string token) => $"quote-client:session:{Convert.ToHexString(HashToken(token))}";

    private static string LoginAttemptKey(string token, string? ipAddress) =>
        $"quote-client:login:{Convert.ToHexString(HashToken($"{token}|{ipAddress ?? "unknown"}"))}";

    private static DateTimeOffset ReadTimestamp(DbDataReader reader, int ordinal) =>
        new(reader.GetFieldValue<DateTime>(ordinal));

    private static IdentityException Failure(int status, string code, string message) => new(status, code, message);

    private sealed record ClientLink(
        Guid Id,
        Guid OrganizationId,
        Guid QuoteId,
        string PasswordHash,
        DateTimeOffset ExpiresAt,
        TenantSchemaName SchemaName);

    private sealed record ClientSession(
        Guid LinkId,
        Guid OrganizationId,
        Guid QuoteId,
        string SchemaName,
        DateTimeOffset ExpiresAt);

    private sealed record ClientHeader(
        Guid Id,
        string Kind,
        string Title,
        string ExecutorName,
        string SelectionMode,
        string? AdditionalInformation,
        Guid? SelectedProposalTypeId,
        DateTimeOffset? SubmittedAt,
        DateTimeOffset UpdatedAt,
        string? ClientName);

    private sealed class MutableClientType(Guid id, string name, Guid? selectedVariantId)
    {
        public Guid Id { get; } = id;
        public List<MutableClientVariant> Variants { get; } = [];
        public QuoteClientProposalType ToDetails() =>
            new(Id, name, selectedVariantId, Variants.Select(item => item.ToDetails()).ToArray());
    }

    private sealed class MutableClientVariant(Guid id, string name, string? subtitle, decimal? vatRate)
    {
        public Guid Id { get; } = id;
        public List<MutableClientCategory> Categories { get; } = [];
        public QuoteClientVariant ToDetails()
        {
            var subtotal = Categories.SelectMany(item => item.Sections)
                .SelectMany(item => item.Positions).Sum(item => item.LineTotal);
            var vat = QuoteVatCalculator.Calculate(subtotal, vatRate);
            return new QuoteClientVariant(
                Id, name, subtitle, vatRate, subtotal, vat, subtotal + vat,
                Categories.Select(item => item.ToDetails()).ToArray());
        }
    }

    private sealed class MutableClientCategory(Guid id, string name)
    {
        public Guid Id { get; } = id;
        public Guid? CatalogCategoryId { get; set; }
        public IReadOnlyList<KanbanFieldSummary>? Fields { get; set; }
        public List<MutableClientSection> Sections { get; } = [];
        public QuoteClientCategory ToDetails() =>
            new(Id, name, Sections.Select(item => item.ToDetails()).ToArray());
    }

    private sealed class MutableClientSection(Guid id, string name)
    {
        public Guid Id { get; } = id;
        public IReadOnlyList<KanbanFieldSummary>? Fields { get; init; }
        public List<QuoteClientPosition> Positions { get; } = [];
        public QuoteClientSection ToDetails() => Fields is null ? new(Id, name, Positions) :
            QuoteClientSection.Configured(Id, name, Positions,
                Fields.Select(field => new DocumentColumn(field.Code, field.Label)).ToArray());
    }
}
