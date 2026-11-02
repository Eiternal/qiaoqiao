$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
dotnet run --project windows/QiaoQiao.Tests -c Release -- $PWD.Path
if ($LASTEXITCODE -ne 0) { throw 'Core tests failed' }
dotnet publish windows/QiaoQiao/QiaoQiao.csproj -c Release -r win-x64 --self-contained true -o dist/windows -p:PublishSingleFile=false
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed' }
$process = Start-Process -FilePath "$PWD/dist/windows/QiaoQiao.exe" -ArgumentList '--smoke-test' -PassThru
if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Windows startup timed out' }
if ($process.ExitCode -ne 0) { throw "Windows startup failed: $($process.ExitCode)" }
python scripts/package.py windows
if ($LASTEXITCODE -ne 0) { throw 'Packaging failed' }
