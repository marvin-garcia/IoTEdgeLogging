using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Text;

namespace FunctionApp.Models
{
    public class IoTEdgeLog
    {
        [JsonProperty("iothub")]
        public string IoTHub { get; set; }
        [JsonProperty("device")]
        public string DeviceId { get; set; }
        [JsonProperty("id")]
        public string ModuleId { get; set; }
        [JsonProperty("stream")]
        public string Stream { get; set; }
        [JsonProperty("loglevel")]
        public int LogLevel { get; set; }
        [JsonProperty("text")]
        public string Text { get; set; }
        [JsonProperty("timestamp")]
        public DateTime Timestamp { get; set; }
    }

    public class LogAnalyticsLog
    {
        [JsonProperty("iotHub")]
        public string IoTHub { get; set; }
        [JsonProperty("deviceId")]
        public string DeviceId { get; set; }
        [JsonProperty("moduleId")]
        public string ModuleId { get; set; }
        [JsonProperty("stream")]
        public string Stream { get; set; }
        [JsonProperty("logLevel")]
        public int LogLevel { get; set; }
        [JsonProperty("message")]
        public string Message { get; set; }
        [JsonProperty("timestamp")]
        public DateTime Timestamp { get; set; }

        public LogAnalyticsLog(IoTEdgeLog iotEdgeLog)
        {
            this.IoTHub = iotEdgeLog.IoTHub;
            this.DeviceId = iotEdgeLog.DeviceId;
            this.ModuleId = iotEdgeLog.ModuleId;
            this.Stream = iotEdgeLog.Stream;
            this.LogLevel = iotEdgeLog.LogLevel;
            this.Message = iotEdgeLog.Text;
            this.Timestamp = iotEdgeLog.Timestamp;
        }
    }
}
