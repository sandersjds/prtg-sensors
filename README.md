prtg-sensors
============

Quick-and-dirty PRTG sensors for various home devices. YMMV. A lot.

Each of these were written to monitor various devices I've got on my home network using the free version of PRTG Network Monitor. Included:

- Domain Expiry: uses a Sysinternals tool to check WHOIS data for domain expiry information. WHOIS databases tend to be a little bit inconsistent in their formatting; this currently works with some .us, .net, and .com domains.
- Motorola/Arris SB6141: monitors signal diagnostic data from a cable modem.
- Some OLD RCA cable modem: signal diagnostics data from my old modem; couldn't even tell you what model it was.
- PPBE: monitors power usage form a CyberPower UPS by way of PowerPanel Business Edition.
- Transmission: monitors data from transmission, the torrent client.
- Monthly Bandwidth: used for monitoring bandwidth utilization on a WAN port. The impetus for this script was Comcast's data caps; since they provide no reliable way to monitor this aside from clicking through their terrible website. Requires an SNMP-monitored port dedicated to WAN traffic.