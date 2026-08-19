# SentinelCxD

Reusable, customer-neutral Microsoft Sentinel content engineered for
deployment through Azure Resource Manager or Microsoft Sentinel Repositories.

## Content packs

| Pack | Coverage | Deployment |
|------|----------|------------|
| [ZscalerViaCriblwithASIM](ZscalerViaCriblwithASIM/README.md) | ZIA and ZPA through Cribl, normalized with ASIM | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FCrisDea%2FSentinelCxD%2Fmain%2FZscalerViaCriblwithASIM%2FPackage%2FmainTemplate.json) |

## Connect to Microsoft Sentinel

In the Microsoft Defender portal, open **Microsoft Sentinel** >
**Content management** > **Repositories**, connect `CrisDea/SentinelCxD`, and
select branch `main`.

For the Zscaler pack, scope the generated repository workflow to:

```text
ZscalerViaCriblwithASIM/RepositoryContent
```

Detailed connection and workflow-path instructions are in
[the pack deployment guide](ZscalerViaCriblwithASIM/docs/defender-repository-deployment.md).

## Data handling

This repository must not contain customer identifiers, tenant or subscription
IDs, workspace names, credentials, secrets, production logs, or exported
incident data. All environment-specific values are supplied at deployment
time.

## License

MIT. Individual content packs may include additional upstream attribution.
