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
