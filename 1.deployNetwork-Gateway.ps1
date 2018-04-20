<#
 .SYNOPSIS
    Create a network and a VPN gateway Point-to-Site, configure it with certificates and download VPN client

 .DESCRIPTION
    Create a network and a VPN gateway Point-to-Site, configure it with certificates and download VPN client

 .PARAMETER subscriptionId
    The subscription id where the template will be deployed.

 .PARAMETER resourceGroupName
    The resource group where the template will be deployed. Can be the name of an existing or a new resource group.

 .PARAMETER resourceGroupLocation
    A resource group location. If specified, will try to create a new resource group in this location. If not specified, assumes resource group is existing.

 .PARAMETER KeepAzureRMProfile
    Keep AzureRM Profile file in the current folder. It will be not removed at the end of the script and avoid the authenticate again

 .EXAMPLE
    .\1.deployNetwork-Gateway.ps1 -subscriptionId <subid> -resourceGroupName <rgname> -resourceGroupLocation westeurope -KeepAzureRMProfile
#>

param(
 [Parameter(Mandatory=$True)]
 [string]
 $subscriptionId,

 [Parameter(Mandatory=$True)]
 [string]
 $resourceGroupName,

 [Parameter(Mandatory=$True)]
 $resourceGroupLocation,

 [SWITCH]$KeepAzureRMProfile
)

#Variables
$ScriptPath = Get-Location
$credentialsPath = "$ScriptPath\azureprofile.json"

$VNETName = "VNET1-$resourceGroupName"
$VNETAddressPrefix = '10.0.0.0/16'

$Subnet1Name = "SUBNET1"
$Subnet1AddressPrefix = '10.0.1.0/24'

$Subnet2Name = "GatewaySubnet" #Don't modify the Gateway subnet name. Azure accept only this one.
$Subnet2AddressPrefix = '10.0.2.0/24'

$VPNClientAddressPool = "172.16.201.0/24"
$GWName = "VNet1GW"
$GWIPName = "VNet1GWPIP"
$GWIPconfName = "gwipconf"

$RootCertName = "P2SRootCert-$resourceGroupName"
$ClientP2SCert = "P2SClientCert-$resourceGroupName"
$CertDER = "$ScriptPath\P2SRootexportPub-$resourceGroupName.cer"
$CertPfx = "$ScriptPath\P2SRootBackupPriv-$resourceGroupName.pfx"
$CertClientPfx = "$ScriptPath\P2SClientBackupPriv1-$resourceGroupName.pfx"
$mypwd = ConvertTo-SecureString -String "mypassword" -Force -AsPlainText

#******************************************************************************
# Script body
# Execution begins here
#******************************************************************************
$ErrorActionPreference = "Stop"
import-module AzureRM

# sign in
Write-Host "Logging in...";
if (!(Test-Path $credentialsPath)){
    Login-AzureRmAccount;
    # select subscription
    Get-AzureRmSubscription
    Write-Host "Selecting subscription '$subscriptionId'";
    Select-AzureRmSubscription -SubscriptionID $subscriptionId;
    Save-AzureRmProfile -Path $credentialsPath -Force
}
else{
    Select-AzureRmProfile -Path $credentialsPath
}

#Check if Azurerm VPNClient cmdlets are present
try
{
    $test = Get-Command 'Get-AzureRmVpnClientConfiguration' -ErrorAction Stop
}
catch
{
    $ErrorMessage = $_.Exception.Message
    if($ErrorMessage -match "The term 'Get-AzureRmVpnClientConfiguration' is not recognized as the name of a cmdlet")
    {
        Write-Warning "Powershell network module update is required"
        #Admin rights required
        #Check admin right, required to update network module to download VPN client (end of the script)
        if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
        {
            Write-Warning "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!"
            Break
        }
        #Update AzureRM Network for Powershell to have cmdlet : Get-AzureRmVpnClientConfiguration
        update-Module -Name AzureRM.Network -force
        Import-Module AzureRM
    }
}

#Create or check for existing resource group
$resourceGroup = Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if(!$resourceGroup)
{
    Write-Host "Resource group '$resourceGroupName' does not exist. To create a new resource group, please enter a location.";
    if(!$resourceGroupLocation) {
        $resourceGroupLocation = Read-Host "resourceGroupLocation";
    }
    Write-Host "Creating resource group '$resourceGroupName' in location '$resourceGroupLocation'";
    New-AzureRmResourceGroup -Name $resourceGroupName -Location $resourceGroupLocation
}
else{
    Write-Host "Using existing resource group '$resourceGroupName'";
}

###########################################
#NETWORK
# Define the subnets.
$Subnet1 = New-AzureRmVirtualNetworkSubnetConfig -Name $Subnet1Name -AddressPrefix $Subnet1AddressPrefix
$Subnet2 = New-AzureRmVirtualNetworkSubnetConfig -Name $Subnet2Name -AddressPrefix $Subnet2AddressPrefix

# Create a virtual network.
$VNET = New-AzureRmVirtualNetwork -ResourceGroupName $resourceGroupName -Location $resourceGroupLocation -Name $VNETName -AddressPrefix $VNETAddressPrefix -Subnet $Subnet1,$Subnet2

#Create the network security group and define the rules
$nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $resourceGroupLocation -Name "NSG-$Subnet1Name"
$vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $resourceGroupName -Name $VNETName
Set-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $VNET -Name $Subnet1Name -AddressPrefix $Subnet1AddressPrefix -NetworkSecurityGroup $nsg
Set-AzureRmVirtualNetwork -VirtualNetwork $vnet

###########################################
#Configure the VPN Gateway - Point-to-Site#
$VNET = Get-AzureRmVirtualNetwork -Name $VNETName -ResourceGroupName $resourceGroupName
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $VNET

$pip = New-AzureRmPublicIpAddress -Name $GWIPName -ResourceGroupName $resourceGroupName -Location $resourceGroupLocation -AllocationMethod Static
$ipconf = New-AzureRmVirtualNetworkGatewayIpConfig -Name $GWIPconfName -Subnet $subnet -PublicIpAddress $pip

write-host "Gateway creation could take 45minutes"
New-AzureRmVirtualNetworkGateway -Name $GWName -ResourceGroupName $resourceGroupName `
-Location $resourceGroupLocation -IpConfigurations $ipconf -GatewayType Vpn -VpnType RouteBased -EnableBgp $false -GatewaySku standard

$Gateway = Get-AzureRmVirtualNetworkGateway -ResourceGroupName $resourceGroupName -Name $GWName
Set-AzureRmVirtualNetworkGateway -VirtualNetworkGateway $Gateway -VpnClientAddressPool $VPNClientAddressPool

#Create Root certificate
$cert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
-Subject "CN=$RootCertName" -KeyExportPolicy Exportable `
-HashAlgorithm sha256 -KeyLength 2048 `
-CertStoreLocation "Cert:\CurrentUser\My" -KeyUsageProperty Sign -KeyUsage CertSign -NotAfter (Get-Date).AddYears(10)

Export-Certificate –Cert $Cert –FilePath $CertDER -Type CERT -NoClobber #Create a tempory file, public key of root certificate
Export-PfxCertificate -Cert $Cert –FilePath $CertPfx -Password $mypwd #Create a backup of root certificate with private key
$CertContent = new-object System.Security.Cryptography.X509Certificates.X509Certificate2($CertDER)
Remove-Item $CertDER 
$CertBase64 = [system.convert]::ToBase64String($CertContent.RawData)
$p2srootcert = New-AzureRmVpnClientRootCertificate -Name ($RootCertName) -PublicCertData $CertBase64

#Upload CertBase64 to Azure
Add-AzureRmVpnClientRootCertificate -VpnClientRootCertificateName ($RootCertName) -VirtualNetworkGatewayname $GWName -ResourceGroupName $resourceGroupName -PublicCertData $CertBase64

#Create Client certificate
$cert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
-Subject "CN=$ClientP2SCert" -KeyExportPolicy Exportable `
-HashAlgorithm sha256 -KeyLength 2048 `
-CertStoreLocation "Cert:\CurrentUser\My" `
-Signer $cert -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")

Export-PfxCertificate -Cert $Cert –FilePath $CertClientPfx -Password $mypwd #Create a backup of client certificate with private key

#Download VPN client
$profile = New-AzureRmVpnClientConfiguration -ResourceGroupName $resourceGroupName -Name $GWName -AuthenticationMethod "EapTls"
$profile.VPNProfileSASUrl
$url = $profile.VPNProfileSASUrl
$output = "$ScriptPath\VPN-$VNETName.zip"
(New-Object System.Net.WebClient).DownloadFile($url, $output)

#Remove the AzureRM Profile file
if(!$KeepAzureRMProfile){
    write-host "deleting the AzureRMProfile file"
    Remove-Item $credentialsPath
}
