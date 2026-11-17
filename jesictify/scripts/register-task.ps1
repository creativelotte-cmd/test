# Registers the hourly Windows scheduled task "EumwonDaily-Collect" for the current user.
# Remove with: Unregister-ScheduledTask -TaskName EumwonDaily-Collect -Confirm:$false
$script = Join-Path $PSScriptRoot 'run-all.ps1'
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`"" `
    -WorkingDirectory (Split-Path -Parent $PSScriptRoot)
$start   = (Get-Date).Date.AddHours((Get-Date).Hour + 1).AddMinutes(5)   # next hh:05
$trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
Register-ScheduledTask -TaskName 'EumwonDaily-Collect' -Action $action -Trigger $trigger -Settings $settings `
    -Description 'Eumwon Daily: hourly Hanteo realtime chart collection' -Force | Out-Null
Get-ScheduledTask -TaskName 'EumwonDaily-Collect' | Get-ScheduledTaskInfo | Select-Object TaskName, NextRunTime
