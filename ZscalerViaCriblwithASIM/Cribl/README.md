# Cribl ingestion boundary

Cribl is the only supported ingestion path. Do not enable the Zscaler direct
connectors. Cribl receives ZIA Cloud NSS and ZPA records, classifies them with
`family-mapping.json`, applies `field-aliases.json`, and posts canonical JSON
arrays to the Azure Monitor Logs Ingestion API.

## Cribl pipeline order

1. Parse the source record and classify one of the 15 ZIA families or a ZPA
   `Access`, `Authentication`, or `Administration` subfamily.
2. Set `ZscalerFamily`, `ZscalerSubfamily`, and `AsimSchemas` exactly as listed
   in `family-mapping.json`.
3. Coalesce aliases into the typed canonical fields. Set `EventVendor` to
   `Zscaler`, generate a stable `EventOriginalUid`, and reject records missing
   the fields required by `asim-field-contract.json`.
4. Put every unconsumed source field and each label/value extension pair in
   `AdditionalFields`. Retain the parsed source object in `RawEvent` only when
   local data-handling policy permits it.
5. Send a JSON array to the endpoint, DCR immutable ID, and stream returned by
   `infra/modules/cribl-asim-ingestion.bicep`. Route HTTP failures and rejected
   records to an explicitly monitored quarantine destination.

The HTTP target is:

```text
{logsIngestionEndpoint}/dataCollectionRules/{dcrImmutableId}/streams/{streamName}?api-version=2023-01-01
```

Use OAuth client credentials or a workload identity for resource
`https://monitor.azure.com/.default`; never store credentials in this pack.
The identity needs **Monitoring Metrics Publisher** on the DCR.

Run `validation/*.kql` after parser deployment. The source-specific parsers are
called by the workspace `Im_*Custom` functions, which the built-in `_Im_*`
functions discover automatically.
