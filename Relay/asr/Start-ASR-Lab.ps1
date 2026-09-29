param([ValidateSet('nemotron','qwen3')][string]$Model = 'nemotron', [switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$container = 'livecue-asr-lab'
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Desktop is required.' }
docker info --format '{{.ServerVersion}}' *> $null
if ($LASTEXITCODE -ne 0) { throw 'Start Docker Desktop first, then run this launcher again.' }
$existing = docker ps -a --filter "name=^/$container`$" --format '{{.Names}}'
if ($existing -eq $container) {
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 2
    } catch { $health = $null }
    if ($health -and $health.busy) { throw 'An ASR session is active. Stop it before switching models.' }
    if ($health -and $health.ready -and $health.model -eq $Model -and $health.relayProtocol -eq 1) {
        if (-not $NoBrowser) { Start-Process 'http://127.0.0.1:8765' }
        return
    }
    $labels = docker inspect --format '{{json .Config.Labels}}' $container | ConvertFrom-Json
    $owner = $labels.'com.livecue.component'
    if ($owner -ne 'asr-lab') { throw 'Container name belongs to another workload; refusing to replace it.' }
    docker stop --time 15 $container | Out-Null
    docker rm $container | Out-Null
}
$models = Join-Path $root "private\models\$Model"
if (-not (Test-Path -LiteralPath (Join-Path $models 'config.json'))) { throw 'Model weights have not been downloaded.' }
docker run -d --name $container --label com.livecue.component=asr-lab --gpus all --shm-size 1g --cap-drop ALL --security-opt no-new-privileges --pids-limit 512 -e VLLM_NO_USAGE_STATS=1 -e DO_NOT_TRACK=1 -e GRADIO_ANALYTICS_ENABLED=False -p 127.0.0.1:8765:8765 --mount "type=bind,source=$models,target=/models,readonly" --mount "type=bind,source=$root,target=/app,readonly" "livecue-asr-${Model}:0.1" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not start the local model container.' }
Write-Host "Loading $Model on the GPU. This can take a few minutes on first start."
$deadline = (Get-Date).AddMinutes(8)
do {
    $state = docker inspect --format '{{.State.Running}}' $container
    if ($state -ne 'true') { docker logs --tail 40 $container; throw 'Model service stopped during initialization.' }
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 2
        if ($health.ready -and $health.model -eq $Model) {
            Write-Host "Ready: http://127.0.0.1:8765 ($Model)"
            if (-not $NoBrowser) { Start-Process 'http://127.0.0.1:8765' }
            return
        }
    } catch { }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
throw 'Model is still starting. Inspect: docker logs --tail 40 livecue-asr-lab'
