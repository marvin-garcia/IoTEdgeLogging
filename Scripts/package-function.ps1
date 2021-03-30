# deploy the script at .\FunctionApp\FunctionApp\
dotnet build /p:DeployOnBuild=true /p:DeployTarget=Package
dotnet publish /p:CreatePackageOnPublish=true -o .\bin\Publish
Compress-Archive -Path .\bin\publish\*  -DestinationPath deploy.zip