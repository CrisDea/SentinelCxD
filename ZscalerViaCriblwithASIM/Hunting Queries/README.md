# Zscaler Private Access ASIM hunting queries

This directory maps all 10 standard ZPA hunts from Azure-Sentinel commit
`cd455a8cecf3e5e983f9cd08191dca3d211c9fa1` to the ASIM Network Session
schema. Every hunt invokes `_Im_NetworkSession` and applies both
`EventVendor =~ "Zscaler"` and `EventProduct has "Private Access"`.

## Exact upstream mapping

| Upstream file | Upstream title | ASIM file | Principal field mapping |
|---|---|---|---|
| `ZscalerAbnormalTotalBytesSize.yaml` | Zscaler - Abnormal total bytes size | same | `ZENTotalBytesRxConnector` → `NetworkBytes`; `DstUserName` → `SrcUsername` |
| `ZscalerApplicationByUsers.yaml` | Zscaler - Applications using by accounts | same | `Application` → `AdditionalFields.Application` (fallback `DstFQDN`); `DstUserName` → `SrcUsername` |
| `ZscalerConnectionCloseReason.yaml` | Zscaler - Connection close reasons | same | raw `close` → `EventSubType == "End"`; raw reason → `EventOriginalResultDetails` (fallback `AdditionalFields.ConnectionCloseReason`) |
| `ZscalerIPsByPorts.yaml` | Zscaler - Destination ports by IP | same | `DstPortNumber`/`DstIpAddr` → same ASIM fields |
| `ZscalerSourceLocation.yaml` | Zscaler - Users by source location countries | same | `SrcGeoCountry` → `SrcGeoCountry`; `DstUserName` → `SrcUsername` |
| `ZscalerTopConnectors.yaml` | Zscaler - Top connectors | same | `Connector` → `AdditionalFields.Connector`; `BytesRxInterface` → `NetworkBytes` |
| `ZscalerTopSourceIP.yaml` | Zscaler - Top source IP | same | raw `open` → `DvcAction == "Allow"`; `SrcIpAddr` → `SrcIpAddr` |
| `ZscalerUrlhostname.yaml` | Zscaler - Rare urlhostname requests | same | `UrlHostname` → `DstFQDN` |
| `ZscalerUserAccessGroups.yaml` | Zscaler - Users access groups | same | `AppGroup` → `AdditionalFields.AppGroup`; `DstUserName` → `SrcUsername` |
| `ZscalerUserServerErrors.yaml` | Zscaler - Server error by user | same | raw result → `EventResult == "Failure"` plus `EventOriginalResultDetails`; `DstUserName` → `SrcUsername` |

Original IDs, severities, ATT&CK tactics/techniques, top-20 limits, the 1000×
byte threshold, and entity types are preserved. The upstream hunts define no
fixed lookback; Sentinel's hunting time picker continues to bound each query.

## Parser and pipeline contract

- Required parser: `_Im_NetworkSession` (`ASimNetworkSession` connector
  dependency).
- Required common fields: `TimeGenerated`, `EventVendor`, `EventProduct`,
  `EventResult`, `SrcIpAddr`, and `DstIpAddr`.
- Relevant normalized optional fields: `SrcUsername`, `SrcGeoCountry`,
  `DstFQDN`, `DstPortNumber`, `DvcAction`, `EventSubType`,
  `EventOriginalResultDetails`, and `NetworkBytes`.
- Vendor-specific `AdditionalFields` keys:
  - `AppGroup`
  - `Application`
  - `Connector`
  - `ConnectionCloseReason`

`AdditionalFields` is used only where ZPA has no equivalent standard ASIM
dimension. Pipelines should preserve the exact key spelling above.

## Semantic limitations

- A parser that does not retain the raw server error in
  `EventOriginalResultDetails` cannot distinguish the specific
  `AST_MT_SETUP_ERR_OPEN_SERVER_ERROR` condition from other failures.
- Close-reason fidelity requires `EventOriginalResultDetails` or the documented
  `ConnectionCloseReason` fallback key.
- `DstFQDN` is a hostname rather than a full URL, but it is the closest standard
  Network Session representation of upstream `UrlHostname`; the URL entity
  mapping is retained for parity.
- ZPA App Connector is not a standard ASIM entity. The upstream Process mapping
  is retained, although the connector identifier is not an operating-system
  process ID.
- User/country, application/user, and port/IP hunts return scalar entity rows
  rather than mapping a dynamic array. This preserves the investigative intent
  while making entity pivots usable.

`hunting-queries.json` is the machine-readable Bicep integration manifest. It
contains exactly one entry for each YAML file and embeds each hunt's complete
deployment payload (`id`, resource/display names, description, query, tactics,
techniques, entity mappings, version, category, and source file).
