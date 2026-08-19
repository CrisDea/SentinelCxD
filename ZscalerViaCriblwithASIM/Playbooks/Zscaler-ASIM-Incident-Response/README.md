# Zscaler ASIM Incident Response

Microsoft Sentinel incident-triggered **Consumption Logic App (playbook)** that:

1. Extracts IP and URL entities from the triggering incident and builds a deduplicated candidate list of `{Type, Value}` pairs.
2. Queries ASIM-normalized tables (`_Im_WebSession`, `_Im_NetworkSession`, `_Im_Dns`) in the target Log Analytics workspace via the **Log Analytics Query REST API**, authenticating with the playbook's **system-assigned managed identity** (no keys or connection strings).
3. Adds an enrichment comment to the incident.
4. **Requests explicit, per-entity analyst approval**: for each candidate entity individually, posts a **Microsoft Teams adaptive card** showing that entity's exact type and value (with an explicit caution that IP entities may be a source, client, internal, or victim IP rather than a confirmed malicious host) and **waits for that one entity's Approve/Reject decision** (bounded by a configurable timeout) before moving to the next candidate. No entity is ever bulk-approved.
5. Collects only the individually-approved values. **If none were approved**, comments the outcome and ends the run without contacting Key Vault or Zscaler and without writing the idempotency marker.
6. **Only for entities that were individually approved**, retrieves the Zscaler OneAPI OAuth2 **client ID, client secret, and token URL from Azure Key Vault** via managed identity, requests an OAuth2 token, and blocks the approved IPs/URLs in Zscaler Internet Access (ZIA) using the upstream ZIA OAuth2 "add to URL category" + "activate" semantics.
7. Activates the ZIA configuration change **once** (a single batched call over only the approved values, not a per-entity activation loop).
8. Comments the outcome back on the incident at every terminal branch (duplicate/no entities/no entity approved/success/failure).

The workflow is **deployed in a `Disabled` state by default** and must not be enabled until the prerequisites below are completed. **This directory does not create or modify RBAC role assignments or Sentinel automation rules** — those are owned by the surrounding infrastructure deployment.

## Files

| File | Purpose |
| --- | --- |
| `azuredeploy.json` | ARM template for the Logic App workflow and its two API connections (Microsoft Sentinel, Microsoft Teams). |
| `README.md` | This document. |

The shared sibling workflow [`../Zscaler-ZIA-Operation`](../Zscaler-ZIA-Operation) securely exposes the complete ten-operation upstream ZIA OAuth2 surface. The machine-readable mapping is [`../playbook-parity.json`](../playbook-parity.json). Parent infrastructure may migrate this orchestrator's ZIA block step to the child workflow one entity at a time; until then, this existing block path remains the hardened incident implementation and its approval and post-activation marker controls must be preserved.

## Architecture / hardening notes

- **Secure inputs/outputs**: supported HTTP actions that touch a Key Vault secret, the OAuth2 access token, or the Zscaler block/activate calls set `runtimeConfiguration.secureData.properties: ["inputs","outputs"]`. The token is never persisted in a workflow variable; secured Zscaler calls reference it directly from the secured OAuth response.
- **Null guards**: every reference to a trigger property, HTTP response body, or array uses `coalesce(...)`/`?[...]` safe-dereference so a missing field degrades gracefully instead of failing the run.
- **Explicit, per-entity approval (not bulk)**: candidate IP and URL entities are deduplicated into a `{Type, Value}` list (`AllCandidates`), and `For_Each_Candidate_Request_Approval` iterates that list **sequentially** (`runtimeConfiguration.concurrency.repetitions: 1`), posting one Teams adaptive card per candidate and waiting for that entity's own Approve/Reject decision before moving to the next. Only entities that receive an explicit "Approve" on their own card are appended to `ApprovedValues`/`ApprovedEntitySummaryLines`; a reject or a per-entity approval timeout appends to `RejectedEntitySummaryLines` instead and that value is never sent to Zscaler. This directly prevents a rule that maps SourceIP/client/victim/internal entities onto the incident from being bulk-approved and blocked along with genuinely malicious entities. Each adaptive card explicitly states the entity's exact type and value and (for IP entities) a caution that the IP may be a source, client, internal, or victim address rather than a confirmed malicious host. Sequential iteration is also required for correctness, since Logic Apps variable mutations (`AppendToArrayVariable`) are not safe to run from parallel loop iterations.
- **Bounded concurrency**: the per-candidate approval loop above is bounded to one iteration at a time (`repetitions: 1`). The trigger itself sets `runtimeConfiguration.concurrency.runs: 1` and `maximumWaitingRuns: 1`, so at most one workflow run is active at a time (with at most one more queued) as a non-persistent, in-flight guard against concurrent/duplicate runs racing each other before either has written the idempotency marker. **Trade-off**: this serializes *all* run instances of this playbook, not just duplicates of the same incident — a long-pending Teams approval on one incident can delay the start of processing for an unrelated incident until it completes, times out, or is rejected. Operators needing higher throughput can raise `runs`/`maximumWaitingRuns` after deployment (Logic App designer > trigger > Settings, or by redeploying with a higher value); this is a deliberate, documented trade-off favoring dedup safety over throughput for a security-block action.
- **Exponential retries**: every outbound HTTP call (Log Analytics query, Key Vault GETs, OAuth2 token request, Zscaler add/activate) uses an `exponential` retry policy (4 attempts, 5s–1h backoff).
- **Explicit timeouts**: every outbound HTTP call sets `limit.timeout`; each per-entity Teams approval wait uses the configurable `ApprovalTimeout` parameter (default `PT8H`), applied independently to every candidate's own card.
- **Idempotency / dedup**: at the start of the run, the workflow checks the incident's labels for a `ZscalerBlockApplied-<category>` marker and, if present, comments "duplicate, skipping" and ends immediately without doing any work. That same marker is written back onto the incident **only after the Zscaler block has been successfully added and activated for the approved entities** (the true success path, alongside the human-readable `ZscalerBlockCompleted` tag) — never before or during the per-entity approval loop. This means a run where every candidate is rejected or times out, or that fails partway through Zscaler activation, leaves no marker behind, so a legitimate later retry on the same incident is not blocked; only a run that has actually completed the block is treated as a duplicate going forward.
- **Non-2xx handling**: every HTTP call's status code is checked explicitly (`If` actions comparing `statusCode`) before its result is trusted; failures post a descriptive comment to the incident and terminate the run with `Failed` status rather than continuing silently.
- **No secrets in the template**: the Zscaler OAuth2 client ID, client secret, and token URL are never stored as template parameters, default values, or variables — they are read from Key Vault at runtime via managed identity. No customer-identifying values (tenant names, workspace names, resource groups) are hardcoded or used as defaults.

## Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `PlaybookName` | `Zscaler-ASIM-Incident-Response` | Name of the Logic App resource. |
| `SentinelConnectionName` | `azuresentinel-zscaler-asim-response` | Name of the Microsoft Sentinel API connection (managed identity auth). |
| `TeamsConnectionName` | `teams-zscaler-asim-response` | Name of the Microsoft Teams API connection (requires one-time manual authorization; see below). |
| `WorkflowState` | `Disabled` | `Disabled` or `Enabled`. Leave `Disabled` until all prerequisites are complete. |
| `LogAnalyticsWorkspaceResourceId` | *(required, no default)* | Full ARM resource ID of the target Log Analytics workspace, e.g. `/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<name>`. The template resolves this to the workspace's `customerId` (workspace GUID) used by the query API. |
| `KeyVaultUri` | *(required, no default)* | Base vault URI, e.g. `https://<vault-name>.vault.azure.net`. |
| `ZscalerClientIdSecretName` | `zscaler-oneapi-client-id` | Key Vault secret name holding the Zscaler OneAPI OAuth2 client ID. |
| `ZscalerClientSecretSecretName` | `zscaler-oneapi-client-secret` | Key Vault secret name holding the Zscaler OneAPI OAuth2 client secret. |
| `ZscalerTokenUrlSecretName` | `zscaler-oneapi-token-url` | Key Vault secret name holding the full OAuth2 token URL, e.g. `https://<vanity-domain>.zslogin.net/oauth2/v1/token`. |
| `ZscalerApiBaseUri` | `https://api.zsapi.net` | Zscaler OneAPI gateway base URI (public endpoint, not a secret). |
| `ZscalerBlockCategory` | `OTHER_MISCELLANEOUS` | ZIA URL category that approved IPs/URLs are added to. |
| `ApproverUpn` | *(required, no default)* | UPN/email of the analyst who receives and must respond to the Teams adaptive card. |
| `ApprovalTimeout` | `PT8H` | ISO 8601 duration to wait for an explicit approval decision. |
| `AsimTimeRangeDays` | `7` | Lookback window (days) for the ASIM context query. |
| `AsimRowLimit` | `50` | Max rows returned per ASIM table in the context query. |

None of these defaults contain secrets, tenant names, or other customer-identifying values; the four required parameters (`LogAnalyticsWorkspaceResourceId`, `KeyVaultUri`, `ApproverUpn`) have no default and must be supplied at deployment time.

## Outputs

`azuredeploy.json` emits the following outputs so a consuming Bicep/ARM deployment can wire up RBAC role assignments and the Sentinel automation rule without re-deriving resource names:

| Output | Description |
| --- | --- |
| `workflowName` | Name of the deployed Logic App (playbook) resource. |
| `workflowResourceId` | Full ARM resource ID of the Logic App, e.g. for use as the automation rule's playbook target. |
| `principalId` | Object (principal) ID of the Logic App's system-assigned managed identity, for use in `roleAssignment` resources granting Key Vault Secrets User, Log Analytics Reader, and Microsoft Sentinel Responder (or equivalent). |
| `sentinelConnectionResourceId` | Resource ID of the `Microsoft.Web/connections` Sentinel connection. |
| `teamsConnectionResourceId` | Resource ID of the `Microsoft.Web/connections` Teams connection (for reference/monitoring; the one-time authorization step below still applies). |

## Prerequisites (complete before enabling the workflow)

1. **Deploy with `WorkflowState=Disabled`** (the default). Do not flip it to `Enabled` until steps 2–6 are done.
2. **Create the three Key Vault secrets out-of-band** — never in this template, a parameters file, or source control:
   - Zscaler OneAPI OAuth2 **client ID**
   - Zscaler OneAPI OAuth2 **client secret**
   - Zscaler OneAPI OAuth2 **token URL** (e.g. `https://<vanity-domain>.zslogin.net/oauth2/v1/token`)
   Use a Key Vault with soft delete and purge protection enabled.
3. **Grant RBAC to the playbook's managed identity** (created by this template but *not* assigned roles by it — the surrounding infrastructure deployment must grant):
   - **Key Vault Secrets User** (or equivalent least-privilege role) scoped to the Key Vault above.
   - **Log Analytics Reader** scoped to the target Log Analytics workspace.
   - **Microsoft Sentinel Responder** (or equivalent) so the playbook can comment on and tag incidents.
4. **Create a Zscaler OneAPI OAuth2 API client** authorized for the ZIA URL/IP category management and status-activation endpoints used by this playbook.
5. **Authorize the Teams connection once, manually** (cannot be automated by ARM):
   - In the Azure portal, open the deployed `teams-zscaler-asim-response` API connection resource (or open the Logic App in the designer).
   - Select **Edit API connection** (or equivalent) and complete interactive sign-in/consent for the account that will send and receive the approval adaptive card.
   - This is a one-time, per-environment step required because Teams uses delegated (interactive) OAuth consent rather than managed identity.
6. **Verify the Sentinel connection** resolves correctly (it is pre-configured for managed identity by this template; no manual auth step is required for it).
7. Only after the above, set `WorkflowState=Enabled` (redeploy or update the resource directly), then **attach this playbook to an incident-creation automation rule** — automation rule creation is out of scope for this directory and is owned by the surrounding infrastructure deployment.

## Workflow logic summary

```
Trigger: Microsoft Sentinel incident (ApiConnectionWebhook, /incident-creation)
  runtimeConfiguration.concurrency: runs=1, maximumWaitingRuns=1 (bounded in-flight guard)
  -> Initialize variables (AllCandidates, ApprovedValues, ApprovedEntitySummaryLines, RejectedEntitySummaryLines, ...)
  -> If incident already has the idempotency label (written only on prior success) -> comment "duplicate, skipping" -> end (Succeeded)
  -> Else:
       -> Extract IP entities and URL entities (parallel)
       -> If no IPs and no URLs found -> comment "no entities" -> end (Succeeded)
       -> Else:
            -> Build and run ASIM context query (Log Analytics Query REST API, managed identity)
            -> Build deduplicated candidate list AllCandidates = union of {Type:"IP",Value} and {Type:"URL",Value} objects
            -> Add enrichment comment to the incident (notes each candidate will be approved individually)
            -> For_Each_Candidate_Request_Approval (sequential, repetitions=1 - one candidate at a time):
                 -> Build an adaptive card for THIS candidate only: exact type/value, IP source/client/internal/victim caution, ASIM context
                 -> Post to Teams approver, wait for THIS candidate's decision (bounded by ApprovalTimeout)
                 -> If approved -> append value to ApprovedValues, append line to ApprovedEntitySummaryLines
                 -> Else (rejected or timed out) -> append line to RejectedEntitySummaryLines only (never sent to Zscaler)
            -> Check_Any_Approved: length(ApprovedValues) > 0 ?
                 -> If NOT (no candidate approved):
                      -> Comment outcome (lists rejections; states no Key Vault/Zscaler calls were made and no marker written)
                      -> End (Succeeded; no marker written; safe to retry later, e.g. after new entities are added to the incident)
                 -> If approved (at least one candidate):
                      -> Get Zscaler client ID / client secret / token URL from Key Vault (managed identity, parallel)
                      -> If any secret retrieval failed -> comment + end (Failed; no marker written)
                      -> Request Zscaler OAuth2 token (client_credentials grant)
                      -> If token request failed -> comment + end (Failed; no marker written)
                      -> Add ONLY ApprovedValues (never rejected/timed-out entities) to the Zscaler ZIA URL category in a single batched call
                      -> If that call failed -> comment + end (Failed; no marker written)
                      -> Activate the ZIA configuration change once
                      -> If activation failed -> comment + end (Failed; no marker written)
                      -> Comment the list of individually-approved blocked entities back to the incident
                      -> Add the idempotency label + a "block completed" label to the incident (only reached on full success)
```


## Deployment

This is an ARM template; deploy with Azure CLI, PowerShell, or the Azure portal's "custom template" import, for example:

```powershell
New-AzResourceGroupDeployment `
  -ResourceGroupName "<resource-group>" `
  -TemplateFile "azuredeploy.json" `
  -LogAnalyticsWorkspaceResourceId "<workspace-resource-id>" `
  -KeyVaultUri "https://<vault-name>.vault.azure.net" `
  -ApproverUpn "<approver-upn>"
```

`WorkflowState` defaults to `Disabled`, so the deployment creates the resources without activating the trigger. **This command is provided for reference only — do not run a deployment as part of this task.**

## Out of scope for this directory

- Role assignments / RBAC for the playbook's managed identity (Key Vault, Log Analytics, Sentinel).
- Sentinel automation rules that invoke this playbook.
- Any Workbook, Cribl, or other content-pack component outside `Playbooks/Zscaler-ASIM-Incident-Response`.

These are handled by the broader repository/infrastructure deployment.
