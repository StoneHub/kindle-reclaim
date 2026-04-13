param(
    [ValidateSet("ensure", "status", "stop")]
    [string]$Action = "ensure",
    [string]$Workspace = "C:\Users\monro\Codex\Kindle reclaim",
    [string]$BindAddress = "0.0.0.0",
    [int]$Port = 8765
)

$ErrorActionPreference = "Stop"

function Get-ListenerConnection {
    param([int]$LocalPort)

    return Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function Get-ListenerProcess {
    param([int]$LocalPort)

    $connection = Get-ListenerConnection -LocalPort $LocalPort
    if (-not $connection) {
        return $null
    }

    return Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
}

$workspaceResolved = (Resolve-Path -LiteralPath $Workspace).Path
$artifactsDir = Join-Path $workspaceResolved "artifacts"
$outLog = Join-Path $artifactsDir "wifi-http.out.log"
$errLog = Join-Path $artifactsDir "wifi-http.err.log"
$pidFile = Join-Path $artifactsDir "wifi-http.pid"

New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null

switch ($Action) {
    "status" {
        $process = Get-ListenerProcess -LocalPort $Port
        if (-not $process) {
            Write-Output "state=stopped port=$Port"
            return
        }

        Write-Output "state=running pid=$($process.Id) port=$Port host=$BindAddress"
        Write-Output "logs_out=$outLog"
        Write-Output "logs_err=$errLog"
        return
    }

    "stop" {
        $process = Get-ListenerProcess -LocalPort $Port
        if (-not $process -and (Test-Path -LiteralPath $pidFile)) {
            $pidText = (Get-Content -LiteralPath $pidFile -Raw).Trim()
            if ($pidText -match '^\d+$') {
                $process = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
            }
        }

        if (-not $process) {
            Write-Output "state=stopped port=$Port"
            Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
            return
        }

        Stop-Process -Id $process.Id -Force
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        Write-Output "state=stopped pid=$($process.Id) port=$Port"
        return
    }

    "ensure" {
        $process = Get-ListenerProcess -LocalPort $Port
        if ($process) {
            [System.IO.File]::WriteAllText($pidFile, "$($process.Id)`n", [System.Text.Encoding]::ASCII)
            Write-Output "state=running pid=$($process.Id) port=$Port host=$BindAddress"
            Write-Output "logs_out=$outLog"
            Write-Output "logs_err=$errLog"
            return
        }

        $serveArgs = @(
            ".\skills\kindle-billboard\scripts\publish_kindle_billboard.py",
            "serve",
            "--host",
            $BindAddress,
            "--port",
            "$Port"
        )

        $started = Start-Process -FilePath python -ArgumentList $serveArgs -WorkingDirectory $workspaceResolved `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru

        Start-Sleep -Seconds 2

        $listener = Get-ListenerProcess -LocalPort $Port
        if (-not $listener) {
            throw "Host serve process did not start listening on port $Port."
        }

        [System.IO.File]::WriteAllText($pidFile, "$($listener.Id)`n", [System.Text.Encoding]::ASCII)
        Write-Output "state=running pid=$($listener.Id) port=$Port host=$BindAddress"
        Write-Output "logs_out=$outLog"
        Write-Output "logs_err=$errLog"
        return
    }
}
