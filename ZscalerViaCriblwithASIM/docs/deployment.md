# Deployment guide

## Prerequisites

- Owner or equivalent deployment and role-assignment permissions.
- An existing Microsoft Sentinel workspace.
- Bicep CLI 0.46 or later.
- Zscaler OneAPI OAuth client credentials.
- A Microsoft Teams identity permitted to authorize the managed connector.
- A Cribl workload identity or Entra application for Logs Ingestion API.
- Cribl routing that satisfies `Cribl/asim-field-contract.json`.

## Validate locally

```powershell
.\scripts\Validate-Pack.ps1 `
  -SubscriptionId '<subscription-id>' `
  -ResourceGroup '<resource-group>' `
  -WorkspaceName '<workspace-name>'
```

The validation script checks the pinned parity counts, JSON, forbidden raw
table references, workbook and hunting manifests, Logic App request
authorization, Bicep, all source-content KQL, and post-deployment parser
contracts.

Before the ingestion resources exist, add `-SkipIngestionKql`. Do not use that
switch after deployment.

## Preview Azure changes

```powershell
az deployment group what-if `
  --subscription '<subscription-id>' `
  --resource-group '<resource-group>' `
  --template-file .\infra\main.bicep `
  --parameters .\infra\main.parameters.json
```

Review every create or modify operation. The pack must not delete or replace
existing vendor content.

## Deploy

```powershell
.\scripts\Deploy-Pack.ps1 `
  -SubscriptionId '<subscription-id>' `
  -ResourceGroup '<resource-group>' `
  -ParametersFile .\infra\main.parameters.json
```

## Configure secrets securely

Use the Azure portal or an approved secret-management process to create:

- `zscaler-oneapi-client-id`
- `zscaler-oneapi-client-secret`
- `zscaler-oneapi-token-url`

Do not put secret values in `main.parameters.json`.

## Configure Cribl

Read these deployment outputs:

- `criblLogsIngestionEndpoint`
- `criblDcrImmutableId`
- `criblStreamName`

Configure the Cribl Azure Monitor Logs destination as documented in
[`cribl-ingestion.md`](cribl-ingestion.md). The Cribl identity needs
**Monitoring Metrics Publisher** on the DCR. If `criblPrincipalObjectId` was
provided during deployment, the pack creates this assignment.

## Authorize and test

1. Authorize both generated Teams connections.
2. Keep both workflows, mutation, and the automation rule disabled.
3. Send test records through Cribl and run all five `Cribl/validation` queries.
4. Confirm all six `_Im_*` parsers return the test records.
5. Enable only the reusable workflow and test authentication and lookup.
6. Test a mutation against a non-production Zscaler category with per-entity
   approval.
7. Enable the incident workflow and invoke a controlled test incident.
8. Confirm Zscaler activation and the post-success Sentinel marker.
9. Enable the automation rule only after every safety test passes.

## Build the redistribution ZIP

```powershell
.\scripts\Build-Pack.ps1
```

The output is written to `dist/`.
