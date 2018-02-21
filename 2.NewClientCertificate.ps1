<#
 .SYNOPSIS
    Create a Client Certificate VPN gateway Point-to-Site

 .DESCRIPTION
    Create a new client certificate for VPN Gateway P2S (Ppint-to-site).
    The root certificate is required and have to be installed in "Cert:\CurrentUser\My” to run this script. 
    The new client certificate will be stored in "Cert:\CurrentUser\My” and will also be exported as PFX file in current folder. 

    Run [Get-ChildItem -Path “Cert:\CurrentUser\My”] to have a list of certificates present

 .PARAMETER RootCertName
    Provide only the name. Example : The certificate object is [CN=CERTNAME], provide only [CERTNAME]

 .PARAMETER ClientCertName
    The client certificate to create

 .PARAMETER ClientCertificatePassword
    The password of the exported certificate to create
    This password will be required to import the certificate on another machine

 .EXAMPLE
    .\2.NewClientCertificate.ps1 -RootCertName P2SRootCert-RGName -ClientCertName P2SClientCert-RGName-Pierre -ClientCertificatePassword mypassword
#>

param(
 [Parameter(Mandatory=$True)]
 [string]
 $RootCertName,

 [Parameter(Mandatory=$True)]
 [string]
 $ClientCertName,

 [Parameter(Mandatory=$True)]
 [string]
 $ClientCertificatePassword

)

#Variables
$ScriptPath = Get-Location


$CertClientPfx = "$ScriptPath\$ClientCertName.pfx"
$ClientCertificatePasswordSecured = ConvertTo-SecureString -String $ClientCertificatePassword -Force -AsPlainText

#******************************************************************************
# Script body
# Execution begins here
#******************************************************************************
$ErrorActionPreference = "Stop"


#Get root certificate
$RootCert = Get-ChildItem -Path “Cert:\CurrentUser\My” | Where-Object {$_.Subject -contains "CN=$RootCertName"}
if(!$RootCert)
    {
        write-host "Please enter a valid Root certificate name. Check get-help for more information"
        break
    }

#Create Client certificate
$ClientCert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
-Subject "CN=$ClientCertName" -KeyExportPolicy Exportable `
-HashAlgorithm sha256 -KeyLength 2048 `
-CertStoreLocation "Cert:\CurrentUser\My" `
-Signer $RootCert -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")

Export-PfxCertificate -Cert $ClientCert –FilePath $CertClientPfx -Password $ClientCertificatePasswordSecured #Create a backup of client certificate with private key
