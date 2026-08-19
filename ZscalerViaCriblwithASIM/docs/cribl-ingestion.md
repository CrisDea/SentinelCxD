# Cribl to Microsoft Sentinel ingestion

## Deployment choices

Deploy `infra/modules/cribl-asim-ingestion.bicep` against the resource group
containing the existing Microsoft Sentinel workspace.

- With `createIngestionLandingZone=true`, the module creates
  `ZscalerCribl_CL`, one DCE, one direct DCR, twelve ASIM functions, and
  optionally assigns the Cribl identity.
- With `createIngestionLandingZone=false`, the table/DCE/DCR are not created.
  Supply `existingLogsIngestionEndpoint`, `existingDcrImmutableId`, and
  `existingStreamName`. The existing route must implement the exact
  `ZscalerCribl_CL` schema. Parser functions are still deployed.

Pass the module outputs `logsIngestionEndpoint`, `dcrImmutableId`, and
`streamName` to the Cribl administrator. Do not pass a DCR resource name in
place of its immutable ID.

## Authentication and network prerequisites

The Cribl workload identity or Entra application requests a token for
`https://monitor.azure.com/.default` and needs the **Monitoring Metrics
Publisher** role scoped to the DCR. The deployment principal separately needs
permission to create the resources and role assignment. No credential belongs
in source control.

The default DCE allows public access over TLS. Set `publicNetworkAccess` to
`Disabled` only after private DNS, Azure Monitor Private Link Scope, and Cribl
network reachability are in place.

## ASIM discovery boundary

The module deploys parameterized `vimZscalerCribl*` source parsers and the
exact pinned `Im_<Schema>Custom` filtering signatures for AuditEvent,
Authentication, Dns, FileEvent, NetworkSession, and WebSession. Microsoft
Sentinel built-in `_Im_*` parsers automatically include these workspace custom
unifying parsers. Analytics, hunts, and workbooks therefore continue to query
only `_Im_*`; they never query `ZscalerCribl_CL`.

The signatures are pinned to Azure/Azure-Sentinel commit
`cd455a8cecf3e5e983f9cd08191dca3d211c9fa1`. Reconcile upstream signature
changes before changing that pin.

## Operational verification

Run the KQL files in `Cribl/validation` in order:

1. canonical-table family routing;
2. source, custom-unifying, and built-in parser compilation;
3. every family-to-schema route through `_Im_*`;
4. mandatory-field completeness;
5. `AdditionalFields` key preservation.

Missing families are expected before their Cribl inputs are enabled. Parser
compile errors, unexpected routes, incomplete mandatory fields, or lost
`AdditionalFields` keys must block content enablement.
