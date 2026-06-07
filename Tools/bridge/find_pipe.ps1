# find_pipe.ps1 — Debug helper: list xEdit-related named pipes
#
# Usage: powershell.exe -ExecutionPolicy Bypass -File find_pipe.ps1

$pipes = [System.IO.Directory]::GetFiles('\\.\pipe\')
$found = $pipes | Where-Object { $_ -match 'xEdit|automation|SSEEdit' }
if ($found) {
    Write-Host "FOUND: $found"
} else {
    Write-Host "Not found in $($pipes.Count) pipes."
}
