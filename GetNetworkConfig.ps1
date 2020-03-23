﻿<#	
	.NOTES
	===========================================================================
	 Created on:   	02/08/2020 1:11 PM
	 Created by:   	GolanC
	 Organization: 	Israel Cyber Directorate
	 Filename:     	GetNetworkConfig
	===========================================================================
	.DESCRIPTION
		Cyber Audit Tool - Get Network Configuration
#>
function Get-DeviceConfig
{
    [OutputType([String])]
    param
    (
		[Parameter(Mandatory=$true)]
		[String]$HostAddress,
		[Parameter(Mandatory=$false)]
		[Int]$HostPort = 22,
        [Parameter(Mandatory=$true)]
        [String]$Vendor,
		[Parameter(Mandatory=$true)]
		[String]$Username,
        [Parameter(Mandatory=$True)]
        [String]$Password,
		[Parameter(Mandatory=$false)]
		[Switch]$AcceptKey,
		[Parameter(Mandatory=$true)]
		[String]$Command,
        [Parameter(Mandatory=$false)]
        [String]$Output,
        [Parameter(Mandatory=$false)]
        [Switch]$a,
        [Parameter(Mandatory=$false)]
        [Int] $Timeout = 5
    )
    if ([string]::IsNullOrEmpty($HostPort)) {
        $HostPort = 22;
    }
    $SecPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force;
    $Credentials = New-Object System.Management.Automation.PSCredential $Username, $SecPassword;
    $SSHSession = New-SSHSession -ComputerName $HostAddress -Port $HostPort -Credential $Credentials -AcceptKey:$AcceptKey;   
    if ($SSHSession.Connected)
    {
        $SessionStream = New-SSHShellStream -SessionId $SSHSession.SessionId;
        if ($Vendor -eq "Cisco"){
            $SessionStream.WriteLine("enable");
            $SessionStream.WriteLine("terminal length 0");
        } elseif ($Vendor -eq "H3C"){
            $SessionStream.WriteLine("screen-lengh disable");
            $SessionStream.WriteLine("disable paging");
        } elseif ($Vendor -eq "hp"){
            $SessionStream.WriteLine("no page");
            $SessionStream.WriteLine("enable");
        } elseif ($Vendor -eq "Juniper"){
            $SessionStream.WriteLine("set cli screen-width 1000");
        } elseif ($Vendor -eq "enterasys"){
            $SessionStream.WriteLine("terminal more disable");
        }
        $SessionStream.WriteLine($command);
        Start-Sleep -s $Timeout;
        while ($SessionStream.DataAvailable){
            Start-Sleep -s 1;
            $SessionResponse = $SessionStream.Read() | Out-String;
        }
        Write-Host $SessionResponse
        if ($Output){
            if ($a) {
                Add-Content $Output $SessionResponse;
            } else {
                $SessionResponse > $Output;
            }
        }
        $SSHSessionRemoveResult = Remove-SSHSession -SSHSession $SSHSession;
        if (-Not $SSHSessionRemoveResult)
        {
            Write-Error "Could not remove SSH Session $($SSHSession.SessionId):$($SSHSession.Host).";
        }
    }
    else
    {
        throw [System.InvalidOperationException]"Could not connect to SSH host: $($HostAddress):$HostPort.";
        $SSHSessionRemoveResult = Remove-SSHSession -SSHSession $SSHSession;
        if (-Not $SSHSessionRemoveResult)
        {
            Write-Error "Could not remove SSH Session $($SSHSession.SessionId):$($SSHSession.Host).";
        }
    }
}

function Get-FileName
{   
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
    Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.filter = "All files (*.*)| *.*"
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.filename
}

function Check-Table
{
    $fix = $false
    Write-Host "`nChecking table format"
    foreach ($j in 1,3,4,5){
        for ($i = $StartRow; $i -le $length; $i++){
            $cell = $sh.Cells.Item($i, $j).Text;
            if ([string]::IsNullOrEmpty($cell)){
                Write-Host Found empty cell '('$i','$j ')' -ForegroundColor Red;
                $fix = $true;
            } elseif ($j -eq 5) {
                if ($cell -ne "cisco" -and $cell -ne "hp" -and $cell -ne "h3c" -and $cell -ne "juniper" -and $cell -ne "enterasys") {
                    Write-Host Unknown vendor on row $i : "'"${vendor} "'" -ForegroundColor Red
                    $fix = $true 
                }
            }
        }
    }
    if ($fix){
        Write-Host "`nVendor must be: cisco ios, cisco nexus, hp, h3c, terrasys or juniper"
        Write-Host “`nPlease fix excel and re-run the script”
        Read-Host "`nPress ENTER to exit"
        $wb.close($false)
        $excel.Quit()
        exit
    } else {
        Write-Host "`nFormat good" -ForegroundColor Green
    }
}

function Rename-Dir 
{
    param
    (
		[String]$Num,
        [String]$Dir,
        [String]$IP,
		[String]$File
    )
    $FileContent = Get-Content $File | Out-String;
    $LastIndex = $FileContent.LastIndexOf("#");
    $Tmp = $FileContent.Substring(0, $LastIndex);
    $FirstIndex = $Tmp.LastIndexOf("`n");
    $DeviceName = $Tmp.Substring($FirstIndex + 1) + ' ' + $IP;
    Rename-Item $Dir\$Num $Dir\$DeviceName;
}

Read-Host “Please choose location of excel file (Press ENTER)”
#$loc = Get-FileName
$loc = "C:\Users\Golan\Documents\NetConfigCollector\test.xlsx"
$IPCol = 1
$PortCol = 2
$UserCol = 3
$PassCol = 4
$VendorCol = 5
$StartRow = 2
$excel = New-Object -ComObject Excel.Application
$wb = $excel.Workbooks.Open($loc)
$sh = $wb.Sheets.Item(1)
$length = $sh.UsedRange.Rows.Count;
Check-Table;
Write-Host "`nCreating connection and retrieving configuration files. Please wait.`n"
$dir = [string](Split-Path -Path $loc) + '\Config'
mkdir $dir | Out-Null
for ($i = $StartRow; $i -le $length; $i++){
    $ip = $sh.Cells.Item($i, $IPCol).Text
    $port = $sh.Cells.Item($i, $PortCol).Text
    $username = $sh.Cells.Item($i, $UserCol).Text
    $password = $sh.Cells.Item($i, $PassCol).Text
    $vendor = $sh.Cells.Item($i, $VendorCol).Text
    mkdir $dir\$i | Out-Null
    switch($vendor)
    {
        "cisco"{
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "cisco" -Command "sh run" -Output $dir\$i\'sh run.txt'
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "cisco" -Command "show ip route vrf *" -Output $dir\$i\'route.txt'
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "cisco" -Command "sh snmp user" -Output $dir\$i\'snmp.txt'
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "cisco" -Command "sh conf | include hostname" -Output $dir\$i\'run.txt'
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "cisco" -Command "sh ver" -Output $dir\$i\'run.txt' -a
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "cisco" -Command "show access-lists" -Output $dir\$i\'run.txt' -a

        }
        "h3c"{
             Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "h3c" -Command "display" -Output $dir\$i\'run.txt'
             Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "h3c" -Command "display ip routing-table" -Output $dir\$i\'route.txt'
        }
        "hp"{
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "hp" -Command "sh run" -Output $dir\$i\'run.txt'
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "hp" -Command "show ip route" -Output $dir\$i\'route.txt'
        }
        "juniper"{
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "juniper" -Command "show configuration | display inheritance | no-more" -Output $dir\$i\'run.txt'
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "juniper" -Command "show chassis hardware | no-more" -Output $dir\$i\'run.txt' -a
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "juniper" -Command "show route logical-system all | no-more" -Output $dir\$i\'route.txt'
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "juniper" -Command "show route all | no-more" -Output $dir\$i\'route1.txt'
        }
        "enterasys"{
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "enterasys" -Command "show config all" -Output $dir\$i\'run.txt'
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "enterasys" -Command "show ip route" -Output $dir\$i\'route.txt'
        }
        #add fortigate, cisco asa
    }
    Rename-Dir -Num $i -Dir $dir -IP $ip -File $dir\$i\'run.txt'
}

$wb.close($false)
$excel.Quit()