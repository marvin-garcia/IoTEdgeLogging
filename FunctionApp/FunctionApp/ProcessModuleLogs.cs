using System;
using System.IO;
using System.Linq;
using System.Text;
using Newtonsoft.Json;
using FunctionApp.Models;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using System.Text.RegularExpressions;
using Azure.Storage.Blobs;
using System.Threading.Tasks;

namespace FunctionApp
{
    public static class ProcessModuleLogs
    {
        private static string _hubResourceId = Environment.GetEnvironmentVariable("HubResourceId");
        private static string _connectionString = Environment.GetEnvironmentVariable("StorageConnectionString");
        private static string _containerName = Environment.GetEnvironmentVariable("ContainerName");
        private static string _workspaceId = Environment.GetEnvironmentVariable("WorkspaceId");
        private static string _workspaceKey = Environment.GetEnvironmentVariable("WorkspaceKey");
        private static string _workspaceApiVersion = "2016-04-01";
        private static string _logType = Environment.GetEnvironmentVariable("LogType");
        private static int _logMaxSizeMB = 28;

        [FunctionName("ProcessModuleLogs")]
        public static async Task Run(
            //[BlobTrigger("iotedgelogs/{name}", Connection = "StorageConnectionString")]Stream myBlob,
            //string name,
            [QueueTrigger("%QueueName%", Connection = "StorageConnectionString")] string queueItem,
            ILogger log)
        {
            try
            {
                log.LogInformation($"ProcessModuleLogs Received new queue item");

                JObject storageEvent = JsonConvert.DeserializeObject<JObject>(queueItem);
                var match = Regex.Match(storageEvent["subject"].ToString(), "/blobServices/default/containers/(.*)/blobs/(.*)", RegexOptions.IgnoreCase);
                if (!match.Success)
                {
                    log.LogWarning($"Unable to parse blob Url from {storageEvent["subject"]}");
                    return;
                }

                if (!string.Equals(match.Groups[1].Value, _containerName))
                {
                    log.LogDebug($"Ignoring queue item because it is related to container '{match.Groups[1].Value}'");
                    return;
                }

                log.LogInformation("ProcessModuleLogs function received a new queue message");
                log.LogDebug($"Message content: {queueItem}");

                // Create a BlobServiceClient object which will be used to create a container client
                BlobServiceClient blobServiceClient = new BlobServiceClient(_connectionString);

                // Create container client object
                BlobContainerClient containerClient = blobServiceClient.GetBlobContainerClient(_containerName);

                // Get blob client object
                string blobName = match.Groups[2].Value;
                BlobClient blobClient = containerClient.GetBlobClient(blobName);

                // Read the blob's contents
                Stream blobStream = await blobClient.OpenReadAsync();
                StreamReader reader = new StreamReader(blobStream);
                IoTEdgeLog[] iotEdgeLogs = JsonConvert.DeserializeObject<IoTEdgeLog[]>(reader.ReadToEnd());

                // Convert to logs their final log analytics format
                LogAnalyticsLog[] logAnalyticsLogs = iotEdgeLogs.Select(x => new LogAnalyticsLog(x)).Select(x => { x.ResourceId = _hubResourceId; return x; }).ToArray();

                if (logAnalyticsLogs.Length == 0)
                    return;

                // initialize log analytics class
                AzureLogAnalytics logAnalytics = new AzureLogAnalytics(
                    workspaceId: _workspaceId,
                    workspaceKey: _workspaceKey,
                    logType: _logType,
                    apiVersion: _workspaceApiVersion);

                // because log analytics supports messages up to 30MB,
                // we have to break logs in chunks to fit in on each request
                byte[] logBytes = Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(logAnalyticsLogs));
                double chunks = Math.Ceiling(logBytes.Length / (_logMaxSizeMB * 1024f * 1024f));

                // get right number of items for the logs array
                int steps = Convert.ToInt32(Math.Ceiling(logAnalyticsLogs.Length / chunks));

                int count = 0;
                do
                {
                    int limit = count + steps < logAnalyticsLogs.Length ? count + steps : logAnalyticsLogs.Length;

                    log.LogInformation($"Submitting data collection request for logs {count + 1} - {limit} / {logAnalyticsLogs.Length}");

                    LogAnalyticsLog[] logsChunk = logAnalyticsLogs.Skip(count).Take(limit).ToArray();
                    try
                    {
                        logAnalytics.Post(JsonConvert.SerializeObject(logsChunk));
                        log.LogInformation("Request successful");
                    }
                    catch (Exception e)
                    {
                        log.LogError($"Request failed with exception {e}");
                    }

                    count += steps;
                }
                while (count < iotEdgeLogs.Length);
            }
            catch (Exception e)
            {
                log.LogError($"GetModuleLogs failed with the following exception: {e}");
            }
        }
    }
}