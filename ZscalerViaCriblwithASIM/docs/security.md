# Security design

## Trust boundaries

1. Cribl normalization ends at the ASIM parser boundary.
2. Microsoft Sentinel detections and workbooks have read-only access to
   normalized events.
3. Both Logic Apps use managed identity for Azure control-plane and data-plane
   access.
4. The Teams connector uses delegated OAuth for the human approval step.
5. Zscaler OAuth credentials remain in Key Vault and are fetched only after
   approval.
6. The reusable operation workflow accepts only Microsoft Entra bearer tokens
   from the deployment tenant, for the configured audience, and from the
   configured managed-identity object ID. Request-trigger SAS is disabled.

## Least-privilege assignments

The deployment grants the incident playbook managed identity:

- Log Analytics Reader on the target workspace;
- Microsoft Sentinel Responder on the target workspace;
- Key Vault Secrets User on the pack Key Vault.

The deployment grants the reusable operation-workflow identity Key Vault
Secrets User on the same vault. The Cribl workload identity receives
Monitoring Metrics Publisher only on the DCR when its object ID is supplied.

The Microsoft Sentinel service principal receives Microsoft Sentinel
Automation Contributor at the playbook resource-group scope so an automation
rule can invoke the workflow.

## Deliberate safety gates

- Both workflows are deployed disabled.
- Zscaler mutations have an independent kill switch that defaults to disabled.
- The automation rule is deployed disabled.
- No Key Vault secret values are deployed.
- The Teams connection must be authorized interactively.
- The automation rule is restricted to analytic-rule IDs deployed by this
  pack.
- Each entity mutation requires a named analyst to approve an adaptive card.
- The incident workflow is the only authorized caller of the reusable
  operation workflow by default.
- URL/IP actions are serialized, retries are bounded, and activation runs
  once.
- The success marker is written only after successful Zscaler activation.
- Incident comments provide an audit trail and an idempotency marker.

## Operator activation sequence

1. Run all Cribl ASIM contract queries and confirm required-field
   completeness.
2. Set the Zscaler OAuth values in Key Vault using an approved secure
   workflow.
3. Authorize both Teams API connections.
4. Enable and test the reusable workflow with lookup-only operations.
5. Enable mutation and run a controlled per-entity approval test against a
   non-production Zscaler category.
6. Review Logic App run-history redaction.
7. Enable and test the incident playbook.
8. Enable the automation rule.

## Secrets

Do not pass Zscaler secrets through chat, commit history, deployment parameter
files, CI variables visible to pull requests, or Logic App action inputs that
lack secure-data settings.
