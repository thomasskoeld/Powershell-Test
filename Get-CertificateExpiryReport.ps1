param(
    [string]$ServerListPath = 'C:\Scripts\Antura\Servers\allServers.txt',
    [int]$DaysToExpiration = 45,
    [string]$SmtpServer = 'smtp.saabgroup.com',
    [string]$EmailTo = 'thomas.skold1@saabgroup.com',
    [string]$ReportOutputPath = 'C:\PSTemp\Certs.htm'
)

$servers = Import-Csv -Path $ServerListPath

foreach ($server in $servers) {
    $option = New-PSSessionOption -IncludePortInSPN
    $psSession = New-PSSession -ComputerName $server.name -SessionOption $option

    try {
        Invoke-Command -Session $psSession -ArgumentList $DaysToExpiration, $SmtpServer, $EmailTo, $ReportOutputPath -ScriptBlock {
            param(
                [int]$DaysToExpiration,
                [string]$SmtpServer,
                [string]$EmailTo,
                [string]$ReportOutputPath
            )

            $expirationDate = (Get-Date).AddDays($DaysToExpiration)
            $certs = Get-ChildItem -Path Cert:\LocalMachine\My -Recurse
            $today = (Get-Date).Date
            $emailFrom = "$env:COMPUTERNAME@saabgroup.com"
            $currentDir = (Get-Location).Path

            $expiredBody = @(
                $certs |
                    Where-Object { $_.NotAfter -lt $today } |
                    Sort-Object -Property NotAfter |
                    Select-Object -Property Subject, NotAfter, Issuer
            )

            $expiringBody = @(
                $certs |
                    Where-Object { $_.NotAfter -gt $today -and $_.NotAfter -lt $expirationDate } |
                    Sort-Object -Property NotAfter |
                    Select-Object -Property Subject, NotAfter, Issuer
            )

            if ($expiringBody.Count -lt 1 -and $expiredBody.Count -lt 1) {
                return
            }

            $head = @'
<style>
TABLE{width: 100%;border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
TH{border-width: 1px;padding: 5px;border-style: solid;border-color: black;}
TD{border-width: 1px;padding: 5px;border-style: solid;border-color: black;}
</style>
'@

            $extendExpiredBody = if ($expiredBody.Count -gt 0) {
                $expiredBody | ConvertTo-Html -Head $head
            } else {
                ''
            }

            $extendExpiringBody = if ($expiringBody.Count -gt 0) {
                $expiringBody | ConvertTo-Html -Head $head
            } else {
                ''
            }

            $emailExpiringBody = "Listed below are certificates that are about to expire in the next $DaysToExpiration days on $env:COMPUTERNAME"
            $emailExpiredBody = if ($expiredBody.Count -gt 0) {
                "<br>Listed below are certificates that have expired on $env:COMPUTERNAME"
            } else {
                ''
            }

            $emailBody = $emailExpiringBody + $extendExpiringBody + $emailExpiredBody + $extendExpiredBody
            $emailBody += "<br>Report last updated on $($today.ToLongDateString()).<br>Script hosted on server $env:COMPUTERNAME.<br>Script path: $currentDir"
            $emailSubject = "Certificates that are expired or expiring within the next $DaysToExpiration days on $env:COMPUTERNAME"

            $sendMailMessageProps = @{
                From       = $emailFrom
                To         = $EmailTo
                Subject    = $emailSubject
                Body       = $emailBody
                BodyAsHtml = $true
                SmtpServer = $SmtpServer
            }

            Send-MailMessage @sendMailMessageProps

            $reportDir = Split-Path -Path $ReportOutputPath -Parent
            if (-not (Test-Path -Path $reportDir)) {
                New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
            }
            $emailBody | Out-File -Path $ReportOutputPath -Force
        }
    }
    finally {
        if ($psSession) {
            Remove-PSSession -Session $psSession
        }
    }
}
