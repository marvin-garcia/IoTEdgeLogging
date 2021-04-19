using System;
using System.IO;
using System.Net;
using System.Text;
using System.Security.Cryptography;

namespace FunctionApp
{
    public class AzureLogAnalytics
    {
        public string WorkspaceId { get; set; }
        private string _workspaceKey { get; set; }
        public string ApiVersion { get; set; }
        public string LogType { get; set; }
        public string ResourceId { get; set; }

        public AzureLogAnalytics(string workspaceId, string workspaceKey, string logType, string apiVersion = "2016-04-01", string resourceId = null)
        {
            this.WorkspaceId = workspaceId;
            this._workspaceKey = workspaceKey;
            this.LogType = logType;
            this.ApiVersion = apiVersion;
            this.ResourceId = resourceId;
        }

        public void Post(string json)
        {
            string requestUriString = $"https://{WorkspaceId}.ods.opinsights.azure.com/api/logs?api-version={ApiVersion}";
            DateTime dateTime = DateTime.UtcNow;
            string dateString = dateTime.ToString("r");
            string signature = GetSignature("POST", json.Length, "application/json", dateString, "/api/logs");
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(requestUriString);
            request.ContentType = "application/json";
            request.Method = "POST";
            request.Headers["Log-Type"] = LogType;
            request.Headers["x-ms-date"] = dateString;
            request.Headers["Authorization"] = signature;

            if (!string.IsNullOrEmpty(this.ResourceId))
                request.Headers["x-ms-AzureResourceId"] = this.ResourceId;

            byte[] content = Encoding.UTF8.GetBytes(json);
            using (Stream requestStreamAsync = request.GetRequestStream())
            {
                requestStreamAsync.Write(content, 0, content.Length);
            }
            using (HttpWebResponse responseAsync = (HttpWebResponse)request.GetResponse())
            {
                if (responseAsync.StatusCode != HttpStatusCode.OK && responseAsync.StatusCode != HttpStatusCode.Accepted)
                {
                    Stream responseStream = responseAsync.GetResponseStream();
                    if (responseStream != null)
                    {
                        using (StreamReader streamReader = new StreamReader(responseStream))
                        {
                            throw new Exception(streamReader.ReadToEnd());
                        }
                    }
                }
            }
        }

        private string GetSignature(string method, int contentLength, string contentType, string date, string resource)
        {
            string message = $"{method}\n{contentLength}\n{contentType}\nx-ms-date:{date}\n{resource}";
            byte[] bytes = Encoding.UTF8.GetBytes(message);
            using (HMACSHA256 encryptor = new HMACSHA256(Convert.FromBase64String(_workspaceKey)))
            {
                return $"SharedKey {WorkspaceId}:{Convert.ToBase64String(encryptor.ComputeHash(bytes))}";
            }
        }
    }
}
