#Hack to make func azure functionapp publish work with functions set up to access web jobs storage with managed identity
#Az.Accounts, Az.Websites and Az.Storage need to be installed
#This script assumes the correct azure context is already set by calling Connect-AzAccount for example
#script args will be passed through to func azure functionapp publish
param (
    [Parameter(
        Mandatory=$true,
        Position=0)]
        [string]$FunctionAppName
    ,
    [Parameter(
        Mandatory=$false)]
        [string]$SlotName
    ,
    [Parameter(
        Mandatory=$true,
        Position=1)]
        [ValidateSet("Set","Restore","Full")] #split the script in three parts making the actual core tools call optional
        [string]$Mode
    ,
    [Parameter(
        ValueFromRemainingArguments=$true,
        Position=2)]
        [string[]]$publishargs
)    

$ErrorActionPreference = 'Stop'

$requiredModules = @(
    "Az.Websites",
    "Az.Storage"
)
$requiredModules | foreach-object { if (!(get-module $_)) { import-module $_ } }

#fixed strings according to MS docs
$awjsname = 'AzureWebJobsStorage'
$awjsan = 'AzureWebJobsStorage__accountName'
$awjsbsu = 'AzureWebJobsStorage__blobServiceUri'

#args that will be passed to func azure functionapp publish
$publishargstr = $publishargs -join ' '
Write-Host "publish args: $publishargstr"

if (($Mode -eq "Set") -or ($Mode -eq "Full"))
{
    #retrieve and save original site settings
    $webapp = Get-AzWebApp -Name $FunctionAppName
    if ($SlotName)
    {
        $webapp = Get-AzWebAppSlot -Slot $SlotName -WebApp $webapp
    }
    
    $originalsettings = $webapp.SiteConfig.AppSettings
    $originalstring = $originalsettings | Where-Object { $_.Name -like $awjsname } | Select-Object -ExpandProperty Value
    $ENV:MIFUNCTIONAWJS = $originalstring

    #determine storage account
    $storageaccountname = $originalsettings | Where-Object { $_.Name -like $awjsan } | Select-Object -ExpandProperty Value
    if (-not $storageaccountname)
    {
        $storageaccountname = $originalsettings | Where-Object { $_.Name -like $awjsbsu } | Select-Object -ExpandProperty Value
        $storageaccountname -match 'https://(.+).blob.core.windows.net'
        $storageaccountname = $Matches.1
        if (-not $storageaccountname)
        {
            Write-Error "Storage account for the function app not found in the settings. Checked in $awjsan and $awjsbsu."
            exit 1
        }
    }
    Write-Host "Storage account: $storageaccountname"
    $storageaccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageaccountname}
    #get accoount access key
    $accountkey = (Get-AzStorageAccountKey -Name $storageaccountname -ResourceGroupName $storageaccount.ResourceGroupName)[0].Value
    $connectionString = 'DefaultEndpointsProtocol=https;AccountName='+$storageaccountname+';AccountKey='+$accountkey+';EndpointSuffix=core.windows.net'

    #new settings for core tools to work
    $publishsettings = @{}
    $originalsettings | Where-Object { $_.Name -ne $awjsname } | ForEach-Object { $publishsettings.add($_.Name,$_.Value) }
    $publishsettings.Add($awjsname, $connectionString)

    #set new settings
    Write-Host "Updating web app to allow for core tools publishing"
    if($SlotName) {Set-AzWebAppSlot -Name $FunctionAppName -Slot $SlotName -ResourceGroupName $webapp.ResourceGroup -AppSettings $publishsettings} else {Set-AzWebApp -Name $FunctionAppName -ResourceGroupName $webapp.ResourceGroup -AppSettings $publishsettings}

    if ($Mode -eq "Set") { exit 0 }
}

if ($Mode -eq "Full")
{
    #run core tools
    $publishexpression = if($SlotName) {"func azure functionapp publish $FunctionAppName --slot $SlotName $publishargstr"} else {"func azure functionapp publish $FunctionAppName $publishargstr"}
    Write-Host "Running core tools command:"
    Write-Host $publishexpression
    Invoke-Expression -Command $publishexpression
}

if (($Mode -eq "Restore") -or ($Mode -eq "Full"))
{
    #restore original settings
    Write-Host "Resetting web app to original settings"
    $webapp = Get-AzWebApp -Name $FunctionAppName
    if ($SlotName)
    {
        $webapp = Get-AzWebAppSlot -Name $FunctionAppName -Slot $SlotName -ResourceGroupName $webapp.ResourceGroup
    }

    $originalsettings = $webapp.SiteConfig.AppSettings
    $hashedoriginals = @{}
    $originalsettings | Where-Object { $_.Name -ne $awjsname } | ForEach-Object { $hashedoriginals.add($_.Name,$_.Value) }
    if ($ENV:MIFUNCTIONAWJS) { $hashedoriginals.Add($awjsname,$ENV:MIFUNCTIONAWJS) }
    if($SlotName) {Set-AzWebAppSlot -Name $FunctionAppName -Slot $SlotName -ResourceGroupName $webapp.ResourceGroup -AppSettings $hashedoriginals} else {Set-AzWebApp -Name $FunctionAppName -ResourceGroupName $webapp.ResourceGroup -AppSettings $hashedoriginals}
}
