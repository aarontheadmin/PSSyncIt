# PSSyncIt

PSSyncIt is a PowerShell module that provides one-way syncing (cloning) of data from one directory tree to another, referred to as Path and Destination. Its operation is comparable to using robocopy.exe with the /mir option.

PSSyncIt compares the folder contents (recursively) within the specified Path against the contents within the specified Destination (see Example Scenario below).

>Note: PowerShell's built-in *Compare-Object* compares the full paths of filesystem objects, resulting in all objects (file paths) being different (C: is different than F:). A common workaround is to use the filesystem object's Name property of Compare-Object. However, this will cause the comparison operation to compare if the Path's file name exists **anywhere** in the Destination, not necessarily in the same tree structure as in the Path.

To use this module, ideally, the controller script (c_PSSyncIt.ps1) and settings file (PSSyncIt.json) should be placed outside the module folder. This allows for module updating without overwriting your script context or sync settings.

The basic structure of PSSyncIt.json contains the source, destination, and log paths used by the controller script. However, settings for email notifications have been added to extend the usability of PSSyncIt. The Notification object in PSSyncIt.json can be ignored or removed and references to Send-EmailNotification in PSSyncIt.ps1 can be commented out or removed.

Currently, only PowerShell Core on Windows is supported.

## Requirements

After the module has been installed:

1. Place the PSSyncIt.ps1 and PSSyncIt.json files in a suitable location (i.e. Documents)
2. Update both/either file to suit your needs.

  **IMPORTANT:** SenderAccountPasswordEncryptedString is used for email authentication for notifications and must contain an EncryptedString:

  ```powershell
  PS />ConvertTo-SecureString 'ABCDEFGH12345678' -AsPlainText -Force | ConvertFrom-SecureString
  4100420043004400450046004700480031003200330034003500360037003800
  ```

  Remember that the EncryptedString is determined by the user token used to generate it. This is important when using something like Task Scheduler to automate PSSyncIt. The user token used to generate the EncryptedString must be the same account used to run the scheduled task.

Updated in PSSyncIt.json:

```json
"SenderAccountPasswordEncryptedString": "4100420043004400450046004700480031003200330034003500360037003800",
```

## Example Scenario:

| Location Type | Path |
| --- | --- |
| Path | C:\Data |
| Destination | F:\Backups\offsite |

Inside C:\Data, there are many files and folders. PSSyncIt will sync the relative structure within C:\Data to F:\Backups\offsite:

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
PS /> Sync-It
```

After the sync, original content has been removed from F:\Backups\offsite and it now contains:
```
F:\Backups\offsite\servers
F:\Backups\offsite\servers\server_A_backup.spf
F:\Backups\offsite\servers\server_B_backup.spf
F:\Backups\offsite\bcp.pdf
...
```

Again, these files did not exist in the source path (C:\Data), so they were removed at the destination (F:\Backups\offsite):
```
~~F:\Backups\offsite\websites~~
~~F:\Backups\offsite\netconfigs\all~~
~~F:\Backups\offsite\photos\conferences~~
~~F:\Backups\offsite\techdocs\baselines~~
~~F:\Backups\offsite\techdocs\inventory\tier1.xlsx~~
...
```

### Example #1

```powershell
PS />Sync-It
```

This example starts the sync, cloning content from the Path and Destination (both specified in PSSyncIt.json).

### Example #2

```powershell
PS />Sync-It -Notify
```

This example starts the sync, cloning the Path contents to the Destination, and sends email notifications when the sync starts and completes. Settings are read from PSSyncIt.json.

### Example #3

```powershell
PS />Sync-It -Resync -Notify
```

This example starts the sync by copying all content from within the Path to the Destination, overwriting pre-existing objects. Email notifications are sent when the sync starts and completes. Using -Resync will cause the sync to take longer.