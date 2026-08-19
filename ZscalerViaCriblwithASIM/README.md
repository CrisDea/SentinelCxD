# Zscaler ASIM for Microsoft Sentinel

This repository contains Microsoft Sentinel content for Zscaler Internet
Access (ZIA) and Zscaler Private Access (ZPA) when events are normalized by
Cribl and exposed through the Advanced Security Information Model (ASIM).

The content queries ASIM unifying parsers instead of `CommonSecurityLog`,
`ZPAEvent`, or a Cribl-specific table:

- `_Im_AuditEvent`
- `_Im_Authentication`
- `_Im_Dns`
- `_Im_FileEvent`
- `_Im_NetworkSession`
- `_Im_WebSession`

## Included content

- 12 ASIM-aware scheduled analytic rules: 2 ZIA and 10 ZPA
- 10 ASIM-aware ZPA hunting queries
- 18 standard-workbook equivalents: 17 ZIA and 1 ZPA
- 3 additional consolidated ASIM and ingestion-health workbooks
- 1 incident enrichment and per-entity approval playbook
- 1 Entra-protected child workflow exposing all 10 standard ZIA OAuth
  response operations
- Optional `ZscalerCribl_CL` table, DCE, DCR, source-specific ASIM parsers,
  and ASIM custom unifying parsers
- Cribl normalization contracts and post-deployment KQL readiness tests
- Bicep deployment and a redistributable Sentinel ARM package

The parity baseline is pinned to Azure-Sentinel commit
`cd455a8cecf3e5e983f9cd08191dca3d211c9fa1`. See
[`Content/content-parity.json`](Content/content-parity.json) for the
machine-readable coverage contract.

## Architecture

```text
Zscaler ZIA/ZPA
    -> Cribl parsing and canonical normalization
    -> Azure Monitor Logs Ingestion API
    -> ZscalerCribl_CL
    -> vimZscalerCribl* source parsers
    -> Im_*Custom custom unifying parsers
    -> Microsoft _Im_* built-in unifying parsers
    -> rules, hunts, workbooks, and response enrichment
```

Direct Zscaler data connectors are deliberately excluded. Cribl remains the
single ingestion path.

## Security model

- Both workflows use system-assigned managed identities. The incident
  workflow uses managed identity for Sentinel, Log
  Analytics, and Key Vault access.
- Zscaler OAuth values are read from Key Vault only after analyst approval.
- The reusable operation workflow disables SAS and requires a Microsoft Entra
  token with the deployment tenant, exact audience, and approved caller
  managed-identity object ID.
- Mutating operations have a second kill switch and explicit per-entity Teams
  approval.
- Teams connectors require one-time delegated authorization.
- Both workflows, the mutation kill switch, and the automation rule deploy
  disabled. Enable them only after connectors, Key Vault, Cribl, and controlled
  response tests pass.
- No credentials or customer-specific values belong in this repository.

## Data prerequisites

By default, deployment creates the canonical Logs Ingestion landing zone.
Provide the deployment outputs `criblLogsIngestionEndpoint`,
`criblDcrImmutableId`, and `criblStreamName` to the Cribl administrator.
Cribl must emit the fields documented in
[Cribl/README.md](Cribl/README.md). Run the KQL contract tests before enabling
content for production use.

## Deployment

### Deploy to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FCrisDea%2FSentinelCxD%2Fmain%2FZscalerViaCriblwithASIM%2FPackage%2FmainTemplate.json)

The portal prompts for the target resource group, existing Sentinel workspace,
and optional integration settings. Response workflows, Zscaler mutation, and
the automation rule remain disabled.

### Windows PowerShell 5.1

The deployment script uses the compiled ARM template and Azure CLI, so it does
not require PowerShell 7 or Bicep:

```powershell
.\scripts\Deploy-Pack.ps1 `
  -SubscriptionId '<subscription-id>' `
  -ResourceGroup '<sentinel-resource-group>' `
  -WorkspaceName '<sentinel-workspace>'
```

Add `-SentinelAutomationPrincipalId` and `-CriblPrincipalObjectId` when those
tenant identities are known. The script validates the deployment, blocks any
resource-level deletion shown by what-if, and then deploys.

### Microsoft Defender portal repository connection

1. In the Defender portal, open **Microsoft Sentinel** >
   **Content management** > **Repositories**.
2. Connect `CrisDea/SentinelCxD`, branch `main`, and install the
   **Azure-Sentinel** GitHub app when prompted.
3. Edit the generated `sentinel-deploy-*.yml` workflow so both its trigger path
   and deployment `directory` point to
   `ZscalerViaCriblwithASIM/RepositoryContent`.
4. Keep the repository-generated workflow as the deployment authority for that
   workspace.

The repository wrapper accepts the `workspace` parameter injected by Sentinel
Repositories and deploys the complete pack with safe defaults. See
[`RepositoryContent/README.md`](RepositoryContent/README.md).

Never place Zscaler credentials in a parameters file. Create the documented
Key Vault secrets through an approved secure channel after deployment.

## Customer-neutral distribution

The repository contains no tenant IDs, subscription IDs, workspace names,
resource-group names, user identities, customer domains, credentials, or
Zscaler secrets. Environment-specific values are deployment parameters only.

## Upstream content

Detection intent and Zscaler response semantics are adapted from the
Microsoft Sentinel community repository. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

MIT. See [LICENSE](LICENSE).
