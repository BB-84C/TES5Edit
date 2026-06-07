# bridge.ps1 — HTTP → Named Pipe bridge for BB-84C xEdit automation
#
# Runs on Windows side as background process.
# Listens on HTTP 127.0.0.1:42423, translates requests to xEdit's
# named pipe (\\.\pipe\xedit-{PID}).
#
# Usage from WSL:
#   1. Start xEdit with -automation-serve
#   2. powershell.exe -Command "Start-Process powershell.exe -ArgumentList '-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File','<path>\bridge.ps1'"
#   3. curl --noproxy '*' -s http://127.0.0.1:42423/system.ping
#
# IMPORTANT: $PID is a PowerShell reserved variable — use $xePid instead.

$pipePrefix = "xedit-"
$httpPort = 42423

function Get-XEditPid {
    $p = Get-Process -Name 'xEdit64' -ErrorAction SilentlyContinue
    if ($p) { return $p.Id }
    return 0
}

function Send-PipeRequest($json) {
    $xePid = Get-XEditPid
    if ($xePid -eq 0) { throw "xEdit not running" }
    $pipeName = "$pipePrefix$xePid"

    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(5000)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $pipe.Write($bytes, 0, $bytes.Length)
    $pipe.Flush()
    $pipe.WaitForPipeDrain()

    $reader = New-Object System.IO.StreamReader($pipe, [System.Text.Encoding]::UTF8)
    $resp = $reader.ReadToEnd()
    $reader.Close()
    $pipe.Close()
    return $resp
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$httpPort/")
$listener.Start()
Write-Host "Bridge listening on http://127.0.0.1:$httpPort"

while ($true) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response

    try {
        $path = $req.Url.AbsolutePath.TrimStart('/')
        $cmd = $path
        $args = @{}
        if ($req.QueryString.Count -gt 0) {
            foreach ($k in $req.QueryString.AllKeys) { if ($k) { $args[$k] = $req.QueryString[$k] } }
        }
        if ($req.HasEntityBody) {
            $sr = New-Object System.IO.StreamReader($req.InputStream)
            $body = $sr.ReadToEnd(); $sr.Close()
            try { $bd = $body | ConvertFrom-Json; foreach ($p in $bd.PSObject.Properties) { $args[$p.Name] = $p.Value } } catch {}
        }

        $payload = @{ command = $cmd; args = $args } | ConvertTo-Json -Compress -Depth 3
        Write-Host "REQ: $payload"
        $result = Send-PipeRequest $payload

        $respBytes = [System.Text.Encoding]::UTF8.GetBytes($result)
        $res.StatusCode = 200
        $res.ContentType = "application/json; charset=utf-8"
        $res.OutputStream.Write($respBytes, 0, $respBytes.Length)
    } catch {
        $err = @{ error = $_.Exception.Message } | ConvertTo-Json
        $errBytes = [System.Text.Encoding]::UTF8.GetBytes($err)
        $res.StatusCode = 500
        $res.ContentType = "application/json"
        $res.OutputStream.Write($errBytes, 0, $errBytes.Length)
    }
    $res.Close()
}
