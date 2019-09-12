Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Install-Module -Force OpenSSHUtils -Scope AllUsers -Confirm:$False
Start-Service sshd 
Set-Service -Name sshd -StartupType 'Automatic'
Get-NetFirewallRule -Name *ssh* | Set-NetFirewallRule -Enabled True -Direction Inbound -Action Allow
mkdir $env:USERPROFILE/.ssh
New-Item $env:USERPROFILE/.ssh/authorized_keys
#$ConfirmPreference = 'None'; Repair-AuthorizedKeyPermission $env:USERPROFILE\.ssh\authorized_keys

Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
Invoke-WebRequest -Uri https://aka.ms/wsl-ubuntu-1804 -OutFile Ubuntu.appx -UseBasicParsing
Rename-Item ./Ubuntu.appx ./Ubuntu.zip
Expand-Archive ./Ubuntu.zip C:/WSL/Ubuntu
C:/WSL/Ubuntu/ubuntu1804.exe install
$userenv = [System.Environment]::GetEnvironmentVariable("Path", "User")
[System.Environment]::SetEnvironmentVariable("PATH", "$env:UserProfile\Ubuntu;" + $userenv, "User")
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\WSL\Ubuntu\ubuntu1804.exe" -PropertyType String -Force

RefreshEnv
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
if (Get-Item 'HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' -ErrorAction Ignore){
    Write-Output "Reboot Required"
}
else {
    Write-Output "No Reboot Required"
}
