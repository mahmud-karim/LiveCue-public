$ErrorActionPreference = 'Stop'
if (-not (Get-Command docker.exe -CommandType Application -ErrorAction SilentlyContinue)) { throw 'Docker Desktop is required.' }
function Test-DockerEngine {
    $ErrorActionPreference = 'Continue'
    docker info --format '{{.ServerVersion}}' *> $null
    return ($LASTEXITCODE -eq 0)
}
# No engine means no live GPU container to unload. Do not start Docker to stop it.
if (-not (Test-DockerEngine)) { return }
$existing = docker ps -a --filter 'name=^/livecue-asr-lab$' --format '{{.Names}}'
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the local model.' }
if ($existing -ne 'livecue-asr-lab') { return }
$labels = docker inspect --format '{{json .Config.Labels}}' livecue-asr-lab | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $labels.'com.livecue.component' -ne 'asr-lab') { throw 'Container is not owned by LiveCue. Refusing to stop it.' }
try { $health = Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 2 } catch { $health = $null }
if ($health -and $health.busy) { throw 'An ASR session is active. Stop it before unloading the model.' }
docker stop --timeout 15 livecue-asr-lab | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not stop the local model.' }
Write-Host 'PC model stopped. Model weights and Docker images are unchanged.'
