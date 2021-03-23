using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json.Serialization;

namespace FunctionApp.Models
{
    [Serializable]
    public class UploadModuleLogs
    {
        [Serializable]
        public class Filter
        {
            [JsonPropertyName("tail")]
            public int? Tail { get; set; }
            [JsonPropertyName("since")]
            public string Since { get; set; }
            [JsonPropertyName("until")]
            public string Until { get; set; }
            [JsonPropertyName("loglevel")]
            public int? LogLevel { get; set; }
            [JsonPropertyName("regex")]
            public string Regex { get; set; }
        }

        [Serializable]
        public class Item
        {
            [JsonPropertyName("id")]
            public string Id { get; set; }
            [JsonPropertyName("filter")]
            public Filter Filter { get; set; }
        }

        [JsonPropertyName("schemaVersion")]
        public string SchemaVersion { get; set; }
        [JsonPropertyName("sasUrl")]
        public string SasUrl { get; set; }
        [JsonPropertyName("items")]
        public List<Item> Items { get; set; }
        [JsonPropertyName("encoding")]
        public string Encoding { get; set; }
        [JsonPropertyName("contentType")]
        public string ContentType { get; set; }
    }
}
