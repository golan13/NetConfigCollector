<#	
	.NOTES
	===========================================================================
	 Created on:   	02/08/2020 1:11 PM
	 Created by:   	Golan Cohen
	 Organization: 	Israel Cyber Directorate
	 Filename:     	GetNetworkConfig
	===========================================================================
	.DESCRIPTION
		Cyber Audit Tool - Collect Configuration and routing tables from network devices
#>

. $PSScriptRoot\CyberFunctions.ps1

$ACQ = ACQ("Network")

$vendors = @("CISCO","HP","H3C","Juniper","Enterasys","Fortigate", "Asa")

function Test-Table
{
    $fix = $false
    Write-Host "Checking table format"
    foreach ($j in 1,3,4,5){
        for ($i = $StartRow; $i -le $length; $i++){
            $cell = $worksheet.Cells.Item($i, $j).Text;
            if ([string]::IsNullOrEmpty($cell)){
                Write-Host [Failed] Found empty cell '('$i','$j ')' -ForegroundColor Red;
                $fix = $true;
            }
        }
    }
    if ($fix){
        Write-Host "[Failed] Table is missing some data, Please fix and try again" -ForegroundColor Red
             break
    } else {
        Write-Host "[Success] Table is OK" -ForegroundColor Green
    }
}

function Rename-Dir 
{
    param
    (
		[String]$Num,
        [String]$Dir,
        [String]$IP,
        [String]$Vendor,
        [String]$File
    )
    $FileContent = Get-Content $File | Out-String;
    if ($Vendor -eq "cisco" -or $Vendor -eq "asa" -or $Vendor -eq "hp" -or $Vendor -eq "enterasys") {
        $EndDelimeter = "#";
        $StartDelimeter = "`n";
    } elseif ($Vendor -eq "h3c") {
        $EndDelimeter = ">";
        $StartDelimeter = "<";
    } elseif ($Vendor -eq "juniper") {
        $EndDelimeter = ">";
        $StartDelimeter = "`n";
    } 
    $LastIndex = $FileContent.LastIndexOf($EndDelimeter);
    $Tmp = $FileContent.Substring(0, $LastIndex);
    $FirstIndex = $Tmp.LastIndexOf($StartDelimeter);
    $DeviceName = $Tmp.Substring($FirstIndex + 1) + ' ' + $IP;
    Rename-Item $Dir\$Num $Dir\$DeviceName;
}
function Get-DeviceConfig
{
    [OutputType([String])]
    param
    (
		[String]$HostAddress,
		[Int]$HostPort,
        [String]$Vendor,
		[String]$Username,
        [SecureString]$Password,
		[String]$Command,
        [String]$Output,
        [Switch]$Append,
        [Int]$Timeout
    )
    $Credentials = New-Object System.Management.Automation.PSCredential $Username, $Password;
    $SSHSession = New-SSHSession -ComputerName $HostAddress -Port $HostPort -Credential $Credentials -AcceptKey ;   
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
        } elseif ($Vendor -eq "fortigate") {
            $SessionStream.WriteLine("config system console");
            $SessionStream.WriteLine("set output standard");
        } elseif ($Vendor -eq "asa") {
            $SessionStream.WriteLine("enable");
            $SessionStream.WriteLine("terminal pager 0");
            $SessionStream.WriteLine("no pager");
        }
        $SessionStream.WriteLine($command);
        Start-Sleep -s $Timeout;
        while ($SessionStream.DataAvailable){
            Start-Sleep -s 1;
            $SessionResponse = $SessionStream.Read() | Out-String;
        }
        Write-Host $SessionResponse
        if ($Output){
            if ($Append) {
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


$help = @"

        This tool will try to automatically collect configuration and routing tables from network devices
        using SSH protocol.

        This tool is currently supporting these devices:
        1. CISCO (IOS/Nexus)
        2. HP
        3. H3C
        4. Juniper
        5. Enterasys
        6. Fortigate
        7. ASA

        The tool requires as an input an excel file in this format:
        IP | SSH Port | Username | Password | Vendor

        Please follow these steps:
        1. Excel template file will be automatically created: $ACQ\NetworkDevices-$TimeStamp.xlsx
        2. please fill all the data in the correct columns before running the collection task
        3. Save and Close excel (do not use Save As)

"@

Write-Host $help -ForegroundColor Yellow

if (!($Timeout = Read-Host "Timeout in seconds between each run [default = 5]")) { $Timeout = 5 };

$IPCol = 1
$PortCol = 2
$UserCol = 3
$PassCol = 4
$VendorCol = 5
$StartRow = 2

#creating the excel file for this audit
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$workbook = $excel.Workbooks.Add()
$worksheet = $workbook.Worksheets.Item(1)
$worksheet.Name = "DeviceList"
$worksheet._DisplayRightToLeft = $false

$worksheet.Cells.Item(1,1) = "IP"
$worksheet.Cells.Item(1,2) = "SSH Port"
$worksheet.Cells.Item(1,3) = "User Name"
$worksheet.Cells.Item(1,4) = "Password"
$worksheet.Cells.Item(1,5) = "Vendor"

$VendorsHeader = "CISCO,HP,H3C,Juniper,Enterasys,Fortigate,ASA"
$Range = $WorkSheet.Range("E2:E100")
$Range.Validation.add(3,1,1,$VendorsHeader)
$Range.Validation.ShowError = $False

$excel.DisplayAlerts = $false
$TimeStamp = UniversalTimeStamp
$FilePath = "$ACQ\NetworkDevices-$TimeStamp.xlsx"
$worksheet.SaveAs($FilePath)

$excel.Visible = $true

$action = Read-Host "Press [S] to save file and start collecting config data (or Enter to quit)"
$worksheet.SaveAs($FilePath)



if ($action -eq "S"){
    $length = $sh.UsedRange.Rows.Count;
    Test-Table;
    Write-Host "Creating connection and retrieving configuration files. Please wait."
    for ($i = $StartRow; $i -le $length; $i++){
        $ip = $sh.Cells.Item($i, $IPCol).Text
        $port = $null ; $port = $sh.Cells.Item($i, $PortCol).Text
        if ([String]::IsNullOrEmpty($port)) {
            $port = 22;
        }
        $username = $sh.Cells.Item($i, $UserCol).Text
        $password = $sh.Cells.Item($i, $PassCol).Text
        $vendor = $sh.Cells.Item($i, $VendorCol).Text
        $savePath = "$ACQ\$vendor-$ip-$port\"
        Write-Host "Collected data for device $ip port $port will be saved in: $savePath" -ForegroundColor Green
        $null = New-Item -Path $savePath -ItemType Directory 
        switch($vendor)
        {
            #CISCO
            $vendors[0]{
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "cisco" -Command "sh run" -Output $dir\$i\'sh run.txt'
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "cisco" -Command "show ip route vrf *" -Output $dir\$i\'route.txt'
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "cisco" -Command "sh conf | include hostname" -Output $dir\$i\'run.txt'
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "cisco" -Command "sh ver" -Output $dir\$i\'run.txt' -Append
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "cisco" -Command "show access-lists" -Output $dir\$i\'run.txt' -Append
                #Rename-Dir -Num $i -Dir $dir -IP $ip -Vendor $vendor -File $dir\$i\'run.txt'
            }
            #H3C
            $vendors[2]{
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "h3c" -Command "display" -Output $dir\$i\'run.txt'
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "h3c" -Command "display ip routing-table" -Output $dir\$i\'route.txt'
                #Rename-Dir -Num $i -Dir $dir -IP $ip -Vendor $vendor -File $dir\$i\'run.txt'
            }
            #HP
            $vendors[1]{
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "hp" -Command "sh run" -Output $dir\$i\'run.txt'
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "hp" -Command "show ip route" -Output $dir\$i\'route.txt'
                #Rename-Dir -Num $i -Dir $dir -IP $ip -Vendor $vendor -File $dir\$i\'run.txt'
            }
            #Juniper
            $vendors[3]{
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "juniper" -Command "show configuration | display inheritance | no-more" -Output $dir\$i\'run.txt'
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "juniper" -Command "show chassis hardware | no-more" -Output $dir\$i\'run.txt' -Append
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "juniper" -Command "show route logical-system all | no-more" -Output $dir\$i\'route.txt'
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "juniper" -Command "show route all | no-more" -Output $dir\$i\'route1.txt'
                #Rename-Dir -Num $i -Dir $dir -IP $ip -Vendor $vendor -File $dir\$i\'run.txt'
            }
            #Enterasys
            $vendors[4]{
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "enterasys" -Command "show config all" -Output $dir\$i\'run.txt'
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "enterasys" -Command "show ip route" -Output $dir\$i\'route.txt'
                #Rename-Dir -Num $i -Dir $dir -IP $ip -Vendor $vendor -File $dir\$i\'run.txt'
            }
            #Fortigate
            $vendors[5]{
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "fortigate" -Command "get system status" -Output $dir\$i\'config.txt'
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "fortigate" -Command "show" -Output $dir\$i\'config.txt' -Append
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "fortigate" -Command "get router info routing-table" -Output $dir\$i\'route.txt'
                #Rename-Dir -Num $i -Dir $dir -IP $ip -Vendor $vendor -File $dir\$i\'config.txt'
            }
            #ASA
            $vendors[6]{
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "asa" -Command "show run" -Output $dir\$i\'run.txt'
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "asa" -Command "show access-lists" -Output $dir\$i\'run.txt' -Append
                Get-DeviceConfig -HostAddress $ip -HostPort $port -Username $username -Password $password -Vendor "asa" -Command "show route" -Output $dir\$i\'route.txt'
                #Rename-Dir -Num $i -Dir $dir -IP $ip -Vendor $vendor -File $dir\$i\'run.txt'
            }
        }
    }
}

[void]$workbook.Close($false)
$excel.DisplayAlerts = $true
[void]$excel.quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null