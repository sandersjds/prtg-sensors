<#

curl 'http://transmissiond:9091/transmission/rpc' -H 'Origin: http://transmissiond:9091' -H 'Accept-Encoding: gzip,deflate,sdch' -H 'Host: ransmissiond:9091' -H 'Accept-Language: en-US,en;q=0.8' -H 'User-Agent: Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/28.0.1500.72 Safari/537.36' -H 'Content-Type: json' -H 'Accept: application/json, text/javascript, */*; q=0.01' -H 'Referer: http://ransmissiond:9091/transmission/web/' -H 'X-Requested-With: XMLHttpRequest' -H 'Connection: keep-alive' -H 'X-Transmission-Session-Id: c0bE2HCjspIty2jlnjYI0ONucTylwAT0fg34vByIVChFzAru' --data-binary '{"method":"torrent-get","arguments":{"fields":["id","error","errorString","eta","isFinished","isStalled","leftUntilDone","metadataPercentComplete","peersConnected","peersGettingFromUs","peersSendingToUs","percentDone","queuePosition","rateDownload","rateUpload","recheckProgress","seedRatioMode","seedRatioLimit","sizeWhenDone","status","trackers","uploadedEver","uploadRatio"],"ids":"recently-active"}}' --compressed

 torrentStatus: {
    "-1": "All",
    0: "Stopped",
    1: "Check waiting",
    2: "Checking",
    3: "Download waiting",
    4: "Downloading",
    5: "Seed waiting",
    6: "Seeding"
  },


#>

###############################################################################



function Get-TorrentStatus {
	$RequestBody = '{"method":"torrent-get","arguments":{"fields":["id","error","errorString","eta","isFinished","isStalled","leftUntilDone","metadataPercentComplete","peersConnected","peersGettingFromUs","peersSendingToUs","percentDone","queuePosition","rateDownload","rateUpload","recheckProgress","seedRatioMode","seedRatioLimit","sizeWhenDone","status","trackers","uploadedEver","uploadRatio"],"ids":"recently-active"}}'

	if (!$SessionID) {

		try { 
			$RawStatusData = Invoke-WebRequest "http://transmissiond:9091/transmission/rpc" -Method Post -Body $RequestBody
		}
		catch {
			$ErrorMessage = $_.ErrorDetails.Message # this comes out as one string and no line breaks
			$ErrorMessage = $ErrorMessage.Split("`r") # split on linebreaks
			$ErrorMessage = $ErrorMessage[$ErrorMessage.Length-1].split(":") # get the last line (which contains the session id) and split by the colon
			$SessionID = $ErrorMessage[$ErrorMessage.Length-1].trim() # get the last item in the array and clean it up
		}
	}

		$RawStatusData = Invoke-WebRequest "http://transmissiond:9091/transmission/rpc"  -WebSession $transmission -Method Post -Body $RequestBody -Headers @{"X-Transmission-Session-Id" = $SessionID}

	(ConvertFrom-Json $RawStatusData.Content).arguments.torrents | select eta,id,percentdone,ratedownload,rateupload,status
}

Import-Module prtgshell

$TorrentData	= @(Get-TorrentStatus)
$DownloadRate	= (($TorrentData | Measure-Object -Sum rateDownload).Sum)
$UploadRate		= (($TorrentData | Measure-Object -Sum rateUpload).Sum)
$CountDL		= @($TorrentData | ? { $_.status -eq 4 }).Count
$CountSeed		= @($TorrentData | ? { $_.status -eq 6 }).Count
$CountWait		= @($TorrentData | ? { $_.status -eq 3 }).Count

"<prtg>`n"

Set-PrtgResult "Torrents: Total in queue" $TorrentData.Count "torrents" -ShowChart
Set-PrtgResult "Torrents: Downloading" $CountDL "torrents" -ShowChart
Set-PrtgResult "Torrents: Seeding" $CountSeed "torrents" -ShowChart
Set-PrtgResult "Torrents: Waiting" $CountWait "torrents" -ShowChart
Set-PrtgResult "Bandwidth: Total Download Rate" $DownloadRate "BytesBandwidth" -ShowChart -SpeedSize KiloByte
Set-PrtgResult "Bandwidth: Total Upload Rate" $UploadRate "BytesBandwidth" -ShowChart -SpeedSize KiloByte

"</prtg>"

