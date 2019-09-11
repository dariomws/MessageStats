###############################################################################
#
#  Written by **Rob Campbell** - 03/02/2011 - https://devblogs.microsoft.com/scripting/use-powershell-to-track-email-messages-in-exchange-server/
#  Updated by **mjolinor** - 02/24/2011
#  Updated by Josh M. Bryant 10/8/2014 to work with Exchange 2013
#  Fixed some stuff by MRoth 04/04/2019 
#
#  Maintained by mroth [msft] 
#  source https://github.com/msftmroth/MessageStats
#  docs 
#
###############################################################################


#requires -version 2.0

param(
    # Days to analyze in the past  
    [Parameter(	Mandatory=$false,
				Position = 0,
				HelpMessage = "Days to analyze in the past (Default 1 (Yesterday) 2 the day before yesterday and so on... )")]
	[ValidatePattern("[0-9]")]
    [int] $AnalyzeDay = 1
	)

$today = [DateTime]::Today
$startdate = $today.AddDays(-$AnalyzeDay)
$stopdate = $startdate.AddHours(24).AddMilliseconds(-1)
$rundate = $($today.adddays(-$AnalyzeDay)).toshortdatestring()

Write-Host "Doing analysis for " + $rundate 

$outfile_date = ([datetime]$AnalyzeDate).tostring("yyyy_MM_dd")
$outfile = "email_stats_" + $outfile_date + ".csv"

$dl_stat_file = "DL_stats.csv"

$accepted_domains = Get-AcceptedDomain |% {$_.domainname.domain}
[regex]$dom_rgx = "`(?i)(?:" + (($accepted_domains |% {"@" + [regex]::escape($_)}) -join "|") + ")$"

$mbx_servers = Get-ExchangeServer |? {$_.serverrole -match "Mailbox"}|% {$_.fqdn}
[regex]$mbx_rgx = "`(?i)(?:" + (($mbx_servers |% {"@" + [regex]::escape($_)}) -join "|") + ")\>$"

$msgid_rgx = "^\<.+@.+\..+\>$"

$hts = Get-ExchangeServer |? {$_.IsHubTransportServer -eq $True} |% {$_.Name}

$exch_addrs = @{}

$msgrec = @{}
$bytesrec = @{}

$msgrec_exch = @{}
$bytesrec_exch = @{}

$msgrec_smtpext = @{}
$bytesrec_smtpext = @{}

$total_msgsent = @{}
$total_bytessent = @{}
$unique_msgsent = @{}
$unique_bytessent = @{}

$total_msgsent_exch = @{}
$total_bytessent_exch = @{}
$unique_msgsent_exch = @{}
$unique_bytessent_exch = @{}

$total_msgsent_smtpext = @{}
$total_bytessent_smtpext = @{}
$unique_msgsent_smtpext=@{}
$unique_bytessent_smtpext = @{}

$dl = @{}


$obj_table = {
@"
Date = $rundate
User = $($address.split("@")[0])
Domain = $($address.split("@")[1])
Sent Total = $(0 + $total_msgsent[$address])
Sent MB Total = $("{0:F2}" -f $($total_bytessent[$address]/1mb))
Received Total = $(0 + $msgrec[$address])
Received MB Total = $("{0:F2}" -f $($bytesrec[$address]/1mb))
Sent Internal = $(0 + $total_msgsent_exch[$address])
Sent Internal MB = $("{0:F2}" -f $($total_bytessent_exch[$address]/1mb))
Sent External = $(0 + $total_msgsent_smtpext[$address])
Sent External MB = $("{0:F2}" -f $($total_bytessent_smtpext[$address]/1mb))
Received Internal = $(0 + $msgrec_exch[$address])
Received Internal MB = $("{0:F2}" -f $($bytesrec_exch[$address]/1mb))
Received External = $(0 + $msgrec_smtpext[$address])
Received External MB = $("{0:F2}" -f $($bytesrec_smtpext[$address]/1mb))
Sent Unique Total = $(0 + $unique_msgsent[$address])
Sent Unique MB Total = $("{0:F2}" -f $($unique_bytessent[$address]/1mb))
Sent Internal Unique  = $(0 + $unique_msgsent_exch[$address]) 
Sent Internal Unique MB = $("{0:F2}" -f $($unique_bytessent_exch[$address]/1mb))
Sent External  Unique = $(0 + $unique_msgsent_smtpext[$address])
Sent External Unique MB = $("{0:F2}" -f $($unique_bytessent_smtpext[$address]/1mb))
"@
}

$props = $obj_table.ToString().Split("`n")|% {if ($_ -match "(.+)="){$matches[1].trim()}}

$stat_recs = @()

function time_pipeline {
param ($increment  = 1000)
begin{$i=0;$timer = [diagnostics.stopwatch]::startnew()}
process {
    $i++
    if (!($i % $increment)){Write-host "`rProcessed $i in $($timer.elapsed.totalseconds) seconds" -nonewline}
    $_
    }
end {
	write-host "`rProcessed $i log records in $($timer.elapsed.totalseconds) seconds"
	Write-Host "   Average rate: $([int]($i/$timer.elapsed.totalseconds)) log recs/sec."
	}
}

foreach ($ht in $hts){

	Write-Host "`nStarted processing $ht"

	get-messagetrackinglog -Server $ht -Start $startdate -End $stopdate -resultsize unlimited |
	time_pipeline |%{
	
	
	if ($_.eventid -eq "DELIVER" -and $_.source -eq "STOREDRIVER"){
	
		if ($_.messageid -match $mbx_rgx -and $_.sender -match $dom_rgx) {
			
			$total_msgsent[$_.sender] += $_.recipientcount
			$total_bytessent[$_.sender] += ($_.recipientcount * $_.totalbytes)
			$total_msgsent_exch[$_.sender] += $_.recipientcount
			$total_bytessent_exch[$_.sender] += ($_.totalbytes * $_.recipientcount)
		
			foreach ($rcpt in $_.recipients){
			$exch_addrs[$rcpt] ++
			$msgrec[$rcpt] ++
			$bytesrec[$rcpt] += $_.totalbytes
			$msgrec_exch[$rcpt] ++
			$bytesrec_exch[$rcpt] += $_.totalbytes
			}
			
		}
		
		else {
			if ($_.messageid -match $messageid_rgx){
					foreach ($rcpt in $_.recipients){
						$exch_addrs[$rcpt] ++
						$msgrec[$rcpt] ++
						$bytesrec[$rcpt] += $_.totalbytes
						$msgrec_smtpext[$rcpt] ++
						$bytesrec_smtpext[$rcpt] += $_.totalbytes
					}
				}
		
			}
				
	}
	
	
	if ($_.eventid -eq "RECEIVE" -and $_.source -eq "STOREDRIVER"){
		$exch_addrs[$_.sender] ++
		$unique_msgsent[$_.sender] ++
		$unique_bytessent[$_.sender] += $_.totalbytes
		
			if ($_.recipients -match $dom_rgx){
				$unique_msgsent_exch[$_.sender] ++
				$unique_bytessent_exch[$_.sender] += $_.totalbytes
				}

			if ($_.recipients -notmatch $dom_rgx){
				$ext_count = ($_.recipients -notmatch $dom_rgx).count
				$unique_msgsent_smtpext[$_.sender] ++
				$unique_bytessent_smtpext[$_.sender] += $_.totalbytes
			    $total_msgsent[$_.sender] += $ext_count
				$total_bytessent[$_.sender] += ($ext_count * $_.totalbytes)
				$total_msgsent_smtpext[$_.sender] += $ext_count
 			    $total_bytessent_smtpext[$_.sender] += ($ext_count * $_.totalbytes)
				}
                               
			
		}
		
	if ($_.eventid -eq "expand"){
		$dl[$_.relatedrecipientaddress] ++
		}
	}	 
	
}

foreach ($address in $exch_addrs.keys){

$stat_rec = (new-object psobject -property (ConvertFrom-StringData (&$obj_table)))
$stat_recs += $stat_rec | select $props
}

$stat_recs | export-csv $outfile -notype 

if (Test-Path $dl_stat_file){
	$DL_stats = Import-Csv $dl_stat_file
	$dl_list = $dl_stats |% {$_.address}
	}
	
else {
	$dl_list = @()
	$DL_stats = @()
	}


$DL_stats |% {
	if ($dl[$_.address]){
		if ([datetime]$_.lastused -le [datetime]$rundate){ 
			$_.used = [int]$_.used + [int]$dl[$_.address]
			$_.lastused = $rundate
			}
		}
}
	
$dl.keys |% {
	if ($dl_list -notcontains $_){
		$new_rec = "" | select Address,Used,Since,LastUsed
		$new_rec.address = $_
		$new_rec.used = $dl[$_]
		$new_rec.Since = $rundate
		$new_rec.lastused = $rundate
		$dl_stats += @($new_rec)
	}
}

$dl_stats | Export-Csv $dl_stat_file -NoTypeInformation -force


Write-Host "`nRun time was $(((get-date) - $today).totalseconds) seconds."
Write-Host "Email stats file is $outfile"
Write-Host "DL usage stats file is $dl_stat_file"


