# General config
$sourcedir="d:\backups\enterprise-pdm"
$datestamp=Get-Date -UFormat "%Y_%m_%d"
$backupfilename="{0}\pdmvaults-{1}.zip" -f $sourcedir,$datestamp

# AWS S3 config
$bucket="corp-backup.jauntvr.com"       # Target bucket
$profilename="backupscorp"              # Prestored access and secret to use
$region="us-west-1"
$s3targetfolder="enterprise-pdm"

Add-Type -A System.IO.Compression.FileSystem

"Removing existing backups"
Remove-Item $sourcedir\pdmvaults*.zip

"Backup file is $backupfilename"

[IO.Compression.ZipFile]::CreateFromDirectory('d:\pdm-data',$backupfilename)

# All backups except for PDM Archive Server settings
foreach ($f in Get-ChildItem -Path $sourcedir\*$datestamp* -file) {
$basename=$f.Name
Write-S3Object -bucketname $bucket -ProfileName $profilename -Region $region -file $f -key "$s3targetfolder/$basename"
}

# PDM Archive Server settings
# Always get written locally as Backup.dat so add datestamp when we copy it to S3
Write-S3Object -bucketname $bucket -ProfileName $profilename -Region $region -file $sourcedir\Backup.dat -key "$s3targetfolder/Backup-$datestamp.dat"
