using SkladKomforta.Domain.Authentication;

namespace SkladKomforta.Domain.Tests.Authentication;

public sealed class TokenLifetimePolicyTests
{
    [Fact]
    public void AccessTokenLifetimeIsFifteenMinutes() =>
        Assert.Equal(TimeSpan.FromMinutes(15), TokenLifetimePolicy.AccessTokenLifetime);

    [Theory]
    [InlineData(DeviceType.Web, 7)]
    [InlineData(DeviceType.Windows, 30)]
    [InlineData(DeviceType.Android, 30)]
    [InlineData(DeviceType.Ios, 30)]
    [InlineData(DeviceType.MacOs, 30)]
    public void RefreshTokenLifetimeDependsOnDevice(DeviceType deviceType, int days) =>
        Assert.Equal(TimeSpan.FromDays(days), TokenLifetimePolicy.GetRefreshTokenLifetime(deviceType));
}
