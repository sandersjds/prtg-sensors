###############################################################################
#
# Monthly Bandwidth Calculator
# jsanders@lockstepgroup.com
# May 22, 2014
# - to be aimed at a SNMP traffic sensor measuring bandwidth usage to the WAN
# - calculates monthly total bandwidth utilization (since comcast has caps now)
#
###############################################################################
# script parameters

Param (
	[Parameter(Position=0)]
	[int]$WanBandwidthSensorId
)

# parameter options to require this don't send enough info back to prtg. do it manual!
# is there a better way to handle this?
if (!($WanBandwidthSensorId)) {
	return @"
<prtg>
  <error>1</error>
  <text>Required parameter not specified: please provide PRTG object ID of WAN SNMP traffic sensor</text>
</prtg>
"@
}


###############################################################################
# import/error check the dhcp management module

function Import-MyModule {
	Param(
		[string]$Name
	)
	
	if ( -not (Get-Module -Name $Name) ) {
		if ( Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name } ) {
			Import-Module -Name $Name
			$true # module installed + loaded
		} else {
			$false # module not installed
		}
	}
	else {
		$true # module already loaded
	}
}


$ModuleToImport = "prtgshell"
$ModuleImportSuccess = Import-MyModule $ModuleToImport

if (!($ModuleImportSuccess)) {
	return @"
<prtg>
  <error>1</error>
  <text>$ModuleToImport module not loaded: ensure the module is visible for 32-bit PowerShell</text>
</prtg>
"@
}








###############################################################################
#
# Local PRTG API Access
# February 21, 2014
#
################################################################################
#
# The code below performs tests to determine two sets of data:
#  1) administrator username and creds to access PRTG API
#  2) proper details on how to connect to the core server (IP/hostname, protocol, and port)
#
###############################################################################


# TWO THINGS LEFT TO FINISH / POLISH IN HERE

# 1) do the right test to check for 64-bit paths in the registry remotely ( w/ error handling )
# 2) handle comma-seperated IP strings returned from the core server (just pick one!)


###############################################################################
# step 1: locate the local probe service's registry keys

$PrtgRegistry32bitPath = "HKLM:\SOFTWARE\Paessler\PRTG Network Monitor\Probe"
$PrtgRegistry64bitPath = "HKLM:\SOFTWARE\Wow6432Node\Paessler\PRTG Network Monitor\Probe"

if (Test-Path $PrtgRegistry64bitPath) {
	$PrtgRegistryPath = $PrtgRegistry64bitPath
} elseif (Test-Path $PrtgRegistry32bitPath) {
	$PrtgRegistryPath = $PrtgRegistry32bitPath
} else {
	Set-PrtgError "Unable to locate PRTG registry information folder"
}

# in the configuration, locate the core server it reports to
$PrtgCoreServer = (Get-ItemProperty $PrtgRegistryPath).Server

#$PrtgCoreServer


###############################################################################
# step 2: pull connection data from the core server

# this is going to need to get more clever
$Is64bit = $true
if ($Is64bit) { $64bitString = "Wow6432Node\" } else { $64bitString = "" }

$PrtgCoreRegistryPath = "SOFTWARE\" + $64bitString + "Paessler\PRTG Network Monitor\Server\Core"
$PrtgWebserverRegistryPath = "SOFTWARE\" + $64bitString + "Paessler\PRTG Network Monitor\Server\Webserver"

# make the connection
$TargetHive = [Microsoft.Win32.RegistryHive]::LocalMachine
$RegistryKeyObject = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey($TargetHive,$PrtgCoreServer)

# get the admin username and passhash
try {
	$RegistrySubKey = $RegistryKeyObject.OpenSubKey($PrtgCoreRegistryPath)
} catch {
	"ERROR!"
}

$PRTGAdmin = $RegistrySubKey.GetValue("Admin")
$PrtgPassword = $RegistrySubKey.GetValue("Password")


# get the http connection details
try {
	$RegistrySubKey = $RegistryKeyObject.OpenSubKey($PrtgWebserverRegistryPath)
} catch {
	"ERROR!"
}

$UseIPs = $RegistrySubKey.GetValue("UseIPs")
$UsePorts = $RegistrySubKey.GetValue("UsePorts")
$Ips = $RegistrySubKey.GetValue("Ips")
$Ports = $RegistrySubKey.GetValue("Ports")

# do some logic on the values
# check the IP setting of the webserver

if ($UseIPs -eq "owioSpecIPs") {
	############################
	# NEEDS HANDLING
	# this can actually be a comma-seperated string: 10.10.35.46,10.10.36.3
	############################
	$ConnectionIP = $Ips 
} elseif ($UseIPs -eq "owioAllIPs") {
	$ConnectionIP = $PrtgCoreServer
} else {
	# THIS ISN'T A SUCCESS MODE.
	# this can also mean local access only, which won't work from remote access anyway, even from a probe!
	return "ERROR: wtf is up with your IP setting?"
}

if ($UsePorts -eq "owpoStandardPort") {
	$ConnectionProtocol = "http"
	$ConnectionPort = 80
} elseif ($UsePorts -eq "owpoSpecPorts") {
	$ConnectionProtocol = "http"
	$ConnectionPort = $Ports
} elseif ($UsePorts -eq "owpoSSL") {
	$ConnectionProtocol = "https"
	$ConnectionPort = 443
} elseif ($UsePorts -eq "owpoSpecSSLPorts") {
	$ConnectionProtocol = "https"
	$ConnectionPort = $Ports
} else {
	# THIS ISN'T A SUCCESS MODE.
	return "ERROR: wtf is up with your port setting?"
}

<#
$ConnectionIP
$ConnectionProtocol
$ConnectionPort
$PRTGAdmin
$PrtgPassword
#>

###############################################################################
###############################################################################
###############################################################################

if ($ConnectionProtocol -eq "https") {
	$PrtgConnection = Get-PrtgServer -Server $ConnectionIP -UserName $PRTGAdmin -PassHash $PrtgPassword -Port $ConnectionPort
} else {
	$PrtgConnection = Get-PrtgServer -Server $ConnectionIP -UserName $PRTGAdmin -PassHash $PrtgPassword -Port $ConnectionPort -HttpOnly
}


###############################################################################
###############################################################################
# updated function

function Get-PrtgSensorHistoricData {
	<#
	.SYNOPSIS
		
	.DESCRIPTION
		
	.EXAMPLE
		
	#>

    Param (
        [Parameter(Mandatory=$True,Position=0)]
        [int]$SensorId,

		# really, this should be a (negative) timespan
        [Parameter(Mandatory=$True,Position=1)]
        $StartDate,
		
		[Parameter(Mandatory=$false,Position=2)]
        [string]$ChannelName
    )

    BEGIN {
		$PRTG = $Global:PrtgServerObject
		if ($PRTG.Protocol -eq "https") { HelperSSLConfig }
		
		#$HistoryTimeStart = ((Get-Date).AddDays([System.Math]::Abs($HistoryInDays) * (-1))).ToString("yyyy-MM-dd-HH-mm-ss")
		$HistoryTimeStart = ($StartDate).ToString("yyyy-MM-dd-HH-mm-ss")
		$HistoryTimeEnd = (Get-Date).ToString("yyyy-MM-dd-HH-mm-ss")
		
		# /api/historicdata.xml?id=objectid&avg=0&sdate=2009-01-20-00-00-00&edate=2009-01-21-00-00-00
    }

    PROCESS {
		$url = HelperURLBuilder "historicdata.xml" (
			"&id=$SensorId",
			"&sdate=$HistoryTimeStart",
			"&edate=$HistoryTimeEnd",
			"&avg=86400"
		)
		
        $Global:LastUrl = $Url
        
		$QueryObject = HelperHTTPQuery $url -AsXML
		$Data = $QueryObject.Data
		
		$ValidData = $Data.histdata.item | ? { $_.coverage_raw -ne '0000000000' }

		$DataPoints = @()

		foreach ($v in $ValidData) {
			$Channels = @()
			foreach ($val in $v.value) {
				$NewChannel          = "" | Select Channel,Value
				$NewChannel.Channel  = $val.channel
				$NewChannel.Value    = $val.'#text'
				$Channels           += $NewChannel
			}

			$ChannelsRaw = @()
			foreach ($vr in $v.value_raw) {
				$NewChannel          = "" | Select Channel,Value
				$NewChannel.Channel  = $vr.channel
				$NewChannel.Value    = [double]$vr.'#text'
				$ChannelsRaw        += $NewChannel
			}

			$New             = "" | Select DateTime,Channels,ChannelsRaw
			$New.Datetime    = [DateTime]::Parse(($v.datetime.split("-"))[0]) # need to do a datetime conversion here
			$New.Channels    = $Channels
			$New.ChannelsRaw = $ChannelsRaw

			$DataPoints += $New
		}

	}
	
	END {
		return $DataPoints
    }
}


###############################################################################
###############################################################################
###############################################################################
# helpers from prtgshell (these are only needed because of the function edit above)


function HelperSSLConfig {
	[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
	[System.Net.ServicePointManager]::Expect100Continue = {$true}
	[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::ssl3
}

function HelperHTTPQuery {
	Param (
		[Parameter(Mandatory=$True,Position=0)]
		[string]$URL,
		
		[Parameter(Mandatory=$False)]
		[alias('xml')]
		[switch]$AsXML
	)
	
	try {
		$Response = $null
		$Request = [System.Net.HttpWebRequest]::Create($URL)
		$Response = $Request.GetResponse()
		if ($Response) {
			$StatusCode = $Response.StatusCode.value__
			$DetailedError = $Response.GetResponseHeader("X-Detailed-Error")
		}
	}
	catch {
		$ErrorMessage = $Error[0].Exception.ErrorRecord.Exception.Message
		$Matched = ($ErrorMessage -match '[0-9]{3}')
		if ($Matched) {
			throw ('HTTP status code was {0} ({1})' -f $HttpStatusCode, $matches[0])
		}
		else {
			throw $ErrorMessage
		}

		#$Response = $Error[0].Exception.InnerException.Response
		#$Response.GetResponseHeader("X-Detailed-Error")
	}
	
	if ($Response.StatusCode -eq "OK") {
		$Stream    = $Response.GetResponseStream()
		$Reader    = New-Object IO.StreamReader($Stream)
		$FullPage  = $Reader.ReadToEnd()
		
		if ($AsXML) {
			$Data = [xml]$FullPage
		} else {
			$Data = $FullPage
		}
		
		$Global:LastResponse = $Data
		
		$Reader.Close()
		$Stream.Close()
		$Response.Close()
	} else {
		Throw "Error Accessing Page $FullPage"
	}
	
	$ReturnObject = "" | Select-Object StatusCode,DetailedError,Data
	$ReturnObject.StatusCode = $StatusCode
	$ReturnObject.DetailedError = $DetailedError
	$ReturnObject.Data = $Data
	
	return $ReturnObject
}

function HelperURLBuilder {
	Param (
		[Parameter(Mandatory=$True,Position=0)]
		[string]$Action,
		
		[Parameter(Mandatory=$false,Position=1)]
		[string[]]$QueryParameters,
		
		[Parameter(Mandatory=$false,Position=2)]
		[string]$Protocol = $Global:PrtgServerObject.Protocol,

		[Parameter(Mandatory=$false,Position=3)]
		[string]$Server = $Global:PrtgServerObject.Server,
		
		[Parameter(Mandatory=$false,Position=4)]
		[int]$Port = $Global:PrtgServerObject.Port,
		
		[Parameter(Mandatory=$false,Position=5)]
		[string]$UserName = $Global:PrtgServerObject.UserName,
		
		[Parameter(Mandatory=$false,Position=6)]
		[string]$PassHash = $Global:PrtgServerObject.PassHash
	)

	$PortString = (":" + ($Port))
	
	$Return =
		$Protocol, "://", $Server, $PortString,
		"/api/",$Action,"?",
		"username=$UserName",
		"&passhash=$PassHash" -join ""
	
	$Return += $QueryParameters -join ""
	
	return $Return
}

function HelperFormatTest {
	$URLKeeper = $global:lasturl
	
	$CoreHealthChannels = Get-PrtgSensorChannels 1002
	$HealthPercentage = $CoreHealthChannels | ? {$_.name -eq "Health" }
	$ValuePretty = [int]$HealthPercentage.lastvalue.Replace("%","")
	$ValueRaw = [int]$HealthPercentage.lastvalue_raw
	
	if ($ValueRaw -eq $ValuePretty) {
		$RawFormatError = $false
	} else {
		$RawFormatError = $true
	}
	
	$global:lasturl = $URLKeeper
	
	$StoredConfiguration = $Global:PrtgServerObject | Select-Object *,RawFormatError
	$StoredConfiguration.RawFormatError = $RawFormatError

	$global:PrtgServerObject = $StoredConfiguration
}

function HelperFormatHandler {
    Param (
        [Parameter(Mandatory=$False,Position=0)]
        $InputData
	)
	
	if (!$InputData) { return }
	
	if ($Global:PrtgServerObject.RawFormatError) {
		# format includes the quirk
		return [double]$InputData.Replace("0.",".")
	} else {
		# format doesn't include the quirk, pass it back
		return [double]$InputData
	}
}



###############################################################################
###############################################################################
###############################################################################
# procedural



$DailyBandwidthData = Get-PrtgSensorHistoricData -SensorId $WanBandwidthSensorId -StartDate (Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0) | % {
	$_ | Select-Object DateTime,
						@{n="DailyVolumeGb";e={$_.ChannelsRaw[0].Value / 1GB}},
						@{n="DailyVolume";e={$_.ChannelsRaw[0].Value}}
}


$SummarizedBandwidthData = $DailyBandwidthData | Measure-Object -Sum -Property DailyVolume


###############################################################################
# OUTPUT

$XMLOutput = "<prtg>`n"
$XMLOutput += Set-PrtgResult "Used Bandwidth" $SummarizedBandwidthData.Sum "BytesDisk" -ShowChart 
$XMLOutput += Set-PrtgResult "Days Calculated" $SummarizedBandwidthData.Count "Days" -ShowChart
$XMLOutput += "</prtg>"

$XMLOutput



