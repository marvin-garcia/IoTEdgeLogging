using System;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Host;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using System.Net.Http;
using Newtonsoft.Json;
using System.Threading.Tasks;
using Azure.Storage.Blobs;
using Microsoft.Azure.Devices;
using Newtonsoft.Json.Linq;
using FunctionApp.Models;
using System.Collections.Generic;

namespace FunctionApp
{
    public static class ScheduleGetModulesLogs
    {
        private static string _iotHubConnectionString = Environment.GetEnvironmentVariable("HubConnectionString");
        private static string _iotDeviceQuery = Environment.GetEnvironmentVariable("DeviceQuery");
        private static string _logsIdRegex = Environment.GetEnvironmentVariable("LogsIdRegex");
        private static string _logsSince = Environment.GetEnvironmentVariable("LogsSince");
        private static string _logsRegex = Environment.GetEnvironmentVariable("LogsRegex");
        private static string _logsLogLevel = Environment.GetEnvironmentVariable("LogsLogLevel");
        private static string _logsUntil = Environment.GetEnvironmentVariable("LogsUntil");
        private static string _logsTail = Environment.GetEnvironmentVariable("LogsTail");
        private static string _logsEncoding = Environment.GetEnvironmentVariable("LogsEncoding");
        private static string _logsContentType = Environment.GetEnvironmentVariable("LogsContentType");
        private static string _getModuleLogsUrl = Environment.GetEnvironmentVariable("GetModuleLogsUrl");
        private static string _connectionString = Environment.GetEnvironmentVariable("StorageConnectionString");
        private static string _containerName = Environment.GetEnvironmentVariable("ContainerName");
        
        [FunctionName("ScheduleGetModulesLogs")]
        public static async Task Run([TimerTrigger("0 0 */1 * * *")]TimerInfo myTimer, ILogger log)
        //public static async Task Run([TimerTrigger("0 */1 * * * *")] TimerInfo myTimer, ILogger log)
        {
            try
            {
                log.LogInformation($"ScheduleGetModulesLogs function executed at: {DateTime.Now}");

                #region cast and fix payload property types
                int? logLevel = null;
                if (!string.IsNullOrEmpty(_logsLogLevel))
                    logLevel = Convert.ToInt32(_logsLogLevel);

                int? logsTail = null;
                if (!string.IsNullOrEmpty(_logsTail))
                    logsTail = Convert.ToInt32(_logsTail);

                if (string.IsNullOrEmpty(_logsUntil))
                    _logsUntil = null;

                if (string.IsNullOrEmpty(_logsRegex))
                    _logsRegex = null;

                if (string.IsNullOrEmpty(_logsEncoding))
                    _logsEncoding = "none";

                if (string.IsNullOrEmpty(_logsContentType))
                    _logsContentType = "json";
                #endregion

                HttpResponseMessage response = new HttpResponseMessage();
                using (var client = new HttpClient())
                {
                    BlobContainerClient container = new BlobContainerClient(_connectionString, _containerName);
                    Azure.Storage.Sas.BlobContainerSasPermissions permissions = Azure.Storage.Sas.BlobContainerSasPermissions.All;
                    DateTimeOffset expiresOn = new DateTimeOffset(DateTime.UtcNow.AddHours(12));
                    Uri sasUri = container.GenerateSasUri(permissions, expiresOn);

                    var registryManager = RegistryManager.CreateFromConnectionString(_iotHubConnectionString);
                    var query = registryManager.CreateQuery(_iotDeviceQuery);
                    var devices = await query.GetNextAsJsonAsync();

                    foreach (var device in devices)
                    {
                        JObject deviceJson = JsonConvert.DeserializeObject<JObject>(device);

                        var data = new
                        {
                            deviceId = deviceJson.GetValue("deviceId"),
                            moduleId = "$edgeAgent",
                            methodName = "UploadModuleLogs",
                            methodPayload = new UploadModuleLogs()
                            {
                                SchemaVersion = "1.0",
                                SasUrl = sasUri.AbsoluteUri,
                                Encoding = _logsEncoding,
                                ContentType = _logsContentType,
                                Items = new List<UploadModuleLogs.Item>()
                                {
                                    new UploadModuleLogs.Item()
                                    {
                                        Id = _logsIdRegex,
                                        Filter = new UploadModuleLogs.Filter()
                                        {
                                            Since = _logsSince,
                                            Regex = _logsRegex,
                                            LogLevel = logLevel,
                                            Tail = logsTail,
                                        }
                                    }
                                }
                            }
                        };

                        string serializedData = JsonConvert.SerializeObject(
                            data,
                            Formatting.None,
                            new JsonSerializerSettings 
                            { 
                                NullValueHandling = NullValueHandling.Ignore 
                            });

                        using var content = new StringContent(serializedData);
                        log.LogInformation($"Calling endpoint {_getModuleLogsUrl} to invoke module logs upload method");
                        response = await client.PostAsync(_getModuleLogsUrl, content);

                        if (response.StatusCode == System.Net.HttpStatusCode.OK)
                        {
                            log.LogInformation($"HTTP call to GetModuleLogs completed successfully");
                        }
                        else
                        {
                            string responseMessage = await response.Content.ReadAsStringAsync();
                            log.LogError($"HTTP call to GetModuleLogs failed with status code {response.StatusCode} and message {responseMessage}");
                        }
                    }
                }
            }
            catch (Exception e)
            {
                log.LogError($"ScheduleGetModulesLogs failed with the following exception: {e}");
            }
        }
    }
}
