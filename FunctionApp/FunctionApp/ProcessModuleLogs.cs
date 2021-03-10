using System;
using System.IO;
using System.Linq;
using System.Text;
using FunctionApp.Models;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Host;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

namespace FunctionApp
{
    public static class ProcessModuleLogs
    {
        private static string _workspaceId = Environment.GetEnvironmentVariable("WorkspaceId");
        private static string _workspaceKey = Environment.GetEnvironmentVariable("WorkspaceKey");
        private static string _workspaceApiVersion = Environment.GetEnvironmentVariable("WorkspaceApiVersion");
        private static string _logType = Environment.GetEnvironmentVariable("LogType");
        private static int _logMaxSizeMB = Convert.ToInt32(Environment.GetEnvironmentVariable("LogsMaxSizeMB"));

        [FunctionName("ProcessModuleLogs")]
        public static void Run(
            [BlobTrigger("iotedgelogs/{name}", Connection = "StorageConnectionString")]Stream myBlob,
            string name,
            ILogger log)
        {
            try
            {
                log.LogInformation($"ProcessModuleLogs Processed blob\n Name:{name} \n Size: {myBlob.Length} Bytes");
                
                // convert logs to intended format class
                StreamReader reader = new StreamReader(myBlob);
                IoTEdgeLog[] iotEdgeLogs = JsonConvert.DeserializeObject<IoTEdgeLog[]>(reader.ReadToEnd());
                LogAnalyticsLog[] logAnalyticsLogs = iotEdgeLogs.Select(x => new LogAnalyticsLog(x)).ToArray();

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
                    int limit = count + steps < logAnalyticsLogs.Length ? count + steps: logAnalyticsLogs.Length;

                    log.LogInformation($"Writing logs {count} - {limit} / {logAnalyticsLogs.Length} to Log Analytics Workspace");

                    LogAnalyticsLog[] logsChunk = logAnalyticsLogs.Skip(count).Take(limit).ToArray();
                    logAnalytics.Post(JsonConvert.SerializeObject(logsChunk));

                    count += steps;
                }
                while (count < iotEdgeLogs.Length);
            }
            catch (Exception e)
            {
                log.LogError($"GetModuleLogs failed with the following exception: {e}");
                throw e;
            }
        }
    }
}
