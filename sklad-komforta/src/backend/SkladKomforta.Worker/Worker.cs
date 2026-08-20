namespace SkladKomforta.Worker;

/// <summary>
/// Поддерживает процесс фонового worker-а до подключения очередей модулей.
/// Реальные обработчики будут добавляться отдельными hosted services, а не
/// объединяться в один бесконечный цикл.
/// </summary>
public sealed partial class Worker(ILogger<Worker> logger) : BackgroundService
{
    /// <summary>Запускает lifetime worker-а и корректно обрабатывает остановку host.</summary>
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        LogWorkerStarted(logger);

        try
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, stoppingToken);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            LogWorkerStopped(logger);
        }
    }

    [LoggerMessage(LogLevel.Information, "Фоновый обработчик запущен.")]
    private static partial void LogWorkerStarted(ILogger logger);

    [LoggerMessage(LogLevel.Information, "Фоновый обработчик остановлен.")]
    private static partial void LogWorkerStopped(ILogger logger);
}
