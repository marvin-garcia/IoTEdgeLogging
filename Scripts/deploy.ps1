function New-IoTEnvironment()
{
    #region obtain deployment location
    $locations = Get-ResourceGroupLocations -provider 'Microsoft.Devices' -typeName 'ProvisioningServices'
    
    Write-Host "Please choose a location for your deployment from this list (using its Index):"
    for ($index = 0; $index -lt $locations.Count; $index++)
    {
        Write-Host "$($index + 1): $($locations[$index])"
    }
    while ($true)
    {
        $option = Read-Host -Prompt ">"
        try
        {
            if ([int]$option -ge 1 -and [int]$option -le $locations.Count)
            {
                break
            }
        }
        catch
        {
            Write-Host "Invalid index '$($option)' provided."
        }
        Write-Host "Choose from the list using an index between 1 and $($locations.Count)."
    }
    $location_name = $locations[$option - 1]
    $location = $location_name.Replace(' ', '').ToLower()
    Write-Host "Using location $($location)"
    #endregion

    #region obtain resource group name
    $resource_group = $null
    $first = $true
    while ([string]::IsNullOrEmpty($resource_group) -or ($resource_group -notmatch "^[a-z0-9-_]*$"))
    {
        if ($first -eq $false)
        {
            Write-Host "Use alphanumeric characters as well as '-' or '_'."
        }
        else
        {
            Write-Host
            Write-Host "Please provide a name for the resource group."
            $first = $false
        }
        $resource_group = Read-Host -Prompt ">"
    }

    $resourceGroup = az group show --name $resource_group | ConvertFrom-Json
    if (!$resourceGroup)
    {
        Write-Host "Resource group '$resource_group' does not exist."
        
        $resourceGroup = az group create --name $resource_group --location $location | ConvertFrom-Json
        Write-Host "Created new resource group $($resource_group) in $($resourceGroup.location)."
    }
    #endregion

    #region log analytics workspace Id and key
    $createWorkspace = $false
    $workspaces = az monitor log-analytics workspace list --query '[].id' -o tsv
    if ($workspaces.Count -gt 0)
    {
        Write-Host "Please choose a Log Analytics workspace to use for your deployment from this list (using its Index):"
        for ($index = 0; $index -lt $workspaces.Count; $index++)
        {
            Write-Host
            Write-Host "$($index + 1): $($workspaces[$index])"
        }
        while ($true)
        {
            $option = Read-Host -Prompt ">"
            try
            {
                if ([int]$option -ge 1 -and [int]$option -le $workspaces.Count)
                {
                    break
                }
            }
            catch
            {
                Write-Host "Invalid index '$($option)' provided."
            }
            Write-Host "Choose from the list using an index between 1 and $($workspaces.Count)."
        }
        $workspaceResourceGroup = az resource show --id $workspaces[$option - 1] --query resourceGroup -o tsv
        $workspaceName = az resource show --id $workspaces[$option - 1] --query name -o tsv
        $workspaceId = az resource show --id $workspaces[$option - 1] --query 'properties.customerId' -o tsv
        $workspaceKey =  az monitor log-analytics workspace get-shared-keys -g $workspaceResourceGroup -n $workspaceName --query primarySharedKey -o tsv

        $location = $location_name.Replace(' ', '').ToLower()
        Write-Host "Using location $($location)"
    }
    else
    {
        $createWorkspace = $true
        Write-Error "The current version of this script requires you to use an existing Log Analytics workspace. Please create one and run the script again."
        return
    }
    #endregion

    $env_hash = Get-EnvironmentHash
    $iot_hub_name_prefix = "iothub"
    $iot_hub_name = "$($iot_hub_name_prefix)-$($env_hash)"
    $deployment_condition = "tags.__app__='iotedgelogs'"
    $device_query = "SELECT * FROM devices WHERE $($deployment_condition)"

    $function_app_name = "iotedgelogsapp-$($env_hash)"

    #region virtual machine details
    $skus = az vm list-skus | ConvertFrom-Json -AsHashtable
    $vm_skus = $skus | Where-Object { $_.resourceType -eq 'virtualMachines' -and $_.locations -contains $location -and $_.restrictions.Count -eq 0 }
    $vm_sku_names = $vm_skus | Select-Object -ExpandProperty Name -Unique
    #endregion

    #region create IoT platform

    # VMs' credentials
    $password_length = 12
    $vm_username = "azureuser"
    $vm_password = New-Password -length $password_length

    #region IoT Edge VM parameters
    $edge_vm_name = "iotedgevm-$($env_hash)"
    
    # We will use VM with at least 2 cores and 8 GB of memory as gateway host.
    $edge_vm_sizes = az vm list-sizes --location $location | ConvertFrom-Json `
        | Where-Object { $vm_sku_names -icontains $_.name } `
        | Where-Object {
            ($_.numberOfCores -ge 2) -and `
            ($_.memoryInMB -ge 8192) -and `
            ($_.osDiskSizeInMB -ge 1047552) -and `
            ($_.resourceDiskSizeInMB -gt 8192)
        } `
        | Sort-Object -Property `
            NumberOfCores,MemoryInMB,ResourceDiskSizeInMB,Name
    # Pick top
    if ($edge_vm_sizes.Count -ne 0) {
        $edge_vm_size = $edge_vm_sizes[0].Name
        Write-Host "Using $($edge_vm_size) as VM size for edge gateway host..."
    }
    #endregion

    #region virtual network parameters
    $vnet_name = "iot-vnet-$($env_hash)"
    $vnet_prefix = "10.0.0.0/16"
    $edge_subnet_name = "iotedge"
    $edge_subnet_prefix = "10.0.0.0/24"
    #endregion

    $platform_parameters = @{
        "location" = @{ "value" = $location }
        "environmentHashId" = @{ "value" = $env_hash }
        "iotHubName" = @{ "value" = $iot_hub_name }
        "edgeVmName" = @{ "value" = $edge_vm_name }
        "edgeVmSize" = @{ "value" = $edge_vm_size }
        "adminUsername" = @{ "value" = $vm_username }
        "adminPassword" = @{ "value" = $vm_password }
        "vnetName" = @{ "value" = $vnet_name }
        "vnetAddressPrefix" = @{ "value" = $vnet_prefix }
        "edgeSubnetName" = @{ "value" = $edge_subnet_name }
        "edgeSubnetAddressRange" = @{ "value" = $edge_subnet_prefix }
        "deviceQuery" = @{ "value" = $device_query }
        "workspaceId" = @{ "value" = $workspaceId }
        "workspaceKey" = @{ "value" = $workspaceKey }
        "functionAppName" = @{ "value" = $function_app_name }
        "logsRegex" = @{ "value" = "\b(WRN?|ERR?|CRIT?)\b" }
    }
    Set-Content -Path ./Templates/azuredeploy.parameters.json -Value (ConvertTo-Json $platform_parameters -Depth 5)

    Write-Host "Creating resource group deployment"
    $deployment_output = az deployment group create `
        --resource-group $resource_group `
        --name 'IoTEdgeLogging' `
        --mode Incremental `
        --template-file ./Templates/azuredeploy.json `
        --parameters ./Templates/azuredeploy.parameters.json | ConvertFrom-Json
    
    if (!$deployment_output)
    {
        throw "Something went wrong with the resource group deployment. Ending script."        
    }

    $deployment_output | Out-String
    #endregion

    #region edge deployment
    
    # Create main deployment
    Write-Host "`r`nCreating main IoT edge device deployment"

    az iot edge deployment create `
        -d "main-deployment" `
        --hub-name $iot_hub_name `
        --content ./EdgeSolution/deployment.template.json `
        --target-condition=$deployment_condition

    # Create layered deployment
    $deployment_name = "sample-logging"
    $priority = 1

    Write-Host "`r`nCreating IoT edge layered deployment $deployment_name-$priority"

    az iot edge deployment create `
        --layered `
        -d "$deployment_name-$priority" `
        --hub-name $iot_hub_name `
        --content EdgeSolution/layered.deployment.json `
        --target-condition=$deployment_condition `
        --priority $priority
    #endregion

    #region build and release function app
    dotnet build /p:DeployOnBuild=true /p:DeployTarget=Package .\FunctionApp\FunctionApp\
    dotnet publish /p:CreatePackageOnPublish=true -o .\FunctionApp\FunctionApp\bin\Publish .\FunctionApp\FunctionApp\
    Compress-Archive -Path .\FunctionApp\FunctionApp\bin\publish\*  -DestinationPath .\FunctionApp\FunctionApp\deploy.zip -Update
    #endregion

    #region function app
    Write-Host "\r\nDeploying code to Function App $function_app_name"
    az functionapp deployment source config-zip -g $resource_group -n $function_app_name --src .\FunctionApp\FunctionApp\deploy.zip
    #endregion

    Write-Host ""
    Write-Host "IoT Edge VM Credentials:"
    Write-Host "Username: $vm_username"
    Write-Host "Password: $vm_password"
}

Function New-Password() {
    param(
        $length = 15
    )
    $punc = 46..46
    $digits = 48..57
    $lcLetters = 65..90
    $ucLetters = 97..122
    $password = `
        [char](Get-Random -Count 1 -InputObject ($lcLetters)) + `
        [char](Get-Random -Count 1 -InputObject ($ucLetters)) + `
        [char](Get-Random -Count 1 -InputObject ($digits)) + `
        [char](Get-Random -Count 1 -InputObject ($punc))
    $password += get-random -Count ($length - 4) `
        -InputObject ($punc + $digits + $lcLetters + $ucLetters) |`
        ForEach-Object -begin { $aa = $null } -process { $aa += [char]$_ } -end { $aa }

    return $password
}

function Get-EnvironmentHash(
    [int]$hash_length = 8
)
{
    $env_hash = (New-Guid).Guid.Replace('-', '').Substring(0, $hash_length).ToLower()

    return $env_hash
}

Function Get-ResourceGroupLocations(
    $provider,
    $typeName
)
{
    $providers = $(az provider show --namespace $provider | ConvertFrom-Json)
    $resourceType = $providers.ResourceTypes | Where-Object { $_.ResourceType -eq $typeName }

    return $resourceType.locations
}

New-IoTEnvironment