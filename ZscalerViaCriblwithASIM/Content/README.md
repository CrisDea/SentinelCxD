# Content parity baseline

`content-parity.json` pins the Microsoft Sentinel ZIA/ZPA baseline used by this
pack and records the expected replacement manifest for every content type.

The pack intentionally replaces the upstream direct data connectors with a
Cribl-owned ingestion stream and ASIM source parsers. This is a semantic
replacement: rules, hunts, workbooks, and playbooks consume ASIM rather than
the physical destination table.

Validation fails when a replacement manifest is missing, its item count does
not match the pinned baseline, a content query references a raw table, or a
required ASIM parser is absent.
