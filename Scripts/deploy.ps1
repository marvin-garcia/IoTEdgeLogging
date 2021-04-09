function New-IoTEnvironment()
{
    # Get environment hash for name uniqueness
    $env_hash = Get-EnvironmentHash
    
    # verify deploy zip package is present in directory
    # $current_path = Split-Path $PSScriptRoot -Parent
    # $root_path = Split-Path $current_path -Parent
    $root_path = Split-Path $PSScriptRoot -Parent
    write-host "parent" $root_path
    if (!(Test-Path -Path "$($root_path)/FunctionApp/FunctionApp/deploy.zip"))
    {
        Write-Error "Unable to find Function app zip deploy file. Aborting."
        return
    }
    
    $create_iot_hub = $false
    $ask_for_location = $false
    $create_workspace = $false
    $create_storage = $false
    $create_event_grid = $false
    $deployment_condition = "tags.logPullEnabled='true'"

    Write-Host
    Write-Host "##############################################"
    Write-Host "##############################################"
    Write-Host "####                                      ####"
    Write-Host "#### IoT Edge Logging deployment solution ####"
    Write-Host "####                                      ####"
    Write-Host "##############################################"
    Write-Host "##############################################"
    
    Write-Host
    Write-Host "This deployment script will help you deploy the IoT Edge Logging solution in your Azure subscription."
    Write-Host "It can be deployed as a sandbox environment, with a new IoT hub and a test IoT Edge device generating sample logs, or it can connect to you existing IoT Hub and Log analytics workspace."
    Write-Host "Follow the instruction below to determine how to deploy your solution."
    Write-Host

    #region obtain resource group name
    $create_resource_group = $false
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
            Write-Host "Provide a name for the resource group to host all the new resources that will be deployed as part of your solution."
            $first = $false
        }
        $resource_group = Read-Host -Prompt ">"
    }

    $resourceGroup = az group show --name $resource_group | ConvertFrom-Json
    if (!$resourceGroup)
    {
        Write-Host "Resource group '$resource_group' does not exist. It will be created later in the deployment."
        $create_resource_group = $true
    }
    else {
        Write-Host "Resource group '$resource_group' already exists in current subscription."
    }
    #endregion

    #region iot hub details
    $iot_hubs = az iot hub list | ConvertFrom-Json
    if ($iot_hubs.Count -gt 0)
    {
        $iot_hub_options = @("Create new IoT hub", "Use existing IoT hub")
        Write-Host
        Write-Host "Choose an option from the list for the IoT hub (using its Index):"
        for ($index = 0; $index -lt $iot_hub_options.Count; $index++)
        {
            # Write-Host
            Write-Host "$($index + 1): $($iot_hub_options[$index])"
        }
        while ($true)
        {
            $option = Read-Host -Prompt ">"
            try
            {
                if ([int]$option -ge 1 -and [int]$option -le $iot_hub_options.Count)
                {
                    break
                }
            }
            catch
            {
                Write-Host "Invalid index '$($option)' provided."
            }
            Write-Host "Choose from the list using an index between 1 and $($iot_hub_options.Count)."
        }

        #region choose existing iot hub
        if ($option -eq 2)
        {
            Write-Host
            Write-Host "Choose an IoT hub to use from this list (using its Index):"
            for ($index = 0; $index -lt $iot_hubs.Count; $index++)
            {
                Write-Host
                Write-Host "$($index + 1): $($iot_hubs[$index].id)"
            }
            while ($true)
            {
                $option = Read-Host -Prompt ">"
                try
                {
                    if ([int]$option -ge 1 -and [int]$option -le $iot_hubs.Count)
                    {
                        break
                    }
                }
                catch
                {
                    Write-Host "Invalid index '$($option)' provided."
                }
                Write-Host "Choose from the list using an index between 1 and $($iot_hubs.Count)."
            }

            $iot_hub_name = $iot_hubs[$option - 1].name
            $iot_hub_resource_group = $iot_hubs[$option - 1].resourcegroup
            $location = $iot_hubs[$option - 1].location
            $iot_hub_location = $location

            # handle IoT hub service policy
            $iot_hub_policies = az iot hub policy list --hub-name $iot_hub_name | ConvertFrom-Json
            $iot_hub_policy = $iot_hub_policies | Where-Object { $_.rights -like '*serviceconnect*' -and $_.rights -like '*registryread*' }
            if ($null -eq $iot_hub_policy)
            {
                $iot_hub_policy_name = "iotedgelogs"
                Write-Host
                Write-Host "Creating IoT hub shared access policy '$($iot_hub_policy_name)' with permissions 'RegistryRead ServiceConnect'"
                az iot hub policy create --hub-name $iot_hub_name --name $iot_hub_policy_name --permissions RegistryRead ServiceConnect
            }
            else
            {
                $iot_hub_policy_name = $iot_hub_policy.keyName
                Write-Host
                Write-Host "Deployment will use existing IoT hub shared access policy '$($iot_hub_policy_name)'"
            }
        }
        #endregion
        else
        {
            $create_iot_hub = $true
            $ask_for_location = $true
        }
    }
    else
    {
        $create_iot_hub = $true
        $ask_for_location = $true
    }

    if ($create_iot_hub)
    {
        $iot_hub_name_prefix = "iothub"
        $iot_hub_name = "$($iot_hub_name_prefix)-$($env_hash)"
        $iot_hub_resource_group = $resource_group
        $iot_hub_policy_name = "iotedgelogs"
    }
    else
    {
        Write-Host -ForegroundColor Yellow "You must update device twin for your IoT edge devices with $($deployment_condition) to collect logs from their modules."
    }
    #endregion

    #region storage account
    $storage_accounts = az storage account list | ConvertFrom-Json
    if ($storage_accounts.Count -gt 0)
    {
        $storage_options = @("Create new storage account", "Use existing storage account")
        Write-Host
        Write-Host "Choose an option from the list for the storage account to store log files (using its Index):"
        for ($index = 0; $index -lt $storage_options.Count; $index++)
        {
            #Write-Host
            Write-Host "$($index + 1): $($storage_options[$index])"
        }
        while ($true)
        {
            $option = Read-Host -Prompt ">"
            try
            {
                if ([int]$option -ge 1 -and [int]$option -le $storage_options.Count)
                {
                    break
                }
            }
            catch
            {
                Write-Host "Invalid index '$($option)' provided."
            }
            Write-Host "Choose from the list using an index between 1 and $($storage_options.Count)."
        }

        #region existing storage account
        if ($option -eq 2)
        {
            Write-Host
            Write-Host "Choose a storage account to use from this list (using its Index):"
            for ($index = 0; $index -lt $storage_accounts.Count; $index++)
            {
                Write-Host
                Write-Host "$($index + 1): $($storage_accounts[$index].id)"
            }
            while ($true)
            {
                $option = Read-Host -Prompt ">"
                try
                {
                    if ([int]$option -ge 1 -and [int]$option -le $storage_accounts.Count)
                    {
                        break
                    }
                }
                catch
                {
                    Write-Host "Invalid index '$($option)' provided."
                }
                Write-Host "Choose from the list using an index between 1 and $($storage_accounts.Count)."
            }

            $storage_account_id = $storage_accounts[$option - 1].id
            $storage_account_name = $storage_accounts[$option - 1].name
            $storage_account_resource_group = $storage_accounts[$option - 1].resourceGroup
            $storage_account_location = $storage_accounts[$option - 1].location

            #region system event grid
            $system_topics = az eventgrid system-topic list | ConvertFrom-Json
            $system_topic = $system_topics | Where-Object { $_.source -eq $storage_account_id }
            if (!!$system_topic)
            {
                $system_topic_name = $system_topic.name
                Write-Host
                Write-Host "Deployment will use existing event grid system topic '$($system_topic_name)'"
            }
            else
            {
                $create_event_grid = $true
            }
            #endregion
        }
        #endregion
        else
        {
            $create_storage = $true
            $create_event_grid = $true
        }
    }
    else
    {
        $create_storage = $true
        $create_event_grid = $true
    }

    if ($create_storage)
    {
        $storage_account_name = "iotedgelogs$($env_hash)"
        $storage_account_resource_group = $resource_group
    }

    if ($create_event_grid)
    {
        $system_topic_name = "iotedgelogs-$($env_hash)"
    }
    
    $storage_container_name = "modulelogs$($env_hash)"
    $storage_queue_name = "modulelogs$($env_hash)"
    #endregion

    #region log analytics workspace
    $workspaces = az monitor log-analytics workspace list | ConvertFrom-Json
    if ($workspaces.Count -gt 0)
    {
        $workspace_options = @("Create new log analytics workspace", "Use existing log analytics workspace")
        Write-Host
        Write-Host "Choose an option from the list for Log Analytics workspace to connect to (using its Index):"
        for ($index = 0; $index -lt $workspace_options.Count; $index++)
        {
            #Write-Host
            Write-Host "$($index + 1): $($workspace_options[$index])"
        }
        while ($true)
        {
            $option = Read-Host -Prompt ">"
            try
            {
                if ([int]$option -ge 1 -and [int]$option -le $workspace_options.Count)
                {
                    break
                }
            }
            catch
            {
                Write-Host "Invalid index '$($option)' provided."
            }
            Write-Host "Choose from the list using an index between 1 and $($workspace_options.Count)."
        }

        #region existing workspace
        if ($option -eq 2)
        {
            Write-Host
            Write-Host "Choose a log analytics workspace to use from this list (using its Index):"
            for ($index = 0; $index -lt $workspaces.Count; $index++)
            {
                Write-Host
                Write-Host "$($index + 1): $($workspaces[$index].id)"
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

            $workspace_name = $workspaces[$option - 1].name
            $workspace_resource_group = $workspaces[$option - 1].resourceGroup
            $workspace_location = $workspaces[$option - 1].location
        }
        #endregion
        else
        {
            $create_workspace = $true
        }
    }
    else
    {
        $create_workspace = $true
    }

    if ($create_workspace)
    {
        $workspace_name = "iotedgelogging-$($env_hash)"
        $workspace_resource_group = $resource_group
    }
    #endregion

    #region obtain deployment location
    if ($ask_for_location)
    {
        $locations = Get-ResourceGroupLocations -provider 'Microsoft.Devices' -typeName 'ProvisioningServices'
        
        Write-Host
        Write-Host "Choose a location for your deployment from this list (using its Index):"
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
    }
    
    Write-Host
    if ($create_iot_hub)
    {
        Write-Host "Using location '$($location)'"
    }
    else
    {
        Write-Host "Using location '$($location)' based on your IoT hub location"
    }

    if ($create_iot_hub)
    {
        $iot_hub_location = $location
    }
    if ($create_storage)
    {
        $storage_account_location = $location
    }
    if ($create_workspace)
    {
        $workspace_location = $location
    }
    #endregion

    # create resource group after location has been defined
    if ($create_resource_group)
    {
        $resourceGroup = az group create --name $resource_group --location $location | ConvertFrom-Json
        Write-Host "Created new resource group $($resource_group) in $($resourceGroup.location)."
    }

    $device_query = "SELECT * FROM devices WHERE $($deployment_condition)"
    $function_app_name = "iotedgelogsapp-$($env_hash)"

    #region create IoT platform

    #region edge virtual machine
    $skus = az vm list-skus | ConvertFrom-Json -AsHashtable
    $vm_skus = $skus | Where-Object { $_.resourceType -eq 'virtualMachines' -and $_.locations -contains $location -and $_.restrictions.Count -eq 0 }
    $vm_sku_names = $vm_skus | Select-Object -ExpandProperty Name -Unique
    
    # VM credentials
    $password_length = 12
    $vm_username = "azureuser"
    $vm_password = New-Password -length $password_length

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
        # Write-Host "Using $($edge_vm_size) as VM size for edge gateway host..."
    }
    #endregion

    #region virtual network parameters
    $vnet_name = "iot-vnet-$($env_hash)"
    $vnet_prefix = "10.0.0.0/16"
    $edge_subnet_name = "iotedge"
    $edge_subnet_prefix = "10.0.0.0/24"
    #endregion

    #endregion

    $platform_parameters = @{
        "location" = @{ "value" = $location }
        "environmentHashId" = @{ "value" = $env_hash }
        "createIoTHub" = @{ "value" = $create_iot_hub }
        "iotHubLocation" = @{ "value" = $iot_hub_location }
        "iotHubName" = @{ "value" = $iot_hub_name }
        "iotHubResourceGroup" = @{ "value" = $iot_hub_resource_group }
        "iotHubServicePolicyName" = @{ "value" = $iot_hub_policy_name }
        "edgeVmName" = @{ "value" = $edge_vm_name }
        "edgeVmSize" = @{ "value" = $edge_vm_size }
        "adminUsername" = @{ "value" = $vm_username }
        "adminPassword" = @{ "value" = $vm_password }
        "vnetName" = @{ "value" = $vnet_name }
        "vnetAddressPrefix" = @{ "value" = $vnet_prefix }
        "edgeSubnetName" = @{ "value" = $edge_subnet_name }
        "edgeSubnetAddressRange" = @{ "value" = $edge_subnet_prefix }
        "deviceQuery" = @{ "value" = $device_query }
        "createStorageAccount" = @{ "value" = $create_storage }
        "storageAccountLocation" = @{ "value" = $storage_account_location }
        "storageAccountName" = @{ "value" = $storage_account_name }
        "storageAccountResourceGroup" = @{ "value" = $storage_account_resource_group }
        "storageContainerName" = @{ "value" = $storage_container_name }
        "storageQueueName" = @{ "value" = $storage_queue_name }
        "createEventGridSystemTopic" = @{ "value" = $create_event_grid }
        "eventGridSystemTopicName" = @{ "value" = $system_topic_name }
        "createWorkspace" = @{ "value" = $create_workspace }
        "workspaceLocation" = @{ "value" = $workspace_location }
        "workspaceName" = @{ "value" = $workspace_name }
        "workspaceResourceGroup" = @{ "value" = $workspace_resource_group }
        "functionAppName" = @{ "value" = $function_app_name }
        "logsRegex" = @{ "value" = "\b(WRN?|ERR?|CRIT?)\b" }
        "logsSince" = @{ "value" = "15m" }
    }
    Set-Content -Path "$($root_path)/Templates/azuredeploy.parameters.json" -Value (ConvertTo-Json $platform_parameters -Depth 5)

    Write-Host
    Write-Host "Creating resource group deployment."
    $deployment_output = az deployment group create `
        --resource-group $resource_group `
        --name "IoTEdgeLogging-$($env_hash)" `
        --mode Incremental `
        --template-file "$($root_path)/Templates/azuredeploy.json" `
        --parameters "$($root_path)/Templates/azuredeploy.parameters.json" | ConvertFrom-Json
    
    if (!$deployment_output)
    {
        throw "Something went wrong with the resource group deployment. Ending script."        
    }

    $deployment_output | Out-String
    #endregion

    #region edge deployment
    if ($create_iot_hub)
    {
        # Create main deployment
        Write-Host "`r`nCreating main IoT edge device deployment"

        az iot edge deployment create `
            -d "main-deployment" `
            --hub-name $iot_hub_name `
            --content "$($root_path)/EdgeSolution/deployment.template.json" `
            --target-condition=$deployment_condition

        # Create layered deployment
        $deployment_name = "sample-logging"
        $priority = 1
        
        Write-Host "`r`nCreating IoT edge layered deployment $deployment_name-$priority"

        az iot edge deployment create `
            --layered `
            -d "$deployment_name-$priority" `
            --hub-name $iot_hub_name `
            --content "$($root_path)/EdgeSolution/layered.deployment.json" `
            --target-condition=$deployment_condition `
            --priority $priority
    }
    #endregion

    #region function app
    Write-Host
    Write-Host "Deploying code to Function App $function_app_name"
    az functionapp deployment source config-zip -g $resource_group -n $function_app_name --src "$($root_path)/FunctionApp/FunctionApp/deploy.zip"
    #endregion

    if ($create_iot_hub)
    {
        Write-Host
        Write-Host "IoT Edge VM Credentials:"
        Write-Host "Username: $vm_username"
        Write-Host "Password: $vm_password"
    }

    Write-Host
    Write-Host "Environment unique id: $($env_hash)"

    Write-Host
    Write-Host -ForegroundColor Green "##############################################"
    Write-Host -ForegroundColor Green "##############################################"
    Write-Host -ForegroundColor Green "####                                      ####"
    Write-Host -ForegroundColor Green "####        Deployment Succeeded          ####"
    Write-Host -ForegroundColor Green "####                                      ####"
    Write-Host -ForegroundColor Green "##############################################"
    Write-Host -ForegroundColor Green "##############################################"
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