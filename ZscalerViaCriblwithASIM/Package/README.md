# Package contents

`mainTemplate.json` is generated from `infra/main.bicep` by
`scripts/Build-Pack.ps1`. Do not edit the generated template directly.

`createUiDefinition.json` exposes only non-secret deployment values. Zscaler
OAuth values are deliberately excluded and must be created in Key Vault after
deployment.

The generated ZIP also contains 12 analytic rules, 10 hunting queries,
21 workbook JSON files, ASIM parser sources, two playbook templates, the
Cribl contract and ingestion module, deployment scripts, CI validation, and
third-party notices so recipients can inspect and rebuild the package.
