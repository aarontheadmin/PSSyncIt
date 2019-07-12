# PSPathSync
PSPathSync is a PowerShell module that provides one-way syncing (cloning) of data from one directory tree to another, referred to as ReferenceDirectory and DifferenceDirectory. Its operation is comparable to using robocopy.exe with the /mir option. The customizable PSPathSync.json file contains settings for paths, email, and notifications for use with the Sync-RelativePath controller script. Currently, only PowerShell Core on Windows is supported.

PSPathSync compares the (relative) directory tree within the specified the ReferenceDirectory against the tree within the specified DifferenceDirectory. For example, the relative tree within C:\Data will be compared to the relative tree within F:\Backups\offsite (example below).

>Note: PowerShell's built-in *Compare-Object* compares the full paths, resulting in all objects (paths) being different (C: is different than F:). A common workaround is to use the (file) Name property of Compare-Object. However, this will cause the comparison operation to compare if the ReferenceObject (file) Name exists **anywhere** in the DifferenceObject, not necessarily in the same tree structure as in the ReferenceObject.

## Requirements
After the module has been installed:
1. Place the PSPathSync.json file in a suitable location (i.e. Documents)
2. In the module base folder, update the PSPathSync.config file to contain the path where PSPathSync.json exists
3. Update PSPathSync.json to suit your needs (some changes may require modification of the Sync-RelativePath controller script)

  **IMPORTANT:** SenderAccountPasswordSecureString is used for email authentication for notifications and must contain a SecureString:
  ```powershell
  PS />ConvertTo-SecureString 'ABCDEFGH12345678' -AsPlainText -Force | ConvertFrom-SecureString
  4100420043004400450046004700480031003200330034003500360037003800
  ```
  
Updated in PSPathSync.json:
```json
"SenderAccountPasswordSecureString": "4100420043004400450046004700480031003200330034003500360037003800",
```

## Example Scenario:

| Location Type | Path |
| --- | --- |
| ReferenceDirectory | C:\Data |
| DifferenceDirectory | F:\Backups\offsite |

Inside C:\Data, there are many files and folders. PSPathSync will sync the relative structure within C:\Data to F:\Backups\offsite:

Original contents of C:\Data:
```
C:\Data\servers
C:\Data\servers\server_A_backup.spf
C:\Data\servers\server_B_backup.spf
C:\Data\bcp.pdf
...
```

Original contents of F:\
```
F:\Backups\offsite\websites
F:\Backups\offsite\netconfigs\all
F:\Backups\offsite\photos\conferences
F:\Backups\offsite\techdocs\baselines
F:\Backups\offsite\techdocs\inventory\tier1.xlsx
...
```

Run sync:
```powershell
PS /> Sync-RelativePath -ReferenceDirectory C:\Data -DifferenceDirectory F:\Backups\offsite
```

After sync, original content has been removed from F:\Backups\offsite and it now contains:
```
F:\Backups\offsite\servers
F:\Backups\offsite\servers\server_A_backup.spf
F:\Backups\offsite\servers\server_B_backup.spf
F:\Backups\offsite\bcp.pdf
...
```

### Example #1
```powershell
PS />Sync-RelativePath
```
This example starts the sync, cloning content from the ReferenceDirectory and DifferenceDirectory (both specified in PSPathSync.json).

### Example #2
```powershell
PS />Sync-RelativePath -Notify
```
This example starts the sync (cloning the ReferenceDirectory contents to the DifferenceDirectory) and sends email notifications when the sync starts and completes. Settings are read from PSPathSync.json.

### Example #3
```powershell
PS />Sync-RelativePath -Resync -Notify
```
This example starts the sync by re-copying all content from the ReferenceDirectory to the DifferenceDirectory, overwriting all objects, including anything previously-synced. Email notifications are sent when the sync starts and completes. Using -Resync will cause the sync to take longer.
