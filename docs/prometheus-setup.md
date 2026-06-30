# Configuração do Prometheus no Orchestrator

## Visão Geral

Este documento descreve o passo a passo para adicionar o Prometheus como serviço de coleta de métricas ao projeto Orchestrator, rodando no Kubernetes dentro do namespace `fcg-tech-fase-2`.

---

## Pré-requisitos

- Cluster Kubernetes rodando (Docker Desktop, Minikube, etc.)
- `kubectl` configurado e apontando para o cluster
- Namespace `fcg-tech-fase-2` já criado
- Orchestrator já deployado no cluster

---

## Etapa 1: Configurar o Orchestrator para expor métricas

### 1.1 Instalar o pacote NuGet

No projeto do Orchestrator, adicionar o pacote de métricas do Prometheus:

```bash
dotnet add package prometheus-net.AspNetCore
```

### 1.2 Configurar o `Program.cs`

Adicionar as seguintes linhas no `Program.cs` do Orchestrator:

```csharp
using Prometheus;

// Após o builder.Build()
app.UseHttpMetrics();  // Coleta métricas de requisições HTTP automaticamente
app.MapMetrics();      // Expõe o endpoint GET /metrics
```

### 1.3 Validar localmente

Rodar o Orchestrator localmente e acessar:

```
http://localhost:<porta>/metrics
```

Deve retornar um texto com métricas no formato Prometheus, por exemplo:

```
# HELP http_requests_received_total Total number of HTTP requests received.
# TYPE http_requests_received_total counter
http_requests_received_total{code="200",method="GET",controller="Health"} 5
```

### 1.4 Rebuild da imagem Docker

Após as alterações, gerar uma nova imagem Docker do Orchestrator:

```bash
docker build -t orchestrator-api:latest .
```

---

## Etapa 2: Criar o manifest do Prometheus no Kubernetes

### 2.1 Criar o arquivo `k8s/prometheus-deployment.yaml`

O arquivo deve conter **3 recursos**:

| Recurso | Finalidade |
|---|---|
| **ConfigMap** | Arquivo `prometheus.yml` com as configurações de scraping |
| **Deployment** | Pod do Prometheus usando a imagem `prom/prometheus` |
| **Service** | Exposição interna do Prometheus na porta `9090` |

### 2.2 Estrutura do ConfigMap

O `prometheus.yml` deve conter:

- **`global.scrape_interval`**: intervalo de coleta (sugestão: `15s`)
- **`scrape_configs`**: lista de jobs com os targets dos serviços a monitorar

Exemplo de job para o Orchestrator:

| Campo | Valor |
|---|---|
| `job_name` | `orchestrator` |
| `metrics_path` | `/metrics` |
| `targets` | `orchestrator-service:<porta>` (nome do Service do Orchestrator no k8s) |

### 2.3 Estrutura do Deployment

| Campo | Valor |
|---|---|
| `image` | `prom/prometheus:latest` |
| `containerPort` | `9090` |
| `volumeMount` | Montar o ConfigMap em `/etc/prometheus/prometheus.yml` |
| `namespace` | `fcg-tech-fase-2` |
| `replicas` | `1` |

### 2.4 Estrutura do Service

| Campo | Valor |
|---|---|
| `port` | `9090` |
| `targetPort` | `9090` |
| `type` | `ClusterIP` |
| `namespace` | `fcg-tech-fase-2` |

### 2.5 Estrutura final de arquivos

```
Orchestrator/
├── k8s/
│   ├── mongodb-deployment.yaml         (já existe)
│   ├── orchestrator-deployment.yaml    (já existe)
│   └── prometheus-deployment.yaml      (a ser criado)
├── src/
│   └── Program.cs                      (a ser alterado)
└── docs/
    └── prometheus-setup.md             (este documento)
```

---

## Etapa 3: Deploy no Kubernetes

### 3.1 Aplicar o manifest do Prometheus

```bash
kubectl apply -f k8s/prometheus-deployment.yaml
```

### 3.2 Verificar se o pod subiu

```bash
kubectl get pods -n fcg-tech-fase-2 -l app=prometheus
```

Esperado: status `Running`.

### 3.3 Verificar logs do Prometheus

```bash
kubectl logs -n fcg-tech-fase-2 -l app=prometheus
```

---

## Etapa 4: Acessar o Prometheus

### 4.1 Port-forward para acesso local

```bash
kubectl port-forward svc/prometheus 9090:9090 -n fcg-tech-fase-2
```

### 4.2 Acessar a UI

Abrir no navegador:

```
http://localhost:9090
```

### 4.3 Validar que o Orchestrator está sendo monitorado

1. Na UI do Prometheus, ir em **Status > Targets**
2. O job `orchestrator` deve aparecer com estado **UP**
3. Na aba **Graph**, testar uma query:

```promql
http_requests_received_total
```

---

## Possíveis Problemas

| Problema | Causa provável | Solução |
|---|---|---|
| Target com estado `DOWN` | Orchestrator não expõe `/metrics` | Verificar se o pacote `prometheus-net` foi adicionado e a imagem foi rebuilded |
| Target não aparece | Nome do Service errado no `targets` | Conferir o nome do Service do Orchestrator com `kubectl get svc -n fcg-tech-fase-2` |
| Pod do Prometheus em `CrashLoopBackOff` | Erro no `prometheus.yml` (YAML inválido) | Verificar logs com `kubectl logs` e validar o YAML do ConfigMap |

---

## Próximos Passos (opcional)

- [ ] Adicionar **Grafana** para dashboards visuais
- [ ] Criar métricas customizadas no Orchestrator (ex: tempo de processamento de pedidos)
- [ ] Adicionar outros microsserviços ao `scrape_configs`
- [ ] Configurar **alertas** no Prometheus (AlertManager)