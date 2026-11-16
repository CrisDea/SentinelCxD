# Changelog

## Unreleased

- Deny Key Vault data-plane traffic by default and add explicit IP allowlists for Key Vault and the ZIA operation HTTP trigger.
- Keep Key Vault public network access enabled for the current multitenant Logic Apps architecture; disabling it requires private networking changes.
- Update pinned CodeQL, Scorecard and artifact upload actions.
- Reject malformed release tags and unsafe build version paths before packaging.
- Add regression coverage for release version validation.
- Run the required validation check for every pull request, including action-only changes.
- Update CodeQL to v4.39.3 to fix alert filtering for paths with spaces or special characters.
