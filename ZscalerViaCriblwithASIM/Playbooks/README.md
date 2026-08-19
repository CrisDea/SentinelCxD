# Zscaler response playbooks

This directory provides a hardened incident response workflow and a reusable ZIA OAuth2 child workflow with exact coverage of the ten standard operations in Azure-Sentinel commit `cd455a8cecf3e5e983f9cd08191dca3d211c9fa1`.

## Architecture

| Component | Purpose |
| --- | --- |
| `Zscaler-ASIM-Incident-Response/azuredeploy.json` | Existing Sentinel incident orchestrator: managed-identity ASIM enrichment, sequential per-entity Teams approval, ZIA block/activation, and post-activation incident marker. |
| `Zscaler-ZIA-Operation/azuredeploy.json` | Shared, one-entity child workflow for all ten authentication, lookup, and mutation capabilities. |
| `playbook-parity.json` | Machine-readable upstream-to-secure-operation mapping. `operationCount` and the `operations` array are exactly ten. |

One entity per child invocation is deliberate. A caller cannot submit a list under one approval. Incident orchestrators must invoke it inside a sequential loop (`repetitions: 1`) and must not add their own bulk-approval bypass.

## Safety defaults

- Both workflow templates deploy with `WorkflowState=Disabled`.
- The child workflow has a second kill switch, `EnableMutatingOperations=false`. Authentication and lookups can be enabled while every mutation remains rejected.
- The child Request trigger disables SAS and accepts only Microsoft Entra bearer tokens whose deployment-tenant issuer, configured audience, and exact caller managed-identity `oid` all match its resource-level authorization policy.
- `AuthorizedCallerObjectId` defaults to the all-zero GUID, so the child is fail-closed until parent integration supplies one approved managed identity.
- Every mutation (`block-*`, `unblock-*`, `blacklist-url`, `unblacklist-url`, `whitelist-url`) waits for an explicit Teams approval for the exact operation and entity.
- Rejection or approval timeout returns `403`, does not read Key Vault, does not request an OAuth token, and does not contact Zscaler.
- Authentication and lookups require no mutation approval. Their responses never include credentials or an access token.
- The request schema and a fixed in-workflow allowlist reject unknown operations. Entity values are trimmed, length-bounded, and rejected when empty or containing spaces/newlines; IP operations additionally require an IPv4-like dot or IPv6-like colon, while URL operations require a dotted host or an `http://`/`https://` prefix.
- Trigger concurrency is bounded to one active and one waiting run. The incident orchestrator retains its sequential candidate loop.
- All Key Vault, OAuth, authorized ZIA, approval, and sensitive response actions use secure inputs/outputs where supported.
- All outbound HTTP actions have explicit timeouts and bounded exponential retry. Status codes are checked; failures return non-2xx responses rather than success-shaped bodies.

## Deployment sequence

1. Deploy both templates with `WorkflowState=Disabled` and `EnableMutatingOperations=false`.
2. Create the following Key Vault secrets out of band:
   - `zscaler-oneapi-client-id`
   - `zscaler-oneapi-client-secret`
   - `zscaler-oneapi-token-url`
3. Grant each workflow identity that reads secrets **Key Vault Secrets User** on the vault. The incident workflow also needs the documented Log Analytics and Sentinel roles.
4. Authorize each deployed Teams API connection interactively. ARM cannot complete delegated Teams consent.
5. Configure and verify:
   - `AuthorizedCallerObjectId` set to the approved caller workflow managed identity's object ID
   - `TriggerAudience` (the caller must request its token for this exact audience)
   - `ZscalerApiBaseUri` and `ZscalerCloudName`
   - `IpBlockCategoryId` and `UrlBlockCategoryId`
   - endpoint path parameters
   - `LookupEndpointPath` and `LookupTimeout`
   - `ApproverUpn` and `ApprovalTimeout`
6. Test `authentication`, `lookup-ip`, and `lookup-url` while mutation remains disabled.
7. Enable the workflow. Only after approval behavior and rollback procedures are tested should `EnableMutatingOperations` be set to `true`.

SAS is unavailable by design. Do not add `sp`, `sv`, or `sig` query parameters or re-enable `sasAuthenticationPolicy`. The parent should obtain the Request trigger URL through ARM at deployment time, keep it out of source control, and call it with an HTTP action configured for `ManagedServiceIdentity` authentication and the exact `TriggerAudience`. The bearer token's `oid` must equal `AuthorizedCallerObjectId`.

## Invocation contract

Invoke the `manual` trigger with one operation and, except for authentication, one entity:

```json
{
  "operation": "lookup-url",
  "entity": "example.test",
  "incidentId": "<optional Sentinel incident ARM ID>",
  "requestedBy": "<optional caller identity>",
  "context": {}
}
```

The fixed operations are:

`authentication`, `block-ip`, `block-url`, `unblock-ip`, `unblock-url`, `lookup-ip`, `lookup-url`, `blacklist-url`, `unblacklist-url`, and `whitelist-url`.

Successful mutations return `activated=true` and `safeToWriteIdempotencyMarker=true` only after the activation endpoint returns 2xx. Callers must treat all other responses as failures and must not write a success marker. The child has no success-shaped catch path.

## Rollback

- `block-ip` rolls back through a separately approved `unblock-ip`.
- `block-url` rolls back through a separately approved `unblock-url`.
- `blacklist-url` rolls back through a separately approved `unblacklist-url`.
- Re-applying a removed entry uses the corresponding block/blacklist operation and requires a new approval.
- Upstream defines no `unwhitelist-url` capability among the ten standard playbooks. Remove a whitelist entry through a separately controlled administrative process; do not repurpose `unblacklist-url`.

Rollback operations are mutations: the kill switch must be enabled, each entity must be approved independently, ZIA activation must succeed, and only then may the caller mark rollback complete.

## Parent integration requirements

The parent ARM/Bicep layer must:

1. Deploy `Zscaler-ZIA-Operation/azuredeploy.json` and consume `workflowResourceId`, `principalId`, and `teamsConnectionResourceId`.
2. Assign least-privilege Key Vault access to `principalId`; do not pass secret values as parameters.
3. Set `AuthorizedCallerObjectId` to the existing incident orchestrator's managed-identity object ID and set `TriggerAudience` to the audience that identity will request.
4. Resolve the child's `manual` Request trigger URL through ARM and wire the incident orchestrator to it with an HTTP action using `ManagedServiceIdentity` authentication and that exact audience. Invoke one entity per sequential iteration; do not use SAS or a Logic Apps `Workflow` action that depends on a callback signature.
5. Preserve the existing Sentinel managed-identity connection, trigger concurrency, per-entity loop concurrency, and incident comments.
6. Write an incident idempotency label only after a child mutation returns HTTP 200 with `safeToWriteIdempotencyMarker=true`.
7. Keep unauthorized, rejected, timed-out, validation-failed, OAuth-failed, operation-failed, and activation-failed branches marker-free.
8. Do not create a direct Zscaler data-connector dependency.

Deployment is intentionally not performed by this content.
