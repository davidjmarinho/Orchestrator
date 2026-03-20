using RabbitMQ.Client;

namespace Orchestrator.Infrastructure;

public class RabbitMqConnectionFactory
{
    private readonly string _host;
    private readonly int _port;
    private readonly string _user;
    private readonly string _password;

    public RabbitMqConnectionFactory(string host, int port, string user, string password)
    {
        _host = host;
        _port = port;
        _user = user;
        _password = password;
    }

    public IConnection CreateConnection()
    {
        var factory = new ConnectionFactory
        {
            HostName = _host,
            Port = _port,
            UserName = _user,
            Password = _password
        };

        return factory.CreateConnection();
    }
}