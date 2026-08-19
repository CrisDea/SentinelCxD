# Zscaler ASIM Workbooks

This folder contains consolidated Azure Monitor Workbook gallery templates
and specialized parity workbooks for Zscaler Internet Access (ZIA) and
Zscaler Private Access (ZPA). Content is delivered to Microsoft Sentinel
through Cribl and normalized with the Advanced Security Information Model
(ASIM).

- `_Im_WebSession`
- `_Im_Dns`
- `_Im_NetworkSession`
- `_Im_Authentication`
- `_Im_AuditEvent`

All source-telemetry queries filter on `EventVendor == 'Zscaler'` and use
ASIM fields. The ZPA **Latest Alerts** panel preserves the upstream
Sentinel-derived `SecurityAlert` query with a precise Zscaler/ZPA filter.
No workbook queries `CommonSecurityLog`, `ZPAEvent`, or any Cribl-specific table, so the dashboards keep working
regardless of how the upstream Zscaler connector or Cribl pipeline is
configured, as long as it emits ASIM-normalized events.

## Files

| File | Purpose | ASIM parsers used |
|------|---------|--------------------|
| `ZscalerASIMOverview.json` | Landing page: cross-parser KPI tiles, Cribl/ASIM ingestion health (last-event and staleness per parser), volume trend, and top entities across all Zscaler data. | `_Im_WebSession`, `_Im_Dns`, `_Im_NetworkSession`, `_Im_Authentication`, `_Im_AuditEvent` |
| `ZscalerZIAWebDns.json` | ZIA web proxy activity (requests, blocks, domains, categories, users, status codes, user agents) and DNS activity (queries, failures, top domains/types). | `_Im_WebSession`, `_Im_Dns` |
| `ZscalerZIANetwork.json` | ZIA firewall/tunnel network session activity: allow/deny trends, protocol and direction mix, denied sessions, top talkers, and bytes transferred. | `_Im_NetworkSession` |
| `ZscalerZPAAccess.json` | Dedicated panel-for-panel equivalent of the standard ZPA workbook pinned at Azure-Sentinel commit `cd455a8cecf3e5e983f9cd08191dca3d211c9fa1`; source telemetry uses ASIM and Latest Alerts uses Sentinel-derived `SecurityAlert`. See `zpa-workbook-parity.json`. | `_Im_NetworkSession`; `SecurityAlert` exception |

## Standard ZIA workbook parity catalog

The 17 specialized ZIA workbooks reproduce all 81 query panels from the
standard Azure-Sentinel ZIA catalog at commit
`cd455a8cecf3e5e983f9cd08191dca3d211c9fa1`. The machine-readable
[`zia-workbook-parity.json`](zia-workbook-parity.json) records source
lineage, panel counts, parser dependencies, required `AdditionalFields` keys,
and mapping status.

| Upstream workbook | ASIM-native workbook | Panels | Parser |
|---|---|---:|---|
| `NSSAuditLogs.json` | `ZIA-Audit.json` | 3 | `_Im_AuditEvent` |
| `NSSCASBActivityLogs.json` | `ZIA-CASB-Activity.json` | 3 | `_Im_AuditEvent` |
| `NSSCASBCloudStorageLogs.json` | `ZIA-CASB-Cloud-Storage.json` | 3 | `_Im_FileEvent` |
| `NSSCASBCollabLogs.json` | `ZIA-CASB-Collaboration.json` | 3 | `_Im_AuditEvent` |
| `NSSCASBCRMLogs.json` | `ZIA-CASB-CRM.json` | 3 | `_Im_AuditEvent` |
| `NSSCASBEmail.json` | `ZIA-CASB-Email.json` | 3 | `_Im_FileEvent` |
| `NSSCASBFileSharingLogs.json` | `ZIA-CASB-File-Sharing.json` | 3 | `_Im_FileEvent` |
| `NSSCASBITSMLogs.json` | `ZIA-CASB-ITSM.json` | 3 | `_Im_AuditEvent` |
| `NSSCASBRepoLogs.json` | `ZIA-CASB-Repository.json` | 3 | `_Im_FileEvent` |
| `NSSDNSLogs.json` | `ZIA-DNS.json` | 3 | `_Im_Dns` |
| `NSSEmailDLPLogs.json` | `ZIA-Email-DLP.json` | 3 | `_Im_FileEvent` |
| `NSSEndpointDLPLogs.json` | `ZIA-Endpoint-DLP.json` | 3 | `_Im_FileEvent` |
| `NSSFWLogs.json` | `ZIA-Firewall.json` | 9 | `_Im_NetworkSession` |
| `NSSTunnelLogs.json` | `ZIA-Tunnel.json` | 3 | `_Im_NetworkSession` |
| `NSSWebLogsOffice365.json` | `ZIA-Office365.json` | 4 | `_Im_WebSession` |
| `NSSWebLogsOverview.json` | `ZIA-Web-Overview.json` | 13 | `_Im_WebSession` |
| `NSSWebLogsThreats.json` | `ZIA-Web-Threats.json` | 16 | `_Im_WebSession` |

Existing chart types, table formatting, widths, section headings, and
click-to-filter exports are retained where present. Each specialized workbook
adds stable Time Range and Workspace parameters and collision-safe,
deterministic item names.

### ZIA vendor extension mapping

Standard concepts use normalized ASIM fields. Where Zscaler has no normalized
field, the Cribl ASIM contract must populate these case-sensitive
`AdditionalFields` keys:

- Routing: `LogType`
- CASB: `Application`, `Identifier`, `Owner`
- DLP: `DlpRule`, `DlpDictionary`, `AttachmentFileType`, `EventClassId`
- Firewall/tunnel: `Location`, `Action`, `EventClassId`
- Web/threat: `Application`, `Location`, `DeviceModel`, `ThreatCategory`,
  `Action`, `RiskScore`, `FileType`, `MalwareCategory`, `UrlClass`,
  `SandboxCategory`

Queries read extension values with `tostring()` or `todouble()` and filter
`EventVendor =~ 'Zscaler'`, `EventProduct has 'ZIA'`, and the expected
`LogType`.

## Common structure

Every workbook includes:

- A **Time Range** parameter (default 24 hours, selectable from 1 hour to
  30 days) used by every query via the `{TimeRange}` macro.
- A **Workspace** parameter (Azure Resource Graph picker, multi-select)
  bound to `Microsoft.OperationalInsights/workspaces`, so the same template
  can be deployed and pointed at any Sentinel-enabled Log Analytics
  workspace without editing the JSON. Queries reference the selection via
  `crossComponentResources: ["{Workspaces}"]`.
- KPI tiles, at least one trend chart, and top-entity tables, following
  standard Microsoft Sentinel workbook conventions (`type: 3` KQL items
  with `tiles`, `timechart`, `table`, and `piechart` visualizations).

The `serializedData` for each workbook is valid, parameterized JSON
conforming to the Azure Monitor Workbook schema
(`https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json`)
and is ready to be embedded in a `Microsoft.Insights/workbooks` ARM/Bicep
resource (for example, by setting the resource's `sourceId` to the target
workspace and its `serializedData` to the contents of one of these files).
No deployment has been performed as part of this change.

## Coverage notes

- **ZIA web/proxy:** requests, block/allow outcome, domains, threat
  category, users, source IP, HTTP status code, and user agent -- all from
  `_Im_WebSession`.
- **ZIA DNS:** query volume, failures/NXDOMAIN-style results, top queried
  domains, query types, and clients with the most failures -- all from
  `_Im_Dns`.
- **ZIA network/firewall/tunnel:** session volume, allow/deny trend,
  protocol and direction mix, denied destinations, top talkers, and bytes
  transferred -- all from `_Im_NetworkSession`.
- **ZPA workbook parity:** nine normalized Network Session panels map one-to-one
  to the standard ZPA workbook's countries, connection status, event trend,
  source IP, close reason, hostname, per-user traffic, new-IP, and latest-signal
  surfaces. Exact field mappings and conditional limitations are recorded in
  `zpa-workbook-parity.json`.
- **Ingestion health:** per-parser last-event timestamp, minutes since last
  event, and a healthy/delayed/stale status, so gaps in the Cribl-to-ASIM
  pipeline are visible on the overview workbook.

## Specialized ZIA parity limitations

No upstream ZIA query panel is intentionally omitted. Vendor-only dimensions
remain empty if the Cribl parser does not populate the documented extension
keys. Hierarchical protocol/method and country/activity panels preserve their
click-through rows and regenerate trend arrays from normalized event time.

## Deployment notes

- These files are the workbook template content only; they are not wrapped
  in an ARM/Bicep resource definition here. See the repository's `infra/`
  and `Package/` folders (when present) for how these JSON files are
  embedded into `Microsoft.Insights/workbooks` resources.
- No customer-specific identifiers, secrets, or environment-specific
  resource IDs are included. The Workspace parameter must be selected (or
  supplied by the deployment) at workbook-open or deployment time.
- Nothing in this folder has been deployed to any Azure subscription or
  workspace.
