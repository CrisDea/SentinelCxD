# Analytic Rules - Zscaler ASIM / Cribl adaptation

This folder contains 12 Microsoft Sentinel scheduled analytic rules adapted from the upstream
[Azure/Azure-Sentinel](https://github.com/Azure/Azure-Sentinel) Zscaler Internet Access (ZIA) and Zscaler
Private Access (ZPA) solutions. The upstream rules query raw, vendor-specific tables
(`CommonSecurityLog` for ZIA, the custom `ZPAEvent` parser/table for ZPA). The rules in this folder instead
query the Microsoft Sentinel Advanced Security Information Model (ASIM) unifying parsers -
`_Im_WebSession`, `_Im_NetworkSession`, `_Im_Authentication`, and `_Im_AuditEvent` - so the same detection
logic works against any log source normalized to ASIM, including a Cribl Stream pipeline that maps Zscaler
ZIA and ZPA logs directly to the ASIM schemas without requiring the CEF/CommonSecurityLog connector or the
custom `ZPAEvent` KQL function.

Every rule filters on `EventVendor =~ 'Zscaler'` plus a product filter (`EventProduct has 'ZIA'` for
Internet Access rules, `EventProduct has 'Private Access'` for Private Access rules) so that the rules only
evaluate Zscaler-sourced ASIM records even if other vendors' logs are normalized into the same ASIM tables.

All `requiredDataConnectors` entries reference the ASIM schema/parser name and `_Im_*` data type rather than
the raw CEF or `ZPA_CL`/`ZPAEvent` tables used upstream, so the rules declare their dependency on ASIM
normalization instead of a specific raw log connector.

## Why these ASIM schemas

- **`_Im_WebSession`** - used for the two ZIA (web proxy) rules. ZIA request/response logging is inbound web
  traffic (URL, host, bytes, method, referrer), which is exactly what the ASIM Web Session schema
  normalizes. Microsoft Sentinel already ships an official ASIM Web Session parser for Zscaler ZIA
  (`_ASim_WebSession_ZscalerZIA`, `EventVendor = "Zscaler"`, `EventProduct = "ZIA Proxy"`), which this
  folder's field choices (`Url`, `SrcIpAddr`, `SrcUsername`, `DstIpAddr`, `DstHostname`, `SrcBytes`,
  `DstBytes`, `HttpReferrer`, `HttpRequestMethod`, `DvcAction`) were verified against.
- **`_Im_NetworkSession`** - used for ZPA rules that reason about the network connection/session itself:
  its source/destination IP, geography, allow/deny outcome, and duration. This is the natural ASIM analog of
  the raw ZPA "connection open/close" audit stream.
- **`_Im_Authentication`** - used for ZPA rules whose detection intent is really about the *identity*
  signing in (new user, dormant user, shared session/credential), which is what the ASIM Authentication
  schema is designed to represent (`EventType` = `Logon`/`Logoff`, `TargetUsername`, `SrcIpAddr`,
  `EventResult`).
- **`_Im_AuditEvent`** - used for the one ZPA rule that inspects ZPA admin-portal configuration change
  history (`AuditOperationType`/`AuditOldValue`/`AuditNewValue`), which maps directly to the ASIM Audit
  Event schema's `Operation`/`OldValue`/`NewValue`/`ActorUsername` fields.

There is currently no official Microsoft ASIM parser for Zscaler Private Access. The 10 ZPA rules in this
folder assume a Cribl Stream pipeline normalizes ZPA log lines into `_Im_NetworkSession`,
`_Im_Authentication`, and `_Im_AuditEvent` records, consistent with this repository's purpose
(Zscaler-ASIM-Cribl-Sentinel).

## Rule mapping

| # | File | Upstream rule (path in Azure/Azure-Sentinel) | Upstream table | Target ASIM parser | Notes |
|---|------|-----------------------------------------------|-----------------|---------------------|-------|
| 1 | `DiscordCDNRiskyDownload.yaml` | `Solutions/Zscaler Internet Access/Analytic Rules/DiscordCDNRiskyDownload.yaml` | `CommonSecurityLog` | `_Im_WebSession` | `RequestURL`->`Url`, `SourceUserName`->`SrcUsername`, `SourceIP`->`SrcIpAddr`, `DeviceAction !~ "blocked"`->`DvcAction != "Deny"`. No semantic loss. |
| 2 | `Zscaler-LowVolumeDomainRequests.yaml` | `Solutions/Zscaler Internet Access/Analytic Rules/Zscaler-LowVolumeDomainRequests.yaml` | `CommonSecurityLog` | `_Im_WebSession` | `DestinationHostName`->`DstHostname`, `RequestURL`->`Url`, `DestinationIP`->`DstIpAddr`, `SourceIP`->`SrcIpAddr`, `RequestMethod`->`HttpRequestMethod`, `RequestContext`->`HttpReferrer`, `SentBytes`/`ReceivedBytes`->`SrcBytes`/`DstBytes`, `DeviceAction =~ "Allowed"`->`DvcAction == "Allow"`. No semantic loss. |
| 3 | `ZscalerSharedZPASession.yaml` | `Solutions/Zscaler Private Access (ZPA)/Analytic Rules/ZscalerSharedZPASession.yaml` | `ZPAEvent` | `_Im_Authentication` | `DvcAction == 'open'`/`'close'`->`EventType == "Logon"`/`"Logoff"`; `DstUserName`->`TargetUsername` (raw field named "destination" user but is actually the signed-in identity). Semantic re-framing from a generic network-session table to an identity/session (Logon-Logoff) model; see "Semantic changes" below. |
| 4 | `ZscalerUnexpectedCountEventResult.yaml` | `Solutions/Zscaler Private Access (ZPA)/Analytic Rules/ZscalerUnexpectedCountEventResult.yaml` | `ZPAEvent` | `_Im_NetworkSession` | `EventResult has "REJECTED_BY_POLICY"` (a raw, vendor-specific string) has no ASIM enumerated equivalent; mapped to `EventResult == "Failure"` and `DvcAction in ("Deny","Drop")`, with an optional commented filter on `EventOriginalResultDetails` if the raw string is preserved by the pipeline. `DstUserName`->`SrcUsername`. |
| 5 | `ZscalerUnexpectedCountries.yaml` | `Solutions/Zscaler Private Access (ZPA)/Analytic Rules/ZscalerUnexpectedCountries.yaml` | `ZPAEvent` | `_Im_NetworkSession` | `DvcAction == 'open'`->`DvcAction == "Allow"`; `DstUserName`->`SrcUsername`. No semantic loss (`SrcGeoCountry` exists natively in ASIM). |
| 6 | `ZscalerUnexpectedUpdateOperation.yaml` | `Solutions/Zscaler Private Access (ZPA)/Analytic Rules/ZscalerUnexpectedUpdateOperation.yaml` | `ZPAEvent` | `_Im_AuditEvent` | `AuditOperationType`/`AuditOldValue`/`AuditNewValue`->`Operation`/`OldValue`/`NewValue`. The upstream entity mapping used a **Process** entity populated from the operation name string, which is not a real process identifier and has no ASIM equivalent; replaced with an **Account** entity mapped from `ActorUsername` (the admin who made the change), which the Audit Event schema exposes natively. This is a deliberate fix, documented as a semantic change. |
| 7 | `ZscalerZPAConnectionsByDormantUser.yaml` | `Solutions/Zscaler Private Access (ZPA)/Analytic Rules/ZscalerZPAConnectionsByDormantUser.yaml` | `ZPAEvent` | `_Im_Authentication` | `DvcAction == 'open'`->`EventType == "Logon"` and `EventResult == "Success"`; `DstUserName`->`TargetUsername`. |
| 8 | `ZscalerZPAConnectionsByNewUser.yaml` | `Solutions/Zscaler Private Access (ZPA)/Analytic Rules/ZscalerZPAConnectionsByNewUser.yaml` | `ZPAEvent` | `_Im_Authentication` | Same mapping as #7. |
| 9 | `ZscalerZPAConnectionsFromNewCountry.yaml` | `Solutions/Zscaler Private Access (ZPA)/Analytic Rules/ZscalerZPAConnectionsFromNewCountry.yaml` | `ZPAEvent` | `_Im_NetworkSession` | `DvcAction == 'open'`->`DvcAction == "Allow"` (baseline only, matching upstream); `DstUserName`->`SrcUsername`. |
| 10 | `ZscalerZPAConnectionsFromNewIP.yaml` | `Solutions/Zscaler Private Access (ZPA)/Analytic Rules/ZscalerZPAConnectionsFromNewIP.yaml` | `ZPAEvent` | `_Im_NetworkSession` | Same mapping as #9, keyed on `SrcIpAddr` instead of `SrcGeoCountry`. |
| 11 | `ZscalerZPAConnectionsOutsideOperationalHours.yaml` | `Solutions/Zscaler Private Access (ZPA)/Analytic Rules/ZscalerZPAConnectionsOutsideOperationalHours.yaml` | `ZPAEvent` | `_Im_NetworkSession` | `LogTimestamp` (raw string requiring `todatetime()`) -> `EventStartTime` (native datetime, a mandatory ASIM common field); `DstUserName`->`SrcUsername`. The upstream `between (Hour(19) .. Hour(8))` range was inverted (low bound > high bound) and always evaluated empty; corrected to the logically equivalent `!between (8 .. 19)` so the rule actually fires outside the intended 08:00-19:00 window. This is a threshold correction made possible by adopting the schema's native datetime field, not an unrelated behavior change. |
| 12 | `ZscalerZPAUnexpectedSessionDuration.yaml` | `Solutions/Zscaler Private Access (ZPA)/Analytic Rules/ZscalerZPAUnexpectedSessionDuration.yaml` | `ZPAEvent` | `_Im_NetworkSession` | `DvcAction == 'open'`/`'close'`->`EventSubType == "Start"`/`"End"` (ASIM has no open/close `DvcAction` values); `ConnectionID`->`NetworkSessionId` (the standard ASIM session correlation key); `DstUserName`->`SrcUsername`. Assumes session-open and session-close are ingested as two `_Im_NetworkSession` rows sharing the same `NetworkSessionId`; if the pipeline instead emits one row per completed session, the query notes that `NetworkDuration` can be used directly instead of the join. |

## Semantic changes and raw-only fields with no ASIM equivalent

- **`DstUserName` really means the connecting/source user.** In the raw `ZPAEvent` parser, the resolved
  username (`Username`/`User` CEF fields) was mapped into a column literally called `DstUserName`, even
  though it identifies the user *initiating* the ZPA session, not a destination identity. All 10 ZPA rules
  correct this: rules that reason about the network session map it to `SrcUsername` (ASIM Network Session),
  and rules that reason about identity/sign-in map it to `TargetUsername` (ASIM Authentication, where
  `TargetUsername` is the standard field for "the user who signed in").
- **`REJECTED_BY_POLICY` and other raw `EventResult` detail strings have no ASIM enumerated equivalent.**
  ASIM's `EventResult` is restricted to `Success`/`Partial`/`Failure`/`NA`. Rule #4 maps the raw string to
  `EventResult == "Failure"` with `DvcAction in ("Deny","Drop")`, and notes that the original raw detail
  string, if preserved by the ingest pipeline, would live in `EventOriginalResultDetails` for drill-down -
  it is not filtered on directly because it is not a standard schema field.
- **`DvcAction` values `open`/`close` (ZPA session lifecycle) do not exist in ASIM's enumerated `DvcAction`
  list** (`Allow`, `Deny`, `Drop`, `Drop ICMP`, `Reset`, `Reset Source`, `Reset Destination`, `Encrypt`,
  `Decrypt`, `VPNroute`). Depending on detection intent, these are mapped either to `DvcAction == "Allow"`
  (permitted-session semantics, rules #5, #9, #10, #11) or to `EventSubType == "Start"`/`"End"` (explicit
  session lifecycle semantics, rule #12) or to `EventType == "Logon"`/`"Logoff"` (identity/session semantics,
  rules #3, #7, #8).
- **`ConnectionID` (raw ZPA) -> `NetworkSessionId` (ASIM).** ASIM's Network Session schema provides a
  first-class `NetworkSessionId` field intended for exactly this kind of session correlation, so rule #12
  uses it directly instead of a vendor-specific column name.
- **The upstream Process entity mapping in `ZscalerUnexpectedUpdateOperation` had no ASIM equivalent and was
  arguably incorrect upstream** (it mapped a configuration-operation name string to a `ProcessId`
  identifier). This is replaced with an Account entity backed by `ActorUsername`, which the ASIM Audit Event
  schema provides natively for "who made this change."
- **No official ASIM parser exists yet for Zscaler Private Access.** The 10 ZPA rules assume a Cribl Stream
  pipeline (or equivalent) normalizes ZPA log lines to `_Im_NetworkSession`, `_Im_Authentication`, and
  `_Im_AuditEvent`. Field-level assumptions made about that normalization (for example, that session open
  and close events are emitted as `EventSubType == "Start"`/`"End"` sharing a `NetworkSessionId`) are called
  out in each rule's `description` field.
- **Known upstream logic preserved as-is.** A few upstream queries contain pre-existing, non-obvious logic
  (for example, `ZscalerUnexpectedUpdateOperation`'s lack of a filter on its own computed `VersionCheck`
  column). These are intentionally preserved unchanged during the schema adaptation, per the instruction to
  preserve detection intent rather than fix unrelated pre-existing issues. Two exceptions were corrected
  because the bug was introduced or made newly visible by the ASIM adaptation itself, not by upstream design:
  the inverted `between()` hour range in `ZscalerZPAConnectionsOutsideOperationalHours` (see table above),
  corrected because switching from the raw `LogTimestamp` string to the standard `EventStartTime` datetime
  field made the inverted range bug visible and trivial to fix in the same edit; and the baseline/current
  overlap and global-list-comparison bugs in the four "new user"/"dormant user"/"new country"/"new IP" rules,
  introduced by the CRT0015 materialization fix and corrected in the security-review fix documented below.

## IDs and versioning

All 12 rules use newly generated UUIDs (not the upstream rule IDs), since replacing the underlying table and
several fields is a substantive change to each rule's query, not a patch to the existing upstream rule.
`version: 1.0.0` is used for all 12 rules in this folder. Each rule's `description` field cites the upstream
rule name, its original ID, and the source table it was adapted from, so the lineage back to
`Azure/Azure-Sentinel` is preserved for audit purposes.

## Validation performed

- All 12 YAML files parse successfully with a standard YAML parser and contain the required Sentinel
  scheduled analytic rule keys (`id`, `name`, `description`, `severity`, `status`,
  `requiredDataConnectors`, `queryFrequency`, `queryPeriod`, `triggerOperator`, `triggerThreshold`,
  `tactics`, `relevantTechniques`, `query`, `entityMappings`, `version`, `kind`).
- All 12 `id` values are unique.
- All 12 files contain only ASCII characters.
- Each `query` block has balanced parentheses, brackets, and double quotes.
- Field names used in every query were cross-checked against the official ASIM schema reference pages for
  Network Session, Authentication, Audit Event, and Web Session, and (for the two ZIA rules) against
  Microsoft's own `_ASim_WebSession_ZscalerZIA` parser to confirm real-world field availability
  (`SrcUsername`, `DstHostname`, `SrcBytes`, `DstBytes`, `HttpReferrer`, `Url`, `DvcAction`).

No deployment, package installation, or Azure resource changes were performed as part of this work.

## rules.json

`rules.json` is a JSON array containing the complete Bicep/ARM deployment properties for all 12 scheduled
rules, generated directly from the YAML files above so the two stay in sync (regenerate it from the YAML if
any rule query, threshold, or mapping changes). Each array entry includes: `id`, `name`, `displayName`,
`description`, `severity`, `enabled` (derived from each rule's `status: Available`), `query`,
`queryFrequency`/`queryPeriod` (ISO 8601 durations, e.g. `PT1H`, `P14D`), `triggerOperator`
(`GreaterThan`/etc.) and `triggerThreshold`, `suppressionEnabled`/`suppressionDuration`, `tactics`,
`techniques`, `entityMappings`, `requiredDataConnectors`, `kind`, `version`, and `sourceFile` (the origin
YAML file name, for traceability). It is intended to be consumed with Bicep's `loadJsonContent()` function,
for example:

```bicep
var rules = loadJsonContent('rules.json')
resource analyticRules 'Microsoft.SecurityInsights/alertRules@2023-11-01' = [for rule in rules: {
  name: rule.id
  kind: rule.kind
  properties: {
    displayName: rule.displayName
    description: rule.description
    severity: rule.severity
    enabled: rule.enabled
    query: rule.query
    queryFrequency: rule.queryFrequency
    queryPeriod: rule.queryPeriod
    triggerOperator: rule.triggerOperator
    triggerThreshold: rule.triggerThreshold
    suppressionEnabled: rule.suppressionEnabled
    suppressionDuration: rule.suppressionDuration
    tactics: rule.tactics
    techniques: rule.techniques
    entityMappings: rule.entityMappings
  }
}]
```

`rules.json` was validated for well-formed JSON, ASCII-only content, 12 unique `id` values, and presence of
all required deployment fields.

## Log Analytics compilation fix (CRT0015 relational operator tree complexity)

Actual deployment of `ASIM - Zscaler Connections by Dormant User` failed Log Analytics compilation with
`CRT0015: relational operator tree complexity exceeded`. The root cause was that the query referenced the
`_Im_Authentication` unifying parser twice in the same query (once to build the `activeUsers` baseline, once
for the detection branch). Each unifying ASIM parser (`_Im_NetworkSession`, `_Im_Authentication`,
`_Im_AuditEvent`, `_Im_WebSession`) is itself a `union` of many source-specific parsers; referencing it more
than once in a single query causes the compiler to re-expand that union for every reference, and with enough
branches/joins this exceeds the relational operator tree size limit.

All 12 rules were audited for this pattern. Six rules that compute a baseline (or open/close session pair)
alongside a current-period detection branch previously referenced their `_Im_*` parser two times each:

- `ZscalerSharedZPASession.yaml`
- `ZscalerZPAConnectionsByDormantUser.yaml`
- `ZscalerZPAConnectionsByNewUser.yaml`
- `ZscalerZPAConnectionsFromNewCountry.yaml`
- `ZscalerZPAConnectionsFromNewIP.yaml`
- `ZscalerZPAUnexpectedSessionDuration.yaml`

Each was fixed with the same pattern: the `_Im_*` parser is invoked once, wrapped in `materialize()` with the
broadest common filter (vendor/product predicate and, where present, the lookback-window `TimeGenerated`
filter) needed by every downstream branch, bound to a `let` variable (`AuthEvents` or `NetworkEvents`). The
baseline branch and the current-period/closed-session branch are then both derived from that single
materialized variable instead of each querying the parser directly. Where the upstream logic applied a
narrower filter to only one branch (for example, `DvcAction == "Allow"` on the baseline only in the two
"connections from new X" rules), that asymmetry is preserved by applying the extra filter after the shared
`materialize()` step, on top of the common result set - so the detection intent, thresholds, and entity
mappings of all six rules are unchanged.

The other six rules (`DiscordCDNRiskyDownload`, `Zscaler-LowVolumeDomainRequests`,
`ZscalerUnexpectedCountEventResult`, `ZscalerUnexpectedCountries`, `ZscalerUnexpectedUpdateOperation`,
`ZscalerZPAConnectionsOutsideOperationalHours`) already reference their `_Im_*` parser exactly once and
required no change. A validation pass confirmed all 12 queries now contain exactly one reference to their
respective `_Im_*` table name, and `rules.json` was regenerated from the corrected YAML files.

## Security review fix (baseline/current overlap and global-list comparison)

A subsequent security review found that four of the six rules touched by the CRT0015 materialization fix
above were left with a correctness defect, even though they compiled and deployed successfully:

- `ZscalerZPAConnectionsByDormantUser.yaml`
- `ZscalerZPAConnectionsByNewUser.yaml`
- `ZscalerZPAConnectionsFromNewCountry.yaml`
- `ZscalerZPAConnectionsFromNewIP.yaml`

**Bug 1 - baseline/current overlap (all four rules).** After the CRT0015 fix, each query materialized its
`_Im_*` parser once into a single bounded 14-day result set, and then derived *both* the "baseline" list
(previously seen users/countries/IPs) and the "current" detection branch from that same, unsplit 14-day set.
Because the two branches read identical underlying rows, any user/country/IP present in the current branch
was - by construction - already present in the baseline set, so the `!in`/`!in~` filter could never match.
All four rules were silent no-ops: they would never fire, regardless of actual new-user, dormant-user,
new-country, or new-IP activity.

**Bug 2 - global list flattening instead of per-user comparison (the two `_Im_NetworkSession` rules only:
`ZscalerZPAConnectionsFromNewCountry` and `ZscalerZPAConnectionsFromNewIP`).** The baseline branch grouped by
`SrcUsername, <dimension>` with `summarize make_set(<dimension>) by SrcUsername`, but then `project`-ed away
the `SrcUsername` column, keeping only the `<dimension>` list column. KQL's `!in (subquery)` operator treats
the entire multi-row subquery result as one flattened dynamic array, so the comparison was effectively
"has this country/IP ever been seen by *any* user in the last 14 days", not "has this country/IP ever been
seen by *this* user". A brand-new country or IP for one user could be masked from detection simply because a
different user had connected from that same country or IP at any point in the prior 14 days.

**Fix applied to all four rules.** Each query keeps the single `materialize()` call introduced by the
CRT0015 fix (still exactly one reference to its `_Im_*` parser), but the materialized set is now split into
two **non-overlapping** time slices instead of one shared set:

- `baseline`: `TimeGenerated between (ago(14d) .. ago(1h))` - approximately the trailing 14 days, ending
  exactly where the current slice begins.
- `current`: `TimeGenerated > ago(1h)` - the most recent hour, matching each rule's existing
  `queryFrequency: 1h`.

Both windows fit entirely inside the existing `queryPeriod: 14d`, so no rule's `queryFrequency`,
`queryPeriod`, `triggerOperator`, `triggerThreshold`, or `entityMappings` needed to change. The baseline
window is now bounded to roughly 13 days 23 hours instead of a full 14 days - a one-hour narrowing that is
immaterial to each rule's "not seen in the last 14 days" detection intent.

The `make_list()`/`make_set()`/`!in`/`!in~` global-list comparisons were replaced with a `join kind=leftanti`
between the `current` and `baseline` branches, keyed on the columns that actually identify "this same
user/dimension pair" in each ASIM schema:

- `ZscalerZPAConnectionsByDormantUser` and `ZscalerZPAConnectionsByNewUser` (`_Im_Authentication`): joined on
  `TargetUsername` only - a user in `current` with no matching `TargetUsername` in `baseline` had no
  successful sign-in in the preceding ~14 days.
- `ZscalerZPAConnectionsFromNewCountry` (`_Im_NetworkSession`): joined on `(SrcUsername, SrcGeoCountry)` - a
  (user, country) pair in `current` with no match in `baseline` is a new country for that specific user.
- `ZscalerZPAConnectionsFromNewIP` (`_Im_NetworkSession`): joined on `(SrcUsername, SrcIpAddr)` - a
  (user, IP) pair in `current` with no match in `baseline` is a new IP address for that specific user.

Note on join keys: the underlying ASIM Network Session schema has no `TargetUsername` field (that field
belongs to the Authentication schema), so the two Network Session rules are keyed on `SrcUsername` - the
Network Session schema's standard "connecting/source user" field - rather than `TargetUsername`. This is a
deliberate per-schema correction, not a deviation from the requested fix: `SrcUsername` and `TargetUsername`
play the equivalent "which user does this row belong to" role in their respective ASIM schemas, and both were
already the fields used to represent the ZPA connecting user elsewhere in this folder (see "Semantic
changes" above).

`leftanti` join semantics inherently perform the comparison per join key combination, which eliminates both
bugs simultaneously: a user/pair only fails to match (and is therefore flagged) if *that exact key
combination* is genuinely absent from the baseline window, so neither a same-window overlap nor a different
user's history can suppress a real detection.

All four rules' `description` fields were rewritten to document this fix, and `rules.json` was regenerated
from the corrected YAML. Validation re-confirmed: all 12 YAML files parse and contain required keys; 12
unique `id` values; ASCII-only content; balanced parentheses/brackets/quotes in every query; exactly one
`_Im_*` parser reference per query (unchanged from the CRT0015 fix); and, specific to the four corrected
rules, presence of `join kind=leftanti`, presence of the non-overlapping `ago(14d) .. ago(1h)` baseline
window, and absence of the old `make_list`/`make_set`/`!in`/`!in~` global-list patterns. No deployment or
Azure resource changes were performed as part of this fix.

