# dumb whois
# this will probably barely work elsewhere

# step 1: install sysinternals whois in the path
# http://technet.microsoft.com/en-us/sysinternals/bb897435.aspx

# step 2: install prtgshell

###############################################################################
# script parameters

Param (
	[Parameter(Position=0)]
	[string]$DomainName
)

# parameter options to require this don't send enough info back to prtg. do it manual!
# is there a better way to handle this?
if (!($DomainName)) {
	return @"
<prtg>
  <error>1</error>
  <text>Required parameter not specified: please provide valid domain and TLD</text>
</prtg>
"@
}

###############################################################################
# load the prtgshell module

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

$ModuleImportSuccess = Import-MyModule PrtgShell

if (!($ModuleImportSuccess)) {
	return @"
<prtg>
  <error>1</error>
  <text>PrtgShell module not loaded: ensure the module is visible for 32-bit PowerShell</text>
</prtg>
"@
}


###############################################################################
# procedural


$FullTextWhois = & whois $DomainName

function HandleUSWHOISDateTime($WhoisQueryText,$MatchString) {
	$SplitString = ($WhoisQueryText -match $MatchString) -split "  "
	$SplitString = ($SplitString[$SplitString.Length - 1]).Trim()
	$SplitString = $SplitString -replace "GMT", "-00:00"
	$ExpirationTimeSpan = ([DateTime]::ParseExact($SplitString,"ddd MMM dd HH:mm:ss zzz yyyy",$null)) - (Get-Date)
	
	$ExpirationTimeSpan
}

function HandleNETWHOISDateTime($WhoisQueryText,$MatchString) {
	$SplitString = ($WhoisQueryText -match $MatchString) -split " "
	$SplitString = ($SplitString[$SplitString.Length - 1]).Trim()
	$ExpirationTimeSpan = ([datetime]::Parse($SplitString)) - (Get-Date)
	
	$ExpirationTimeSpan
}

function HandleCOMWHOISDateTime($WhoisQueryText,$MatchString) {
	$SplitString = ($WhoisQueryText -match $MatchString) -split ": "
	$SplitString = ($SplitString[$SplitString.Length - 1]).Trim()
	$ExpirationTimeSpan = ([datetime]::Parse($SplitString)) - (Get-Date)
	
	$ExpirationTimeSpan
}


if ($DomainName -match ".us$") {
	[int]$DaysUntilExpiry = (HandleUSWHOISDateTime $FullTextWhois "Expiration Date").TotalDays
	[int]$DaysSinceRegistration = [math]::abs((HandleUSWHOISDateTime $FullTextWhois "Registration Date").TotalDays)
	[int]$DaysSinceLastUpdate = [math]::abs((HandleUSWHOISDateTime $FullTextWhois "Last Updated Date").TotalDays)
#	[int]$DaysSinceTransfer = [math]::abs((HandleUSWHOISDateTime $FullTextWhois "Last Transferred Date").TotalDays)
} elseif ($DomainName -match ".net$") {
	[int]$DaysUntilExpiry = (HandleNETWHOISDateTime $FullTextWhois "Expiration Date").TotalDays
	[int]$DaysSinceRegistration = [math]::abs((HandleNETWHOISDateTime $FullTextWhois "Registration Date").TotalDays)
	[int]$DaysSinceLastUpdate = [math]::abs((HandleNETWHOISDateTime $FullTextWhois "Updated Date").TotalDays)
} elseif ($DomainName -match ".com$") {
	[int]$DaysUntilExpiry = (HandleCOMWHOISDateTime $FullTextWhois "Expiration Date").TotalDays
	[int]$DaysSinceRegistration = [math]::abs((HandleCOMWHOISDateTime $FullTextWhois "Registration Date").TotalDays)
	[int]$DaysSinceLastUpdate = [math]::abs((HandleCOMWHOISDateTime $FullTextWhois "Updated Date").TotalDays)
}

###############################################################################
# output

"<prtg>`n"

Set-PrtgResult "Days Until Expiry" $DaysUntilExpiry "days" -ShowChart
Set-PrtgResult "Days Since Registration" $DaysSinceRegistration "days"
Set-PrtgResult "Days Since Last Update" $DaysSinceLastUpdate "days"
#Set-PrtgResult "Days Since Transfer" $DaysSinceTransfer "days"

"</prtg>"
