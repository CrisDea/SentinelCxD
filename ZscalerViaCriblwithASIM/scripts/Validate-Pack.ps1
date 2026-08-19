[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$ResourceGroup,
    [string]$WorkspaceName,
    [switch]$SkipLiveKql,
    [switch]$SkipIngestionKql
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$expectedCommit = 'cd455a8cecf3e5e983f9cd08191dca3d211c9fa1'
$forbiddenTelemetryPattern = '\bCommonSecurityLog\b|\bZPAEvent\b|\bZscalerCribl_CL\b'

function Assert-Condition {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-JsonFile {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $root $RelativePath
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) `
        "Required file not found: $RelativePath"
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
}

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed: az $($Arguments -join ' ')"
    }
}

function Get-KqlQueries {
    param([AllowNull()][object]$Node)

    if ($null -eq $Node -or $Node -is [string] -or
        $Node -is [ValueType]) {
        return
    }

    if ($Node -is [System.Collections.IEnumerable] -and
        $Node -isnot [pscustomobject]) {
        foreach ($item in $Node) {
            Get-KqlQueries -Node $item
        }
        return
    }

    if ($Node -is [pscustomobject]) {
        foreach ($property in $Node.PSObject.Properties) {
            if ($property.Name -eq 'query' -and
                $property.Value -is [string] -and
                -not [string]::IsNullOrWhiteSpace($property.Value)) {
                $property.Value
            }
            else {
                Get-KqlQueries -Node $property.Value
            }
        }
    }
}

function Get-LogicAppMaximumNesting {
    param(
        [Parameter(Mandatory)]$Actions,
        [int]$Depth = 0
    )

    $maximum = $Depth
    foreach ($property in $Actions.PSObject.Properties) {
        $action = $property.Value
        $nestedActionSets = @(
            $action.actions
            $action.else.actions
            $action.default.actions
        )
        $nestedActionSets += @($action.cases.PSObject.Properties |
            ForEach-Object { $_.Value.actions })

        foreach ($nestedActions in $nestedActionSets) {
            if ($null -ne $nestedActions) {
                $nestedMaximum = Get-LogicAppMaximumNesting `
                    -Actions $nestedActions -Depth ($Depth + 1)
                $maximum = [Math]::Max($maximum, $nestedMaximum)
            }
        }
    }

    return $maximum
}

function Get-LogicAppActions {
    param([Parameter(Mandatory)]$Actions)

    foreach ($property in $Actions.PSObject.Properties) {
        $action = $property.Value
        [pscustomobject]@{
            Name = $property.Name
            Type = $action.type
            Action = $action
        }

        $nestedActionSets = @(
            $action.actions
            $action.else.actions
            $action.default.actions
        )
        $nestedActionSets += @($action.cases.PSObject.Properties |
            ForEach-Object { $_.Value.actions })
        foreach ($nestedActions in $nestedActionSets) {
            if ($null -ne $nestedActions) {
                Get-LogicAppActions -Actions $nestedActions
            }
        }
    }
}

function Convert-WorkbookQueryForCompilation {
    param([Parameter(Mandatory)][string]$Query)

    $normalized = $Query `
        -replace 'TimeGenerated\s+\{TimeRange\}',
            'TimeGenerated between (ago(24h) .. now())' `
        -replace '\{TimeRange:start\}', 'ago(24h)' `
        -replace '\{TimeRange:end\}', 'now()' `
        -replace '\{TimeRange:grain\}', '1h' `
        -replace '\{TimeRange\}', '24h'

    $normalized = $normalized -replace "'\{[^}]+\}'", "'All'"
    $normalized = $normalized -replace '\{[^}]+\}', 'dynamic([])'
    return $normalized
}

Write-Host 'Generating deterministic deployment manifests...'
& (Join-Path $PSScriptRoot 'Generate-DeploymentManifests.ps1')

Write-Host 'Validating customer-neutral content...'
$forbiddenCustomerPattern = '(?i)' + (
    @(
        '/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        '\bSentinel_rg\b'
        '\bSentinelLAW\b'
        '\bME-MngEnvMCAP'
        '\b7ad02141-9daf-43c3-a3f9-3d0cb90ccc2c\b'
        '\bf0cfe7d5-ee2b-4800-92eb-fa936734a04b\b'
        '\bfc063896-2fd6-4f52-93b7-5e99a729d188\b'
        '\bcdeangelis@microsoft\.com\b'
    ) -join '|'
)
Get-ChildItem -Path $root -Recurse -File |
    Where-Object {
        $_.FullName -notmatch '\\dist\\' -and
        $_.FullName -notmatch '\\infra\\main\.parameters\.json$' -and
        $_.Extension -in @(
            '.bicep', '.json', '.md', '.ps1', '.yml', '.yaml'
        )
    } |
    ForEach-Object {
        $content = Get-Content -LiteralPath $_.FullName -Raw
        Assert-Condition ($content -notmatch $forbiddenCustomerPattern) `
            "Customer-specific value found in $($_.FullName)."
    }

Write-Host 'Validating JSON files...'
Get-ChildItem -Path $root -Recurse -File -Filter '*.json' |
    Where-Object FullName -NotMatch '\\dist\\' |
    ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw |
            ConvertFrom-Json -Depth 100 | Out-Null
    }

$rules = Get-JsonFile 'Analytic Rules\rules.json'
$hunts = Get-JsonFile 'Hunting Queries\hunting-queries.json'
$ziaWorkbooks = Get-JsonFile 'Workbooks\zia-workbook-parity.json'
$zpaWorkbook = Get-JsonFile 'Workbooks\zpa-workbook-parity.json'
$workbookDeployment = Get-JsonFile 'infra\generated\workbooks.json'
$playbookParity = Get-JsonFile 'Playbooks\playbook-parity.json'
$familyMapping = Get-JsonFile 'Cribl\family-mapping.json'
$parserManifest = Get-JsonFile 'Parsers\parser-manifest.json'
$normalizationContract = Get-JsonFile 'Cribl\normalization-contract.json'
$contentParity = Get-JsonFile 'Content\content-parity.json'

Write-Host 'Validating pinned content parity...'
Assert-Condition ($contentParity.baseline.commit -eq $expectedCommit) `
    'Content parity baseline commit is not pinned to the approved upstream commit.'
Assert-Condition ($contentParity.coverage.Count -eq 8) `
    'Content parity manifest must contain eight coverage categories.'
Assert-Condition (@($contentParity.coverage |
        Where-Object status -ne 'complete').Count -eq 0) `
    'Every content parity category must be complete before release.'
foreach ($coverage in $contentParity.coverage) {
    Assert-Condition (Test-Path -LiteralPath (
        Join-Path $root $coverage.replacementManifest
    ) -PathType Leaf) "Missing replacement manifest: $($coverage.replacementManifest)"
    Assert-Condition ($coverage.upstreamCount -eq $coverage.replacementCount) `
        "Parity count mismatch for $($coverage.product) $($coverage.contentType)."
}

Assert-Condition ($rules.Count -eq 12) `
    "Expected 12 analytic rules, found $($rules.Count)."
Assert-Condition (@($rules.id | Sort-Object -Unique).Count -eq 12) `
    'Analytic rule IDs must be unique.'
Assert-Condition (@($rules | Where-Object displayName -Match '\bZIA\b').Count -eq 2) `
    'Expected two ZIA analytic rules.'
Assert-Condition (@($rules | Where-Object displayName -Match '\bZPA\b').Count -eq 10) `
    'Expected ten ZPA analytic rules.'

Assert-Condition ($hunts.upstream.commit -eq $expectedCommit) `
    'Hunting-query baseline commit mismatch.'
Assert-Condition ($hunts.queries.Count -eq 10) `
    'Expected ten ZPA hunting queries.'
Assert-Condition (@($hunts.queries.id | Sort-Object -Unique).Count -eq 10) `
    'Hunting-query IDs must be unique.'
foreach ($hunt in $hunts.queries) {
    foreach ($field in @(
        'id', 'displayName', 'description', 'query', 'tactics',
        'techniques', 'entityMappings', 'version', 'sourceFile'
    )) {
        Assert-Condition ($null -ne $hunt.$field) `
            "Hunting query '$($hunt.displayName)' is missing '$field'."
    }
}

Assert-Condition ($ziaWorkbooks.sourceCommit -eq $expectedCommit) `
    'ZIA workbook baseline commit mismatch.'
Assert-Condition ($ziaWorkbooks.workbookCount -eq 17 -and
    $ziaWorkbooks.workbooks.Count -eq 17) `
    'Expected 17 ZIA workbook mappings.'
Assert-Condition ($ziaWorkbooks.sourcePanelCount -eq 81 -and
    $ziaWorkbooks.mappedPanelCount -eq 81) `
    'Expected all 81 ZIA workbook panels to be mapped.'
Assert-Condition (@($ziaWorkbooks.workbooks |
        Where-Object status -ne 'mapped').Count -eq 0) `
    'Every ZIA workbook mapping must have mapped status.'

Assert-Condition ($zpaWorkbook.upstream.commit -eq $expectedCommit) `
    'ZPA workbook baseline commit mismatch.'
Assert-Condition ($zpaWorkbook.upstream.queryPanelCount -eq
    $zpaWorkbook.target.queryPanelCount) `
    'ZPA workbook panel count does not match upstream.'
Assert-Condition ($workbookDeployment.workbookCount -eq 21 -and
    $workbookDeployment.workbooks.Count -eq 21) `
    'Expected 21 deployed workbooks: 18 parity plus three consolidated views.'
Assert-Condition (@($workbookDeployment.workbooks.key |
        Sort-Object -Unique).Count -eq 21) `
    'Workbook deployment keys must be unique.'

Assert-Condition ($playbookParity.upstream.commit -eq $expectedCommit) `
    'Playbook baseline commit mismatch.'
Assert-Condition ($playbookParity.operationCount -eq 10 -and
    $playbookParity.operations.Count -eq 10) `
    'Expected ten ZIA response operations.'
Assert-Condition (@($playbookParity.operations.operation |
        Sort-Object -Unique).Count -eq 10) `
    'ZIA response operation names must be unique.'

Assert-Condition ($familyMapping.upstream.commit -eq $expectedCommit) `
    'Cribl family-mapping baseline commit mismatch.'
Assert-Condition ($familyMapping.ziaFamilies.Count -eq 15) `
    'Expected 15 ZIA Cribl source families.'
Assert-Condition ($familyMapping.zpa.subfamilies.Count -eq 3) `
    'Expected ZPA access, authentication, and administration routes.'
Assert-Condition ($parserManifest.upstreamCommit -eq $expectedCommit) `
    'ASIM parser baseline commit mismatch.'
Assert-Condition ($parserManifest.functions.Count -eq 6) `
    'Expected six ASIM schema parser pairs.'
Assert-Condition (@($parserManifest.functions.sourceSpecific |
        Sort-Object -Unique).Count -eq 6) `
    'Source-specific parser names must be unique.'
Assert-Condition (@($parserManifest.functions.customUnifying |
        Sort-Object -Unique).Count -eq 6) `
    'Custom unifying parser names must be unique.'

Write-Host 'Validating AdditionalFields coverage...'
$requiredAdditionalFields = @(
    $ziaWorkbooks.workbooks.additionalFieldsKeys
    $zpaWorkbook.target.additionalFields
    $hunts.queries.additionalFields
) | Where-Object { $_ } | Sort-Object -Unique
$contractAdditionalFields =
    @($normalizationContract.output.requiredAdditionalFieldsForContent) |
    Sort-Object -Unique
$missingAdditionalFields = @(
    $requiredAdditionalFields |
        Where-Object { $_ -notin $contractAdditionalFields }
)
Assert-Condition ($missingAdditionalFields.Count -eq 0) `
    "Cribl contract is missing AdditionalFields keys: $($missingAdditionalFields -join ', ')"

Write-Host 'Checking content for forbidden raw-table dependencies...'
foreach ($rule in $rules) {
    Assert-Condition ($rule.query -notmatch $forbiddenTelemetryPattern) `
        "Raw-table dependency found in rule query: $($rule.displayName)"
}
foreach ($hunt in $hunts.queries) {
    Assert-Condition ($hunt.query -notmatch $forbiddenTelemetryPattern) `
        "Raw-table dependency found in hunt query: $($hunt.displayName)"
}

$workbookQueryRecords = [System.Collections.Generic.List[object]]::new()
Get-ChildItem (Join-Path $root 'Workbooks') -File -Filter '*.json' |
    Where-Object Name -NotMatch '-parity\.json$' |
    ForEach-Object {
        $workbook = Get-Content -LiteralPath $_.FullName -Raw |
            ConvertFrom-Json -Depth 100
        $index = 0
        foreach ($query in @(Get-KqlQueries -Node $workbook)) {
            $index++
            Assert-Condition ($query -notmatch $forbiddenTelemetryPattern) `
                "Raw-table dependency found in workbook query: $($_.Name) query $index"
            $workbookQueryRecords.Add([pscustomobject]@{
                Name = "$($_.Name) query $index"
                Query = $query
            })
        }
    }

$zpaAlertQueries = @($workbookQueryRecords |
    Where-Object { $_.Query -match '\bSecurityAlert\b' })
Assert-Condition ($zpaAlertQueries.Count -eq 1) `
    'SecurityAlert is allowed only in the single ZPA Latest Alerts panel.'

Write-Host 'Validating request-trigger security...'
$operationTemplate = Get-JsonFile `
    'Playbooks\Zscaler-ZIA-Operation\azuredeploy.json'
$operationWorkflow = @($operationTemplate.resources |
    Where-Object type -eq 'Microsoft.Logic/workflows')[0]
$triggerAccess = $operationWorkflow.properties.accessControl.triggers
Assert-Condition ($triggerAccess.sasAuthenticationPolicy.state -eq 'Disabled') `
    'The ZIA operation Request trigger must disable SAS.'
$maximumNesting = Get-LogicAppMaximumNesting `
    -Actions $operationWorkflow.properties.definition.actions
Assert-Condition ($maximumNesting -le 8) `
    "The ZIA operation workflow action nesting level is $maximumNesting; Azure allows 8."
$operationActions = @(Get-LogicAppActions `
    -Actions $operationWorkflow.properties.definition.actions)
$secureResponses = @($operationActions | Where-Object {
    $_.Type -eq 'Response' -and $_.Action.runtimeConfiguration.secureData
})
Assert-Condition ($secureResponses.Count -eq 0) `
    'Logic Apps Response actions do not support secureData configuration.'
$unsecuredSensitiveActions = @($operationActions | Where-Object {
    $_.Type -in @('Http', 'ApiConnectionWebhook') -and
    -not $_.Action.runtimeConfiguration.secureData
})
Assert-Condition ($unsecuredSensitiveActions.Count -eq 0) `
    'Every Key Vault, OAuth, Zscaler, and approval action must redact inputs and outputs.'
$operationTrigger = $operationWorkflow.properties.definition.triggers.manual
Assert-Condition ($null -eq $operationTrigger.runtimeConfiguration.concurrency) `
    'A synchronous Request/Response workflow cannot use trigger concurrency.'
$incidentTemplate = Get-JsonFile `
    'Playbooks\Zscaler-ASIM-Incident-Response\azuredeploy.json'
$incidentWorkflow = @($incidentTemplate.resources |
    Where-Object type -eq 'Microsoft.Logic/workflows')[0]
$incidentConcurrency = $incidentWorkflow.properties.definition.triggers.
    'Microsoft_Sentinel_incident'.runtimeConfiguration.concurrency
Assert-Condition ($incidentConcurrency.runs -eq 1 -and
    $incidentConcurrency.maximumWaitingRuns -eq 1) `
    'The authorized incident caller must serialize workflow runs.'
$claims = @(
    $triggerAccess.openAuthenticationPolicies.policies.
        ApprovedManagedIdentityOnly.claims.name
)
Assert-Condition (@('iss', 'aud', 'oid' |
    Where-Object { $_ -notin $claims }).Count -eq 0) `
    'The ZIA operation Request trigger must require iss, aud, and oid claims.'
Assert-Condition ($operationTemplate.parameters.WorkflowState.defaultValue -eq
    'Disabled') 'The ZIA operation workflow must be disabled by default.'
Assert-Condition (-not $operationTemplate.parameters.
    EnableMutatingOperations.defaultValue) `
    'ZIA mutating operations must be disabled by default.'
Assert-Condition ($operationTemplate.parameters.
    AuthorizedCallerObjectId.defaultValue -eq
    '00000000-0000-0000-0000-000000000000') `
    'The ZIA operation caller must default to a fail-closed identity.'
$mainBicep = Get-Content (Join-Path $root 'infra\main.bicep') -Raw
Assert-Condition ($mainBicep -match `
    'value:\s+take\(hunt\.description,\s*256\)') `
    'Saved-search description tags must be capped at Azure''s 256-character limit.'

Write-Host 'Building and linting Bicep...'
Invoke-Az @(
    'bicep', 'build',
    '--file', (Join-Path $root 'infra\main.bicep'),
    '--outfile', (Join-Path $root 'Package\mainTemplate.json')
)
Invoke-Az @(
    'bicep', 'lint',
    '--file', (Join-Path $root 'infra\main.bicep')
)
$repositoryTemplate = Join-Path $env:TEMP `
    "zscaler-repository-$([guid]::NewGuid().ToString('N')).json"
try {
    Invoke-Az @(
        'bicep', 'build',
        '--file', (Join-Path $root 'RepositoryContent\main.bicep'),
        '--outfile', $repositoryTemplate
    )
    Invoke-Az @(
        'bicep', 'lint',
        '--file', (Join-Path $root 'RepositoryContent\main.bicep')
    )
}
finally {
    Remove-Item -LiteralPath $repositoryTemplate -Force `
        -ErrorAction SilentlyContinue
}

if ($SkipLiveKql) {
    Write-Host 'Portable pack validation completed successfully.'
    return
}

foreach ($value in @{
    SubscriptionId = $SubscriptionId
    ResourceGroup = $ResourceGroup
    WorkspaceName = $WorkspaceName
}.GetEnumerator()) {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($value.Value)) `
        "$($value.Key) is required unless -SkipLiveKql is used."
}

$workspaceId = & az monitor log-analytics workspace show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --query customerId `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($workspaceId)) {
    throw 'Unable to resolve the Log Analytics workspace customer ID.'
}

$env:AZURE_CORE_HTTP_TIMEOUT = '120'

function Test-Kql {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Query
    )

    Write-Host "Compiling KQL: $Name"
    $bodyPath = Join-Path $env:TEMP `
        "sentinel-asim-kql-$([guid]::NewGuid().ToString('N')).json"
    @{ query = $Query } |
        ConvertTo-Json -Compress |
        Set-Content -LiteralPath $bodyPath -Encoding utf8NoBOM
    try {
        $succeeded = $false
        for ($attempt = 1; $attempt -le 3 -and -not $succeeded; $attempt++) {
            $output = & az rest `
                --method post `
                --uri "https://api.loganalytics.azure.com/v1/workspaces/$workspaceId/query" `
                --resource 'https://api.loganalytics.io/' `
                --headers 'Content-Type=application/json' `
                --body "@$bodyPath" `
                --output none 2>&1
            $succeeded = $LASTEXITCODE -eq 0
            if (-not $succeeded -and $attempt -lt 3) {
                Start-Sleep -Seconds (5 * $attempt)
            }
        }
        if (-not $succeeded) {
            throw "KQL compilation failed for '$Name':`n$output"
        }
    }
    finally {
        Remove-Item -LiteralPath $bodyPath -Force
    }
}

function Test-ResourceGraphKql {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Query
    )

    Write-Host "Compiling Azure Resource Graph KQL: $Name"
    $bodyPath = Join-Path $env:TEMP `
        "sentinel-asim-arg-$([guid]::NewGuid().ToString('N')).json"
    @{
        subscriptions = @($SubscriptionId)
        query = "$($Query.Trim() -replace ';\s*$', '')`n| take 0"
    } | ConvertTo-Json -Depth 10 -Compress |
        Set-Content -LiteralPath $bodyPath -Encoding utf8NoBOM

    try {
        $output = az rest --method post `
            --url 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' `
            --headers 'Content-Type=application/json' `
            --body "@$bodyPath" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Azure Resource Graph KQL compilation failed for '$Name':`n$output"
        }
    }
    finally {
        Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue
    }
}

foreach ($parser in $contentParity.architecture.requiredParsers) {
    Test-Kql -Name "$parser built-in parser" -Query "$parser | take 0"
}
foreach ($rule in $rules) {
    $query = $rule.query.Trim() -replace ';\s*$', ''
    Test-Kql -Name $rule.displayName -Query "$query`n| take 0"
}
foreach ($hunt in $hunts.queries) {
    $query = $hunt.query.Trim() -replace ';\s*$', ''
    Test-Kql -Name $hunt.displayName -Query "$query`n| take 0"
}
foreach ($record in $workbookQueryRecords) {
    $query = Convert-WorkbookQueryForCompilation -Query $record.Query
    $query = $query.Trim() -replace ';\s*$', ''
    if ($query -match '^\s*Resources\b') {
        Test-ResourceGraphKql -Name $record.Name -Query $query
    }
    else {
        Test-Kql -Name $record.Name -Query "$query`n| take 0"
    }
}

if (-not $SkipIngestionKql) {
    Get-ChildItem (Join-Path $root 'Cribl\validation') -Filter '*.kql' |
        Sort-Object Name |
        ForEach-Object {
            Test-Kql -Name $_.Name -Query (
                Get-Content -LiteralPath $_.FullName -Raw
            )
        }
}

Write-Host 'Pack validation completed successfully.'
