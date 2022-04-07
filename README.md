# MIAzureFunctionDeployWrapper
Wrapper for Azure function core tools to allow publishing to functions accessing their own storage with managed identity.

Azure functions core tools looks into the function configuration key "AzureWebJobsStorage" and expects a connection string.
This key isn't there when managed identity is used to access the function storage, see here:

https://docs.microsoft.com/en-us/azure/azure-functions/functions-reference?tabs=blob#connecting-to-host-storage-with-an-identity-preview

This leads to core tools exiting with an error, see here:

https://github.com/Azure/azure-cli/issues/19035

This script works around the issue by setting the value core tools expects, running core tools and then restoring the original settings.
