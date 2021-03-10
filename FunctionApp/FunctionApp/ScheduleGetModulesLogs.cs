using System;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Host;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using System.Net.Http;
using Newtonsoft.Json;
using System.Threading.Tasks;

namespace FunctionApp
{
    public static class ScheduleGetModulesLogs
    {
        private static string _iotHubDeviceId = Environment.GetEnvironmentVariable("IotHubDeviceId");
        private static string _logsIdRegex = Environment.GetEnvironmentVariable("LogsIdRegex");
        private static string _logsSince = Environment.GetEnvironmentVariable("LogsSince");
        private static int _logsLogLevel = Convert.ToInt32(Environment.GetEnvironmentVariable("LogsLogLevel"));
        private static int? _logsTail = Convert.ToInt32(Environment.GetEnvironmentVariable("LogsTail"));
        private static string _logsEncoding = Environment.GetEnvironmentVariable("LogsEncoding");
        private static string _logsContentType = Environment.GetEnvironmentVariable("LogsContentType");
        private static string _getModuleLogsUrl = "https://localhost/api/GetModuleLogs";
        
        [FunctionName("ScheduleGetModulesLogs")]
        public static async Task Run([TimerTrigger("0 0 */1 * * *")]TimerInfo myTimer, ILogger log)
        {
            try
            {
                log.LogInformation($"ScheduleGetModulesLogs function executed at: {DateTime.Now}");

                HttpResponseMessage response = new HttpResponseMessage();
                using (var client = new HttpClient())
                {
                    var data = new
                    {
                        deviceId = _iotHubDeviceId,
                        moduleId = "edgeAgent",
                        methodName = "UploadModuleLogs",
                        methodPayload = new
                        {
                            id = _logsIdRegex,
                            filter = new
                            {
                                since = _logsSince,
                                loglevel = _logsLogLevel,
                                tail = _logsTail,
                            }
                        }
                    };

                    using (var content = new StringContent(JsonConvert.SerializeObject(data)))
                    {
                        response = await client.PostAsync(_getModuleLogsUrl, content);
                    }
                }

                if (response.StatusCode == System.Net.HttpStatusCode.OK)
                    log.LogInformation($"HTTP call to GetModuleLogs completed successfully");
                else
                {
                    string responseMessage = await response.Content.ReadAsStringAsync();
                    log.LogError($"HTTP call to GetModuleLogs failed with status code {response.StatusCode} and message {responseMessage}");
                }
            }
            catch (Exception e)
            {
                log.LogError($"ScheduleGetModulesLogs failed with the following exception: {e}");
            }
        }
    }
}
