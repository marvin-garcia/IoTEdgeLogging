using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using Newtonsoft.Json;
using Microsoft.Azure.Devices;
using Newtonsoft.Json.Linq;
using System;

namespace FunctionApp
{
    public static class GetModuleLogs
    {
        private static ServiceClient _serviceClient;
        private static string _hubConnectionString = Environment.GetEnvironmentVariable("HubConnectionString");

        [FunctionName("GetModuleLogs")]
        public static async Task<IActionResult> Run(
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

                return new OkObjectResult(result);
            }
            catch (Exception e)
            {
                log.LogError($"GetModuleLogs failed with the following exception: {e}");
                return new BadRequestObjectResult(e);
            }
        }
    }
}