# Deploy from Microsoft Sentinel Repositories

Microsoft Sentinel Repositories can continuously deploy this pack from GitHub
to a Sentinel workspace in the Microsoft Defender portal.

## Prerequisites

- Owner on the resource group containing the Sentinel workspace.
- Collaborator access to `CrisDea/SentinelCxD`.
- GitHub Actions enabled.
- The connecting identity must be a member of the Sentinel workspace tenant;
  B2B guest and delegated identities are not supported by repository
  connections.

## Connect the repository

1. Open `https://security.microsoft.com`.
2. Select **Microsoft Sentinel** > **Content management** >
   **Repositories**.
3. Select **Add new**, choose **GitHub**, and authorize the connection.
4. Select repository `CrisDea/SentinelCxD` and branch `main`.
5. Install the **Azure-Sentinel** GitHub app on this repository when prompted.
6. Select the required content types and create the connection.

Sentinel creates a workflow named `.github/workflows/sentinel-deploy-*.yml`.

## Scope the workflow to this pack

Edit the generated workflow so its push paths include only:

```yaml
paths:
  - 'ZscalerViaCriblwithASIM/**'
  - '!.github/workflows/**'
  - '.github/workflows/sentinel-deploy-<deployment-id>.yml'
```

Set the deployment directory in the workflow job to:

```yaml
directory: '${{ github.workspace }}/ZscalerViaCriblwithASIM/RepositoryContent'
```

Keep the trigger path and deployment directory consistent. The
`RepositoryContent/main.bicep` wrapper receives the `workspace` parameter from
the Sentinel-generated workflow and compiles the complete pack from source.

## Safety state

Repository deployment creates the content and Cribl ingestion landing zone,
but leaves both Logic Apps, Zscaler mutation, and the Sentinel automation rule
disabled. Complete Key Vault secret creation, Teams authorization, caller
authorization, Cribl tests, and controlled mutation testing before enabling
response automation.

## References

- [Deploy content as code from your repository](https://learn.microsoft.com/azure/sentinel/ci-cd)
- [Customize repository deployments](https://learn.microsoft.com/azure/sentinel/ci-cd-custom-deploy)
