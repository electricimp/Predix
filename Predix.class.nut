// MIT License
//
// Copyright 2017 Electric Imp
//
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
// OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

// Predix Class:
//     Provides an integration with GE Predix IoT platform using 
//     Predix User Account and Authentication (UAA), Asset and Time Series
//     services REST API.
// 
//     Before using this library you need to:
//         - register an account at the Predix platform
//         - add UAA, Assets, Time Series services to your account
//         - create and configure a client using UAA service instance
//         - obtain URLs of UAA, Assets and Time Series service instances
//         - obtain Zone-Id identificators of Assets and Time Series service 
//           instances
//
//     If you want to manage your connected device(s) and see the data from
//     the device(s) in Predix, you may:
//         - create a web application
//         - deploy the web application to the Predix platform
//         - bind UAA, Assets and Time Series services (and any other Predix services
//           your application uses) to the web application
//
//     For more information see Predix Documentation https://www.predix.io/docs
//
//     To instantiate this library you need to have:
//         - UAA service instance URL,
//         - UAA service client id,
//         - UAA service client secret,
//         - Asset service instance URL,
//         - Asset service Zone-Id,
//         - TimeSeries service ingestion URL,
//         - TimeSeries service Zone-Id.
//
//     EI device is represented in the Predix platform as an asset.
//     Every asset is uniquely identified in the scope of one Predix account
//     by a pair <assetType>/<assetId>.
//     Usually <assetType> is a type of device, type of sensor/actuator,
//     your application or use case name or anything else you want.
//     <assetId> is a unique identifier in the scope of a particular <assetType>.
//     <assetId> may have hierarchical naming structure inside or just to be a
//     unique number (e.g. device id).
//     All library methods which operate with assets and ingest data have
//     <assetType>, <assetId> pair as parameters.
//
//     All requests to Predix platform are made asynchronously.
//     Any method that sends a request has an optional callback parameter.
//     If the callback is provided, it is executed when the operation is
//     completed (e.g. a response is received), successfully or not.
//     The callback function has the following signature:
//         cb(status, errMessage, response), where
//             status : int
//                 Status of the operation -
//                 one of the PREDIX_STATUS enum values
//             errMessage : string
//                 Error details, null if the status is PREDIX_STATUS.SUCCESS
//             response : table
//                 HTTP response received as a reply from Predix service, 
//                 can be null.
//                 It contains the following keys and values:
//                     statuscode : HTTP status code
//                     headers    : table of returned HTTP headers
//                     body       : returned HTTP body decoded from JSON (if any)
//
// Dependencies
//     Promise Library - you need to include the latest version
//     of the Promise library to the top of your agent code.

// Predix library operation status
enum PREDIX_STATUS {
    // operation is completed successfully
    SUCCESS,
    // the library detects an error, e.g. the library is wrongly initialized or 
    // a method is called with invalid argument(s). The error details can be 
    // found in the callback errMessage parameter
    LIBRARY_ERROR,
    // HTTP request to Predix service failed. The error details can be found in 
    // the callback errMessage and response parameters
    PREDIX_REQUEST_FAILED,
    // Unexpected response from Predix service. The error details can be found in 
    // the callback errMessage and response parameters
    PREDIX_UNEXPECTED_RESPONSE
};

// Internal Predix library constants
const _PREDIX_TOKEN_RENEW_BEFORE_EXPIRY_SEC = 60;
// Errors produced by the library
const _PREDIX_WRONG_TIME_SERIES_INGEST_URL = "Data ingestion failed: non-HTTP timeSeriesIngestUrl is currently unsupported";
const _PREDIX_UNEXPECTED_UAA_RESPONSE = "Unexpected response from Predix User Account and Authentication service";
const _PREDIX_WRONG_EMPTY_ARGUMENT = "Non empty argument required";
const _PREDIX_REQUEST_FAILED = "Predix request failed with status code:";

class Predix {
    static VERSION = "1.0.0";

    _uaaUrl = null;
    _clientId = null;
    _clientSecret = null;
    _assetUrl = null;
    _assetZoneId = null;
    _timeSeriesIngestUrl = null;
    _timeSeriesZoneId = null;
    
    _accessToken = null;
    _tokenRenewTime = null; 
    _isHttpTimeSeriesIngest = false;
    _libInitialized = null;

    // Predix library constructor
    //
    // Parameters:
    //     uaaUrl : string              Predix UAA service instance URL
    //     clientId : string            Id of a client registered in Predix UAA service
    //     clientSecret : string        Predix UAA client secret
    //     assetUrl : string            Predix Asset service instance URL
    //     assetZoneId : string         Predix Zone ID for Asset service
    //     timeSeriesIngestUrl : string Predix Time Series service ingestion URL
    //     timeSeriesZoneId : string    Predix Zone ID for TimeSeries service
    //
    // Returns:                         Predix library object created
    constructor(uaaUrl, clientId, clientSecret, assetUrl, assetZoneId, timeSeriesIngestUrl, timeSeriesZoneId) {
        _uaaUrl = uaaUrl;
        _clientId = clientId;
        _clientSecret = clientSecret;
        _assetUrl = assetUrl;
        _assetZoneId = assetZoneId;
        _timeSeriesIngestUrl = timeSeriesIngestUrl;
        _timeSeriesZoneId = timeSeriesZoneId;

        _libInitialized = _checkLibStateAndParams(null, _uaaUrl, _clientId, _clientSecret, 
            _assetUrl, _assetZoneId, _timeSeriesIngestUrl, _timeSeriesZoneId);

        if (_timeSeriesIngestUrl != null) {
            // check timeSeriesIngestUrl scheme
            local index = _timeSeriesIngestUrl.find(":");
            if (index != null) {
                local scheme = _timeSeriesIngestUrl.slice(0, index);
                if (scheme == "https" || scheme == "http") {
                    _isHttpTimeSeriesIngest = true;
                }
            }
        }
    }

    // Creates or updates custom asset for the EI device in Predix IoT platform 
    // using Predix Asset service.
    // The asset is uniquely identified by a pair <assetType>, <assetId>.
    // If the asset with this identifier does not exist, it is created.
    // The created asset will be available at <_assetUrl>/<assetType>/<assetId> URL.
    // If the asset with this identifier already exists, it is updated by the new
    // provided properties. All old properties are deleted.
    //
    // Parameters:
    //     assetType : string        Predix asset type, any alphanumeric value 
    //                               with optional underscores or dashes
    //     assetId : string          Id of asset to be created in Predix, any 
    //                               alphanumeric value with optional underscores
    //                               or dashes
    //     assetInfo : table         Asset properties of any format.
    //                               Any property of the device can be specified
    //                               in the format {"<property_name>" : <property_value>, ...}.
    //                               assetInfo can be empty.
    //     cb (optional) : function  Function to execute when response received, 
    //                               the exact format is specified above
    //
    // Returns:                      Nothing
    function createAsset(assetType, assetId, assetInfo, cb = null) {
        if (!_checkLibStateAndParams(cb, assetType, assetId)) {
            return;
        }
        // check access token, then
        // POST to <_assetUrl>/<assetType>
        _accessCheckPromise(cb).
            then(function(msg) {
                local info = !assetInfo ? {} : clone(assetInfo);
                info["uri"] <- format("/%s/%s", assetType, assetId);
                local url = format("%s/%s", _assetUrl, assetType);
                local req = http.post(url, _createHeaders(_assetZoneId), http.jsonencode([info]));
                req.sendasync(function(resp) {
                    _processResponse(resp, cb);
                }.bindenv(this));
            }.bindenv(this));
    }
    
    // Queries custom asset from Predix IoT platform. 
    // If the asset doesn't exist, the callback (if provided) is called with 
    // the status = PREDIX_STATUS.PREDIX_REQUEST_FAILED
    // If the asset exists, the callback (if provided) is called with
    // the status = PREDIX_STATUS.SUCCESS. The asset properties are provided
    // in callback response.body in the format:
    // [
    //   { "uri" : "/<assetType>/<assetId>", 
    //     "<asset_property_name>" : <value>,
    //     ...
    //   }
    // ]
    //
    // Parameters:
    //     assetType : string        Type of the asset
    //     assetId : string          Id of the asset to be queried
    //     cb (optional) : function  Function to execute when response received, 
    //                               the exact format is specified above
    //
    // Returns:                      Nothing
    function queryAsset(assetType, assetId, cb = null) {
        if (!_checkLibStateAndParams(cb, assetType, assetId)) {
            return;
        }
        // check access token, then
        // GET to <_assetUrl>/<assetType>/<assetId>
        _accessCheckPromise(cb).
            then(function(msg) {
                local url = format("%s/%s/%s", _assetUrl, assetType, assetId);
                local req = http.get(url, _createHeaders(_assetZoneId));
                req.sendasync(function(resp) {
                    _processResponse(resp, cb);
                }.bindenv(this));
            }.bindenv(this));
    }
    
    // Deletes custom asset from Predix IoT platform.
    // If the asset doesn't exist, the method does nothing and the callback
    // (if provided) is called with the status = PREDIX_STATUS.SUCCESS
    //
    // Parameters:
    //     assetType : string        Type of the asset
    //     assetId : string          Id of the asset to be deleted
    //     cb (optional) : function  Function to execute when response received,
    //                               the exact format is specified above
    //
    // Returns:                      Nothing
    function deleteAsset(assetType, assetId, cb = null) {
        if (!_checkLibStateAndParams(cb, assetType, assetId)) {
            return;
        }
        // check access token, then
        // DELETE to <_assetUrl>/<assetType>/<assetId>
        _accessCheckPromise(cb).
            then(function(msg) {
                local url = format("%s/%s/%s", _assetUrl, assetType, assetId);
                local req = http.httpdelete(url, _createHeaders(_assetZoneId));
                req.sendasync(function(resp) {
                    _processResponse(resp, cb);
                }.bindenv(this));
            }.bindenv(this));
    }

    // Ingests data to Predix IoT platform using Predix Time Series service.
    // Every <data_value> from data parameter formatted as {"<data_name>" : "<data_value>", ...}
    // is ingested to Predix Time Series with tag name <assetType>.<assetId>.<data_name>
    //
    // Parameters:
    //     assetType : string        Type of the asset
    //     assetId : string          Id of asset whose data is posted
    //     data : table              Data to be ingested to Predix Time Series,
    //                               table formatted as {"<data_name>" : "<data_value>", ...}
    //     ts (optional) : integer   Data measurement timestamp in seconds since epoch.
    //                               If not specified, the current timestamp is inserted and
    //                               sent by the library.
    //     cb (optional) : function  Function to execute when response received,
    //                               the exact format is specified above 
    //
    // Returns:                      Nothing
    function ingestData(assetType, assetId, data, ts = null, cb = null) {
        if (!_checkLibStateAndParams(cb, assetType, assetId, data)) {
            return;
        }
        // Predix Time Series service uses WebSocket protocol for data ingestion.
        // The current implementation requires external http-to-websocket proxy that
        // receives HTTP requests from the library and resends them to the Predix 
        // Time Series service through WebSocket
        if (!_isHttpTimeSeriesIngest) {
            _handleError(PREDIX_STATUS.LIBRARY_ERROR, _PREDIX_WRONG_TIME_SERIES_INGEST_URL, null, cb);
            return;
        }
        // check access token, then
        // POST to <_timeSeriesIngestUrl>
        _accessCheckPromise(cb).
            then(function(msg) {
                if (!ts) {
                    ts = time();
                }
                local tsMillis = format("%d000", ts);
                local body = [];
                foreach (sensor, value in data) {
                    local sensorData = {
                        "name" : format("%s.%s.%s", assetType, assetId, sensor),
                        "datapoints" : [[tsMillis, value]],
                    };
                    body.append(sensorData);
                }
                local predixData = {
                    "messageId" : tsMillis,
                    "body" : body
                };
                local req = http.post(_timeSeriesIngestUrl, _createHeaders(_timeSeriesZoneId), http.jsonencode(predixData));
                req.sendasync(function(resp) {
                    _processResponse(resp, cb);
                }.bindenv(this));
            }.bindenv(this));
    }

    // -------------------- PRIVATE METHODS -------------------- //

    // Checks Predix UAA access token and recreates it if needed.
    //
    // Parameters:
    //     cb : function    Function to execute when response received,
    //                      the exact format is specified above
    //
    // Returns:             Promise that resolves when access token is successfully 
    //                      obtained, or rejects with an error
    function _accessCheckPromise(cb) {
        return Promise(function(resolve, reject) {
            if (_accessToken == null || _tokenRenewTime < time()) {
                // Request new access token
                // POST to <_uaaUrl>/oauth/token
                local url = format("%s/oauth/token", _uaaUrl);
                local auth = http.base64encode(format("%s:%s", _clientId, _clientSecret));
                local headers = {
                    "Authorization" : format("Basic %s", auth),
                    "Content-Type" : "application/x-www-form-urlencoded"
                };
                local body = format("client_id=%s&grant_type=client_credentials", _clientId);
                local req = http.post(url, headers, body);
                req.sendasync(function(resp) {
                    _processResponse(resp, function(status, errMessage, resp) {
                        if (status == PREDIX_STATUS.SUCCESS) {
                            if ("access_token" in resp.body && "expires_in" in resp.body) {
                                _accessToken = resp.body["access_token"];
                                _tokenRenewTime = time() + resp.body["expires_in"] - _PREDIX_TOKEN_RENEW_BEFORE_EXPIRY_SEC;
                                return resolve("Access token created successfully");
                            }
                            _handleError(PREDIX_STATUS.PREDIX_UNEXPECTED_RESPONSE, _PREDIX_UNEXPECTED_UAA_RESPONSE, resp, cb);
                            return reject(_PREDIX_UNEXPECTED_UAA_RESPONSE);
                        }
                        else {
                            // we encountered an error
                            _handleError(status, errMessage, resp, cb);
                            return reject(errMessage);
                        }
                    }.bindenv(this));
                }.bindenv(this));
            }
            else {
                return resolve("Access token is valid");
            }
        }.bindenv(this));
    }

    // Creates HTTP headers for Predix Asset and Time Series services requests.
    //
    // Parameters:
    //     predixZoneId : string     Predix Zone ID of the service instance
    //
    // Returns:                      request header table
    function _createHeaders(predixZoneId) {
        return {
            "Authorization" : format("Bearer %s", _accessToken),
            "Predix-Zone-Id" : predixZoneId,
            "Content-Type" : "application/json"
        };
    }

    // Processes responses from Predix services.
    //
    // Parameters:
    //     resp : table              The response object from Predix
    //     cb : function             The callback function passed into the request 
    //                               or null, the exact format is specified above
    //
    // Returns:             Nothing
    function _processResponse(resp, cb) {
        local statuscode = resp.statuscode;
        local status = PREDIX_STATUS.SUCCESS;
        local errMessage = null;
        if (statuscode < 200 || statuscode >= 300) {
            status = PREDIX_STATUS.PREDIX_REQUEST_FAILED;
            errMessage = format("%s %i", _PREDIX_REQUEST_FAILED, statuscode);
        }
        try {
            resp.body = (resp.body == "") ? {} : http.jsondecode(resp.body);
        } catch (e) {
            if (status == PREDIX_STATUS.SUCCESS) {
                status = PREDIX_STATUS.PREDIX_UNEXPECTED_RESPONSE;
                errMessage = e;
            }
        }
        if (cb) {
            imp.wakeup(0, function() {
                cb(status, errMessage, resp);
            });
        }
    }

    // Checks that the library is initialized successfully and all of the 
    // optional parameters are not null or empty string/table. 
    // Executes the callback with PREDIX_STATUS.LIBRARY_ERROR status if any of 
    // the checks is failed.
    //
    // Parameters:
    //     cb : function          The callback function passed into the request 
    //                            or null, the exact format is specified above
    //     optional parameters    values to be validated
    //
    // Returns:                   true if the library is initialized successfully 
    //                            and all of the optional parameters are valid, 
    //                            false otherwise
    function _checkLibStateAndParams(cb, ...) {
        local isValid = _libInitialized != null ? _libInitialized : true;
        if (isValid) {
            foreach (param in vargv) {
                if (!param || typeof param == "string" && param.len() == 0 ||
                    typeof param == "table" && param.len() == 0) {
                    isValid = false;
                    break;
                }
            }
        }
        if (!isValid) {
            _handleError(PREDIX_STATUS.LIBRARY_ERROR, _PREDIX_WRONG_EMPTY_ARGUMENT, null, cb)
        }
        return isValid;
    }

    // Handles an error occurred during the library methods execution
    //
    // Parameters:
    //     status : int              status of the library method call, one of 
    //                               the PREDIX_STATUS enum values
    //     errMessage : string       error details
    //     resp : table              HTTP response received as a reply from the 
    //                               Predix platform, can be null.
    //     cb : function             The callback function passed into the request 
    //                               or null, the exact format is specified above
    //
    // Returns:                      Nothing
    function _handleError(status, errMessage, resp, cb) {
        _logError(errMessage);
        if (cb) {
            imp.wakeup(0, function() {
                cb(status, errMessage, resp);
            });            
        }
    }

    // Logs an error occurred during the library methods execution
    //
    // Parameters:
    //     errMessage : string       the error message occurred
    //
    // Returns:                      Nothing
    function _logError(errMessage) {
        server.error("[Predix] " + errMessage);
    }
}
