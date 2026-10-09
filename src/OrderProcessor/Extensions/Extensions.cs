using System.Text.Json.Serialization;
using eShop.OrderProcessor.Events;
using Npgsql;

namespace eShop.OrderProcessor.Extensions;

public static class Extensions
{
    public static void AddApplicationServices(this IHostApplicationBuilder builder)
    {
        builder.AddRabbitMqEventBus("eventbus")
               .ConfigureJsonOptions(options => options.TypeInfoResolverChain.Add(IntegrationEventContext.Default));

        var orderingConnectionString = builder.Configuration.GetConnectionString("orderingdb")
            ?? throw new InvalidOperationException("Connection string 'orderingdb' not found.");
        builder.Services.AddSingleton<NpgsqlDataSource>(_ => new NpgsqlDataSourceBuilder(orderingConnectionString).Build());

        builder.Services.AddOptions<BackgroundTaskOptions>()
            .BindConfiguration(nameof(BackgroundTaskOptions));

        builder.Services.AddSingleton<IGracePeriodOrdersRepository, GracePeriodOrdersRepository>();
        builder.Services.AddHostedService<GracePeriodManagerService>();
    }
}

[JsonSerializable(typeof(GracePeriodConfirmedIntegrationEvent))]
partial class IntegrationEventContext : JsonSerializerContext
{

}
