# Installs (or reinstalls) the Windows scheduled task that runs weekly_update.ps1.
#
# It runs every day at 10:00 (and soon after the PC wakes if it missed that time). Most days it
# finds nothing new and does nothing; once a week's games are all final and loaded, it publishes
# that week's cards.
#
# Install:    powershell -ExecutionPolicy Bypass -File pipeline\install_weekly_task.ps1
# Run now:    Start-ScheduledTask -TaskName "Gridiron Dynasty card update"
# Remove:     Unregister-ScheduledTask -TaskName "Gridiron Dynasty card update" -Confirm:$false

$name = "Gridiron Dynasty card update"
$script = Join-Path $PSScriptRoot "weekly_update.ps1"

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
	-Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`"" `
	-WorkingDirectory (Split-Path -Parent $PSScriptRoot)
$trigger = New-ScheduledTaskTrigger -Daily -At 10:00
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
	-ExecutionTimeLimit (New-TimeSpan -Minutes 30) -RunOnlyIfNetworkAvailable
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
	-Description "Builds new Gridiron Dynasty cards from the latest real stats and publishes docs/cards.json." -Force | Out-Null

$task = Get-ScheduledTask -TaskName $name
"Installed '$name' (state: $($task.State)). Next run: $((Get-ScheduledTaskInfo -TaskName $name).NextRunTime)"
