# Third-party notices

This pack adapts detection intent, workbook coverage, and response API
semantics from the MIT-licensed
[Azure/Azure-Sentinel](https://github.com/Azure/Azure-Sentinel) repository.

Upstream solution paths:

- `Solutions/Zscaler Internet Access`
- `Solutions/Zscaler Private Access (ZPA)`

Versions reviewed for this pack:

- Zscaler Internet Access: 3.0.3
- Zscaler Internet Access CCF: 3.0.4
- Zscaler Private Access: 3.0.4

Full-content parity is pinned to Azure-Sentinel commit
`cd455a8cecf3e5e983f9cd08191dca3d211c9fa1`. The reviewed baseline contains
12 analytic rules, 18 workbooks, 10 hunting queries, 15 ZIA Cloud NSS
connector families, one ZPA connector/parser family, and 10 ZIA OAuth
response operations.

The adapted content replaces upstream raw-table dependencies with Microsoft
Sentinel ASIM unifying parsers. Zscaler product names and trademarks remain
the property of their respective owners.
