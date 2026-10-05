param(
    [Parameter(Mandatory = $true)][string]$CodePath,
    [ValidateSet('editor', 'game')][string]$Type = 'editor'
)
$ErrorActionPreference = 'Stop'
$connectionPath = Join-Path $env:USERPROFILE '.codex\hastur\connection.json'
$connection = Get-Content -LiteralPath $connectionPath -Raw | ConvertFrom-Json
$headers = @{ Authorization = 'Bearer ' + $connection.auth_token }
$executors = Invoke-RestMethod -Uri ($connection.base_url + '/api/executors') -Headers $headers -TimeoutSec 8
$projectPath = (Split-Path -Parent $PSScriptRoot).Replace('\', '/')
$target = $executors.data | Where-Object { $_.type -eq $Type -and $_.project_path.TrimEnd('/') -eq $projectPath } | Select-Object -First 1
if (-not $target) { throw "No connected $Type executor for this project." }
$body = @{ executor_id = $target.id; type = $Type; code = (Get-Content -LiteralPath $CodePath -Raw -Encoding UTF8) } | ConvertTo-Json -Depth 8
$response = Invoke-RestMethod -Uri ($connection.base_url + '/api/execute') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 35
$response | ConvertTo-Json -Depth 10
if (-not $response.success -or -not $response.data.compile_success -or -not $response.data.run_success) { throw 'Remote Godot operation failed.' }
