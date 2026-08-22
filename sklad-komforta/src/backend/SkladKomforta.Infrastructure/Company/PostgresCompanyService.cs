using System.Data.Common;
using System.Text.Json;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Infrastructure.Company;

/// <summary>Работает с единственным профилем организации в текущей tenant-схеме.</summary>
internal sealed class PostgresCompanyService(
    IDatabaseConnectionFactory connectionFactory,
    ITenantContext tenantContext) : ICompanyService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<CompanyProfile> GetAsync(CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        return await ReadAsync(connection, cancellationToken);
    }

    public async Task<CompanyProfile> UpdateAsync(
        Guid userId,
        CompanyProfile profile,
        CancellationToken cancellationToken)
    {
        OnboardingValidator.ValidateCompany(new CompanyProfileDraft(
            profile.OrganizationName, profile.CompanyType, profile.LegalName,
            profile.Inn, profile.Kpp, profile.Ogrn, profile.Address,
            profile.Phone, profile.Email));

        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var before = await ReadAsync(connection, cancellationToken, transaction);

        await ExecuteAsync(connection, transaction, """
            UPDATE organization_profile SET
                organization_name = @name, company_type = @type, legal_name = @legal,
                inn = @inn, kpp = @kpp, ogrn = @ogrn, address = @address,
                phone = @phone, email = @email, updated_by = @user_id, updated_at = now()
            WHERE singleton
            """, cancellationToken,
            ("name", profile.OrganizationName.Trim()), ("type", Db(profile.CompanyType)),
            ("legal", Db(profile.LegalName)), ("inn", Db(profile.Inn)),
            ("kpp", Db(profile.Kpp)), ("ogrn", Db(profile.Ogrn)),
            ("address", Db(profile.Address)), ("phone", Db(profile.Phone)),
            ("email", Db(profile.Email)), ("user_id", userId));

        await ExecuteAsync(connection, transaction,
            "UPDATE public.organizations SET name = @name, updated_at = now() WHERE id = @organization_id",
            cancellationToken,
            ("name", profile.OrganizationName.Trim()), ("organization_id", tenantContext.OrganizationId));

        await ExecuteAsync(connection, transaction, """
            INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
            VALUES (@user_id, 'organization_profile', @organization_id, 'updated', CAST(@diff AS jsonb))
            """, cancellationToken,
            ("user_id", userId), ("organization_id", tenantContext.OrganizationId),
            ("diff", JsonSerializer.Serialize(new { before, after = profile }, JsonOptions)));

        await transaction.CommitAsync(cancellationToken);
        return await ReadAsync(connection, cancellationToken);
    }

    private static async Task<CompanyProfile> ReadAsync(
        DbConnection connection,
        CancellationToken token,
        DbTransaction? transaction = null)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT organization_name, company_type, legal_name, inn, kpp, ogrn,
                   address, phone, email
            FROM organization_profile
            WHERE singleton
            """;
        await using var reader = await command.ExecuteReaderAsync(token);
        if (!await reader.ReadAsync(token))
            throw new IdentityException(404, "company_profile_not_found", "Данные компании не найдены.");
        return new CompanyProfile(
            reader.GetString(0), NullableString(reader, 1), NullableString(reader, 2),
            NullableString(reader, 3), NullableString(reader, 4), NullableString(reader, 5),
            NullableString(reader, 6), NullableString(reader, 7), NullableString(reader, 8));
    }

    private static string? NullableString(DbDataReader reader, int index) =>
        reader.IsDBNull(index) ? null : reader.GetString(index);

    private static object Db(string? value) =>
        string.IsNullOrWhiteSpace(value) ? DBNull.Value : value.Trim();

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
}
