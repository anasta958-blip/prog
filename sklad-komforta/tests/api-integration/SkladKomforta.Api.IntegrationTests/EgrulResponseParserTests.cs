using SkladKomforta.Infrastructure.Company;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class EgrulResponseParserTests
{
    [Fact]
    public void SearchResultForLegalEntityProvidesRequisitesAndDirector()
    {
        const string json = """
            {"rows":[{"c":"ПАО СБЕРБАНК","g":"ПРЕЗИДЕНТ, ПРЕДСЕДАТЕЛЬ ПРАВЛЕНИЯ: Греф Герман Оскарович",
            "i":"7707083893","k":"ul","n":"ПУБЛИЧНОЕ АКЦИОНЕРНОЕ ОБЩЕСТВО \"СБЕРБАНК РОССИИ\"",
            "o":"1027700132195","p":"773601001","t":"TOKEN","rn":"Г.Москва"}]}
            """;

        var (record, token) = EgrulResponseParser.ParseSearchResult(json, "7707083893")!.Value;

        Assert.Equal("ooo", record.CompanyType);
        Assert.Equal("ПАО СБЕРБАНК", record.Name);
        Assert.Equal("ПУБЛИЧНОЕ АКЦИОНЕРНОЕ ОБЩЕСТВО \"СБЕРБАНК РОССИИ\"", record.LegalName);
        Assert.Equal("773601001", record.Kpp);
        Assert.Equal("1027700132195", record.Ogrn);
        Assert.Equal("Греф Герман Оскарович", record.DirectorName);
        Assert.Equal("Президент, председатель правления", record.DirectorTitle);
        Assert.Null(record.Address);
        Assert.Equal("TOKEN", token);
    }

    [Fact]
    public void SearchResultForIndividualUsesReadableNameWithoutKpp()
    {
        const string json = """
            {"rows":[{"i":"500123456750","k":"fl","n":"ИВАНОВ ИВАН ИВАНОВИЧ","o":"304500116000157","p":"123456789"}]}
            """;

        var (record, _) = EgrulResponseParser.ParseSearchResult(json, "500123456750")!.Value;

        Assert.Equal("ip", record.CompanyType);
        Assert.Equal("ИП Иванов Иван Иванович", record.Name);
        Assert.Equal("Иванов Иван Иванович", record.LegalName);
        Assert.Equal("Иванов Иван Иванович", record.DirectorName);
        Assert.Null(record.Kpp);
    }

    [Theory]
    [InlineData("""{"rows":[]}""")]
    [InlineData("""{"rows":[{"i":"7707083894","n":"ДРУГАЯ КОМПАНИЯ"}]}""")]
    [InlineData("""{"error":"x"}""")]
    public void SearchResultWithoutExactInnIsNotFound(string json)
    {
        Assert.Null(EgrulResponseParser.ParseSearchResult(json, "7707083893"));
    }

    [Fact]
    public void AddressIsReadFromExtractPageAndStopsAtRegistrationNumber()
    {
        const string page = """
            Место нахождения и адрес юридического лица
            5 Адрес юридического лица
            6 ГРН и дата внесения в ЕГРЮЛ записи, содержащей указанные сведения
            117312, Г.МОСКВА, УЛ. ВАВИЛОВА, Д.19
            1027700132195 16.08.2002
            """;

        Assert.Equal("117312, Г.МОСКВА, УЛ. ВАВИЛОВА, Д.19", EgrulResponseParser.ParseAddress(page));
    }

    [Fact]
    public void AddressInPdfPigLayoutStartsOnLabelLine()
    {
        // Так ContentOrderTextExtractor (PdfPig) раскладывает первую страницу выписки.
        const string page = "5 Адрес юридического лица 117312,\nГ.МОСКВА,\nУЛ. ВАВИЛОВА,\nД.19\n6 ГРН и дата внесения в ЕГРЮЛ записи,\n1027700132195";

        Assert.Equal("117312, Г.МОСКВА, УЛ. ВАВИЛОВА, Д.19", EgrulResponseParser.ParseAddress(page));
    }

    [Fact]
    public void WrappedAddressIsJoined()
    {
        const string page = "Адрес юридического лица\n123456, ОБЛАСТЬ МОСКОВСКАЯ,\nГ. ХИМКИ, УЛ. ЛЕНИНА, Д. 1\n1027700000000 01.01.2020";

        Assert.Equal("123456, ОБЛАСТЬ МОСКОВСКАЯ, Г. ХИМКИ, УЛ. ЛЕНИНА, Д. 1", EgrulResponseParser.ParseAddress(page));
    }

    [Fact]
    public void EmailIsReadFromEmailSectionInLowerCase()
    {
        const string text = "Сведения о гражданстве\nАдрес электронной почты\n6 E-mail\nAIRCOOLING_SKORNYAKOV@MAIL.RU\n7 ГРН и дата";

        Assert.Equal("aircooling_skornyakov@mail.ru", EgrulResponseParser.ParseEmail(text));
    }

    [Fact]
    public void WrappedEmailInPdfPigLayoutIsJoinedWithHyphen()
    {
        // Так PdfPig раскладывает длинный e-mail в выписке ЕГРЮЛ.
        const string text = "Адрес электронной почты\n7 E-mail REGISTER-YANDEX@YANDEX-\nTEAM.RU\n8 ГРН и дата внесения в ЕГРЮЛ записи,\n2217705543999";

        Assert.Equal("register-yandex@yandex-team.ru", EgrulResponseParser.ParseEmail(text));
    }

    [Theory]
    [InlineData("Выписка без раздела почты")]
    [InlineData("Адрес электронной почты\n6 E-mail\nне указан")]
    public void MissingEmailIsNull(string text)
    {
        Assert.Null(EgrulResponseParser.ParseEmail(text));
    }

    [Theory]
    [InlineData("Выписка без блока адреса")]
    [InlineData("Адрес юридического лица\nГ.МОСКВА без индекса\n1027700000000 01.01.2020")]
    public void UnrecognizedAddressIsNull(string page)
    {
        Assert.Null(EgrulResponseParser.ParseAddress(page));
    }
}
