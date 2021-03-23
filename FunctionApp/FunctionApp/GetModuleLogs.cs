using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Azure.Devices;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;

namespace FunctionApp
{
    public static class GetModuleLogs
    {
        private static ServiceClient _serviceClient;
        private static string _hubConnectionString = Environment.GetEnvironmentVariable("HubConnectionString");

        [FunctionName("GetModuleLogs")]
        public static async Task<HttpResponseMessage> Run(
            [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequest req,
            ILogger log)
        {
            try
            {
                log.LogInformation("GetModuleLogs processed a request.");

                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                dynamic data = JsonConvert.DeserializeObject(requestBody);
                string deviceId = data.deviceId;
                string moduleId = data.moduleId;
                string methodName = data.methodName;
                string methodPayload = JsonConvert.SerializeObject(data.methodPayload);

                _serviceClient = ServiceClient.CreateFromConnectionString(_hubConnectionString);
                var deviceMethod = new CloudToDeviceMethod(methodName);
                deviceMethod.SetPayloadJson(methodPayload);

                var result = await _serviceClient.InvokeDeviceMethodAsync(deviceId, moduleId, deviceMethod);
                
                return new HttpResponseMessage((HttpStatusCode)result.Status)
                {
                    Content = new StringContent(result.GetPayloadAsJson())
                };
            }
            catch (Exception e)
            {
                log.LogError($"GetModuleLogs failed with the following exception: {e}");
                return new HttpResponseMessage(HttpStatusCode.InternalServerError)
                {
                    Content = new StringContent(e.ToString()),
                };
            }
        }
    }
}