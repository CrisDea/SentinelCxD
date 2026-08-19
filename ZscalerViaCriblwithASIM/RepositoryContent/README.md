# Microsoft Sentinel repository deployment entry point

`main.bicep` is the customer-neutral entry point for Microsoft Sentinel
Repositories. The generated GitHub workflow supplies the required `workspace`
parameter for the connected Sentinel workspace.

After creating the repository connection in the Microsoft Defender portal,
scope its generated workflow to:

```text
ZscalerViaCriblwithASIM/RepositoryContent
```

The deployment creates the Cribl ingestion landing zone by default. Both Logic
Apps, Zscaler mutation, and the Sentinel automation rule remain disabled until
the customer completes secure post-deployment configuration.
