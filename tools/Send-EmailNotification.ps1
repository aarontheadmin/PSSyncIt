function Send-EmailNotification {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Subject,

        [Parameter(Mandatory)]
        [string]$MessageBody
    )

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 # modern HTTPS requests
    [pscustomobject]                 $notification     = Get-PSPathSyncConfiguration | Select-Object -ExpandProperty Notification
    [string]                         $senderEmail      = $notification.SenderEmail

    New-Variable -Name secureString -Visibility Private -Value ($notification.SenderAccountPasswordSecureString | ConvertTo-SecureString)

    [pscredential]$credential = New-Object System.Management.Automation.PSCredential -ArgumentList $senderEmail, $secureString

    Remove-Variable -Name secureString

    [hashtable]$params = @{
        To         = [string]$notification.RecipientAddress
        SmtpServer = [string]$notification.SmtpServer
        Credential = $credential
        UseSsl     = [bool]$notification.UseSSL
        Subject    = $subject
        Port       = [uint16]$notification.SenderPort
        Body       = $MessageBody
        From       = $senderEmail
        BodyAsHtml = $true
    } # hashtable

    Send-MailMessage @params

    Remove-Variable credential, notification, params, senderEmail
} # function