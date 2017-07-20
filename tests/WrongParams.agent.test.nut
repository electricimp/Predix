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

const UAA_URL                   = "@{PREDIX_UAA_URL}";
const CLIENT_ID                 = "@{PREDIX_CLIENT_ID}";
const CLIENT_SECRET             = "@{PREDIX_CLIENT_SECRET}";
const ASSET_URL                 = "@{PREDIX_ASSET_URL}";
const ASSET_ZONE_ID             = "@{PREDIX_ASSET_ZONE_ID}";
const TIME_SERIES_INGEST_URL    = "@{PREDIX_TIME_SERIES_INGEST_URL}";
const TIME_SERIES_ZONE_ID       = "@{PREDIX_TIME_SERIES_ZONE_ID}";

const ASSET_TYPE = "test_device";
const ASSET_ID = "id_123";

// Test case for wrong parameters of Predix library methods.
// Some use cases are not tested, because the library calls server.error(...) for them and it 
// currently terminates impTest execution with 'Agent Runtime Error'.
// These are: 
// - nulls and empty parameters of any Predix library method
// - wrong uaaUrl, clientId or clientSecret
// - non HTTP timeSeriesIngestUrl
class WrongParamsTestCase extends ImpTestCase {
    _predixConfig = {
        "uaaUrl" : UAA_URL, 
        "clientId" : CLIENT_ID, 
        "clientSecret" : CLIENT_SECRET, 
        "assetUrl" : ASSET_URL, 
        "assetZoneId" : ASSET_ZONE_ID, 
        "timeSeriesIngestUrl" : TIME_SERIES_INGEST_URL, 
        "timeSeriesZoneId" : TIME_SERIES_ZONE_ID
    };

    _sensorsData = {
        "temperature" : 23,
        "humidity" : 50
    };

    _assetInfo = {};

    _wrongAssetTypes = ["test!", "test?", "<test", "test>"];
    _wrongAssetIds = ["id$", "id&", "id(", "(id", "=id"];

    // Tests asset operation with invalid assetUrl
    function testWrongAssetUrl() {
        local config = clone(_predixConfig);
        config.assetUrl = format("%sabcdefg", config.assetUrl);
        return _testWrongAssetParams(config);
    }

    // Tests asset operation with invalid assetZoneId
    function testWrongAssetZoneId() {
        local config = clone(_predixConfig);
        config.assetZoneId = format("%sabc", config.assetZoneId);
        return _testWrongAssetParams(config);
    }

    // Tests ingestData with invalid timeSeriesIngestUrl
    function testWrongTimeSeriesIngestUrl() {
        local config = clone(_predixConfig);
        config.timeSeriesIngestUrl = format("%sabcdefg", config.timeSeriesIngestUrl);
        return _testWrongTimeSeriesParams(config);
    }

    // Tests ingestData with invalid timeSeriesZoneId
    function testWrongTimeSeriesZoneId() {
        local config = clone(_predixConfig);
        config.timeSeriesZoneId = format("%sabc", config.timeSeriesZoneId);
        return _testWrongTimeSeriesParams(config);
    }

    // Tests createAsset with invalid characters in assetType
    function testWrongAssetType() {
        foreach (wrongAssetType in _wrongAssetTypes) {
            _testWrongAssetTypeOrId(wrongAssetType, ASSET_ID);
        }
    }

    // Tests createAsset with invalid characters in assetId
    function testWrongAssetId() {
        foreach (wrongAssetId in _wrongAssetIds) {
            _testWrongAssetTypeOrId(ASSET_TYPE, wrongAssetId);
        }
    }

    function _testWrongAssetTypeOrId(assetType, assetId) {
        local config = _predixConfig;
        local predix = Predix(config.uaaUrl, config.clientId, config.clientSecret, 
            config.assetUrl, config.assetZoneId, config.timeSeriesIngestUrl, config.timeSeriesZoneId);
        return Promise(function (resolve, reject) {
            predix.createAsset(assetType, assetId, _assetInfo, function(status, errMessage, response) {
                if (status == PREDIX_STATUS.SUCCESS) {
                    return reject("Wrong param ignored");
                }
                return resolve("");
            }.bindenv(this));
        }.bindenv(this));
    }

    function _testWrongAssetParams(config) {
        local predix = Predix(config.uaaUrl, config.clientId, config.clientSecret, 
            config.assetUrl, config.assetZoneId, config.timeSeriesIngestUrl, config.timeSeriesZoneId);
        return Promise(function (resolve, reject) {
            // deleteAsset with valid params returns PREDIX_STATUS.SUCCESS in any case
            predix.deleteAsset(ASSET_TYPE, ASSET_ID, function(status, errMessage, response) {
                if (status == PREDIX_STATUS.SUCCESS) {
                    return reject("Wrong param ignored");
                }
                return resolve("");
            }.bindenv(this));
        }.bindenv(this));
    }

    function _testWrongTimeSeriesParams(config) {
        local predix = Predix(config.uaaUrl, config.clientId, config.clientSecret, 
            config.assetUrl, config.assetZoneId, config.timeSeriesIngestUrl, config.timeSeriesZoneId);
        return Promise(function (resolve, reject) {
            predix.ingestData(ASSET_TYPE, ASSET_ID, _sensorsData, null, function(status, errMessage, response) {
                if (status == PREDIX_STATUS.SUCCESS) {
                    return reject("Wrong param ignored");
                }
                return resolve("");
            }.bindenv(this));
        }.bindenv(this));
    }
}

