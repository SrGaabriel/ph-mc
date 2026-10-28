# Purdue Hackers Minecraft installer for Windows. From Win+R or a terminal:
#   powershell -c "irm https://minecraft.phack.sh/install.ps1 | iex"
# Files fetched this way carry no "downloaded from the internet" mark, so SmartScreen stays quiet.
# Running it again updates the launcher and keeps accounts, settings and worlds.
& {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue' # the progress bar makes Invoke-WebRequest crawl on PowerShell 5
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

  $name = 'Purdue Hackers Minecraft'
  $url = 'https://github.com/srgaabriel/ph-mc/releases/latest/download/ph-mc-windows.zip'
  $dir = Join-Path $env:LOCALAPPDATA "Programs\$name"
  $exe = Join-Path $dir 'freesmlauncher.exe'
  $play = '--launch "Purdue Hackers"'
  $tmp = Join-Path ([IO.Path]::GetTempPath()) "ph-mc-$([guid]::NewGuid())"

  try {
    Write-Host "Downloading $name..."
    New-Item -ItemType Directory -Force $tmp | Out-Null
    Invoke-WebRequest $url -OutFile "$tmp\ph-mc.zip" -UseBasicParsing
    Expand-Archive "$tmp\ph-mc.zip" "$tmp\x"
    $src = "$tmp\x\$name"

    Get-Process freesmlauncher -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$dir\*" } | Stop-Process -Force
    New-Item -ItemType Directory -Force $dir | Out-Null
    # Portable mode keeps accounts, settings and the instance in this folder: keep the player's copies
    $keep = 'instances', 'freesmlauncher.cfg'
    Get-ChildItem $src |
      Where-Object { -not ($keep -contains $_.Name -and (Test-Path (Join-Path $dir $_.Name))) } |
      ForEach-Object { Copy-Item $_.FullName $dir -Recurse -Force }
    $jar = 'instances\Purdue Hackers\minecraft\packwiz-installer-bootstrap.jar'
    Copy-Item "$src\$jar" "$dir\$jar" -Force

    $shell = New-Object -ComObject WScript.Shell
    $link = {
      param($path, $arguments)
      $s = $shell.CreateShortcut($path)
      $s.TargetPath = $exe
      $s.Arguments = $arguments
      $s.WorkingDirectory = $dir
      $s.IconLocation = $exe
      $s.Save()
    }
    $menu = [Environment]::GetFolderPath('Programs')
    & $link "$menu\$name.lnk" $play
    & $link "$menu\Purdue Hackers Launcher.lnk" ''
    & $link "$([Environment]::GetFolderPath('Desktop'))\$name.lnk" $play

    Write-Host "Installed to $dir. Starting the game..."
    Write-Host "For the launcher window, open 'Purdue Hackers Launcher' from the Start menu."
    Start-Process $exe -ArgumentList $play -WorkingDirectory $dir
  } catch {
    Write-Host "Install failed: $_" -ForegroundColor Red
    # From Win+R the window closes on its own, so hold it open long enough to read the error
    Read-Host 'Press Enter to close'
  } finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}
