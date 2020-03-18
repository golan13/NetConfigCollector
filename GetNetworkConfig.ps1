<#	
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
            } elif ($j -eq 5) {
                if ($cell -ne "cisco ios" -and $cell -ne "cisco nexus" -and $cell -ne "hp" -and $cell -ne "h3c" -and $cell -ne "juniper") {
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
Read-Host “Please choose location of excel file (Press ENTER)”
#$loc = Get-FileName
$loc = "C:\Users\Golan\Documents\GetNetworkConfig\test.xlsx"
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
        "cisco ios"{
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "cisco" -Command "sh run" -Output $dir\$i\'sh run.txt'
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "cisco" -Command "show ip route vrf *" -Output $dir\$i\'route.txt'
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "cisco" -Command "sh snmp user" -Output $dir\$i\'snmp.txt'
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "cisco" -Command "sh conf | include hostname" -Output $dir\$i\'run.txt'
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "cisco" -Command "sh ver" -Output $dir\$i\'run.txt' -a
            Get-DeviceConfig -HostAddress $ip -Username $username -Password $password -AcceptKey -Vendor "cisco" -Command "show access-lists" -Output $dir\$i\'run.txt' -a
        }
        "cisco nexux"{
        
        }
        "h3c"{
            
        }
        "hp"{
        
        }
        "juniper"{
        
        }
        "terrasys"{
        
        }
    }
}

$wb.close($false)
$excel.Quit()