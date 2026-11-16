# Zscaler ZIA operation child workflow

`azuredeploy.json` packages all ten standard ZIA OAuth2 response capabilities behind one allowlisted, one-entity Logic App Request trigger. See [`../README.md`](../README.md) for deployment, Key Vault, approval, rollback, and parent-wiring requirements, and [`../playbook-parity.json`](../playbook-parity.json) for the exact upstream mapping.

The workflow is disabled by default. Mutation remains independently disabled by `EnableMutatingOperations=false`, even when the workflow is enabled for authentication and lookup testing. The template creates a system-assigned managed identity and a Teams connection but does not create RBAC assignments, authorize Teams, expose the signed trigger URL, create Sentinel automation, or deploy anything.

## Request-trigger authorization

SAS authentication is disabled at the Logic App resource level. SAS query parameters and previously generated SAS signatures cannot invoke the trigger while this policy remains disabled. The only accepted authorization scheme is a Microsoft Entra bearer token matching all three claims in `ApprovedManagedIdentityOnly`:

- `iss`: derived as `https://sts.windows.net/<deployment-tenant-id>/`
- `aud`: exact value of `TriggerAudience` (default `https://management.azure.com/`)
- `oid`: exact value of `AuthorizedCallerObjectId`

`AuthorizedCallerObjectId` defaults to `00000000-0000-0000-0000-000000000000`, which intentionally matches no real managed identity. Parent integration must set it to the approved caller workflow's managed-identity object ID before any call can succeed.

The caller uses an HTTP action with managed identity authentication, sets its token audience to exactly `TriggerAudience`, and posts to the child Request trigger URL without `sp`, `sv`, or `sig` query parameters. Azure Logic Apps validates the token before starting the child workflow; the JSON allowlist and mutation approval controls then apply inside the workflow.

Reference: [Secure access and data in workflows - Azure Logic Apps](https://learn.microsoft.com/azure/logic-apps/logic-apps-securing-a-logic-app), including the Microsoft Entra authorization-policy and SAS-disable guidance for Consumption Request triggers.

The Request trigger also applies an IP allowlist. Its default `0.0.0.0/32` is intentionally fail-closed; before enabling the workflow, set `AllowedCallerIpAddresses` to the approved caller's stable egress CIDR ranges. Keep the Entra claims policy enabled as a second authorization layer.

## Key Vault network access

The shared Key Vault firewall defaults to `defaultAction: Deny` with no public IP rules. For the multitenant Logic Apps in this pack to read secrets, deployment owners must set `keyVaultAllowedIpRules` to the Logic Apps' outbound IP ranges for the deployed region (each entry uses `{ "value": "<CIDR>" }`) and retain Entra/RBAC authorization. The sample parameter file intentionally has no Key Vault IP rules, so secret reads remain blocked until an explicit allowlist is configured.

`publicNetworkAccess` remains `Enabled` because these multitenant Logic Apps need outbound access to Key Vault and the pack does not provision private endpoints or VNet integration. To disable public network access, first migrate the workflows to a network-isolated design with a verified private route to Key Vault; simply switching this flag off would break secret retrieval. See [Key Vault network security](https://learn.microsoft.com/azure/key-vault/general/network-security) and [Logic Apps IP address ranges](https://learn.microsoft.com/azure/logic-apps/logic-apps-limits-and-config).
