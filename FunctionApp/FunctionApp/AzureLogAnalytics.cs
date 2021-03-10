using System;
using System.IO;
using System.Net;
using System.Text;
using System.Security.Cryptography;

namespace FunctionApp
{
    public class AzureLogAnalytics
    {
        private string _workspaceId { get; set; }
        private string _workspaceKey { get; set; }
        private string _apiVersion { get; set; }
        private string _logType { get; set; }

        public AzureLogAnalytics(string workspaceId, string workspaceKey, string logType, string apiVersion = "2016-04-01")
        {
            this._workspaceId = workspaceId;
            this._workspaceKey = workspaceKey;
            this._logType = logType;
            this._apiVersion = apiVersion;
        }
        public void Post(string json)
        {
            string requestUriString = $"https://{_workspaceId}.ods.opinsights.azure.com/api/logs?api-version={_apiVersion}";
            DateTime dateTime = DateTime.UtcNow;
            string dateString = dateTime.ToString("r");
            string signature = GetSignature("POST", json.Length, "application/json", dateString, "/api/logs");
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(requestUriString);
            request.ContentType = "application/json";
            request.Method = "POST";
            request.Headers["Log-Type"] = _logType;
            request.Headers["x-ms-date"] = dateString;
            request.Headers["Authorization"] = signature;
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
                return $"SharedKey {_workspaceId}:{Convert.ToBase64String(encryptor.ComputeHash(bytes))}";
            }
        }
    }
}
