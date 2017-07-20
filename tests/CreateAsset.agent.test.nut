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
const ASSET_TYPE_2 = "test_device_2";
const ASSET_ID = "id_123";
const ASSET_ID_2 = "id_789";

// Test case for createAsset methods of Predix library
class CreateAssetTestCase extends ImpTestCase {
    _assetInfo1 = {
        "description" : "test device",
        "location" : "home",
        "metaInfo" : {
            "macAddress" : "12345",
            "swVersion" : "v1.2.3"
        }
    };
    _assetInfo2 = {
        "manufacturer" : "electric imp",
        "sensors" : ["temperature", "humidity"]
    };

    _predix = null;

    // Initializes Predix library, deletes the asset to be created, if exists
    function setUp() {
        _predix = Predix(UAA_URL, CLIENT_ID, CLIENT_SECRET, 
            ASSET_URL, ASSET_ZONE_ID, TIME_SERIES_INGEST_URL, TIME_SERIES_ZONE_ID);
        _predix.queryAsset(ASSET_TYPE, ASSET_ID, function(status, errMessage, response) {
            if (status == PREDIX_STATUS.SUCCESS) {
                _predix.deleteAsset(ASSET_TYPE, ASSET_ID);
            }
        }.bindenv(this));
    }

    // Tests asset creation and checks assetInfo using queryAsset
    function testCreateAsset() {
        return Promise(function (resolve, reject) {
            _predix.createAsset(ASSET_TYPE, ASSET_ID, _assetInfo1, function(status, errMessage, response) {
                if (status != PREDIX_STATUS.SUCCESS) {
                    return reject("createAsset failed:" + errMessage);
                }
                _predix.queryAsset(ASSET_TYPE, ASSET_ID, function(status, errMessage, response) {
                    if (status != PREDIX_STATUS.SUCCESS) {
                        return reject("queryAsset failed:" + errMessage);
                    }
                    if (response.body == null || typeof response.body != "array" || response.body.len() == 0) {
                        return reject("Unexpected queryAsset response body");
                    }
                    if (!_compareAssetInfo(_assetInfo1, response.body[0], true)) {
                        return reject("Wrong assetInfo");
                    }
                    _predix.deleteAsset(ASSET_TYPE, ASSET_ID, function(status, errMessage, response) {
                        if (status != PREDIX_STATUS.SUCCESS) {
                            return reject("deleteAsset failed:" + errMessage);
                        }
                        return resolve("");
                    }.bindenv(this));
                }.bindenv(this));
            }.bindenv(this));
        }.bindenv(this));
    }

    // Test asset creation and update, then checks assetInfo using queryAsset
    function testCreateAndUpdateAsset() {
        return Promise(function (resolve, reject) {
            _predix.createAsset(ASSET_TYPE, ASSET_ID, _assetInfo1, function(status, errMessage, response) {
                if (status != PREDIX_STATUS.SUCCESS) {
                    return reject("createAsset failed:" + errMessage);
                }
                _predix.createAsset(ASSET_TYPE, ASSET_ID, _assetInfo2, function(status, errMessage, response) {
                    if (status != PREDIX_STATUS.SUCCESS) {
                        return reject(errMessage);
                    }
                    _predix.queryAsset(ASSET_TYPE, ASSET_ID, function(status, errMessage, response) {
                        if (status != PREDIX_STATUS.SUCCESS) {
                            return reject("queryAsset failed:" + errMessage);
                        }
                        if (response.body == null || typeof response.body != "array" || response.body.len() == 0) {
                            return reject("Unexpected queryAsset response body");
                        }
                        if (!_compareAssetInfo(_assetInfo2, response.body[0], true) ||
                            !_compareAssetInfo(_assetInfo1, response.body[0], false)) {
                            return reject("Wrong assetInfo");
                        }
                        _predix.deleteAsset(ASSET_TYPE, ASSET_ID, function(status, errMessage, response) {
                            if (status != PREDIX_STATUS.SUCCESS) {
                                return reject("deleteAsset failed:" + errMessage);
                            }
                            resolve("");
                        }.bindenv(this));
                    }.bindenv(this));
                }.bindenv(this));
            }.bindenv(this));
        }.bindenv(this));
    }

    // Tests asset uniqueness. Every asset is uniquely identified by a pair <assetType>/<assetId>.
    // Creates assets with different assetType and identical assetId.
    function testAssetUniqueness() {
        return _createAndCheckTwoAssets(ASSET_TYPE, ASSET_ID, _assetInfo1, ASSET_TYPE_2, ASSET_ID, _assetInfo2);
    }

    // Tests asset uniqueness. Every asset is uniquely identified by a pair <assetType>/<assetId>.
    // Creates assets with identical assetType and different assetId.
    function testAssetUniqueness2() {
        return _createAndCheckTwoAssets(ASSET_TYPE, ASSET_ID, _assetInfo1, ASSET_TYPE, ASSET_ID_2, _assetInfo2);
    }

    // Compares assetInfo tables.
    // If isSubset = true, returns true if all keys from pattern table are contained in
    //     actual table and the values are equal
    // If isSubset = false, returns true if none of pattern table keys is contained in
    //     actual table
    function _compareAssetInfo(pattern, actual, isSubset) {
        foreach (prop, value in pattern) {
            if (isSubset) {
                if (!prop in actual) {
                    this.info(format("missing key '%s' in actual assetInfo", prop));
                    return false;
                }
                else {
                    this.assertDeepEqual(actual[prop], value);
                }
            }
            else if (prop in actual) {
                this.info(format("extra key '%s' in actual assetInfo", prop));
                return false;
            }
        }
        return true;
    }

    // Creates two assets, deletes the first one and checks the second still exists.
    function _createAndCheckTwoAssets(assetType1, assetId1, assetInfo1, assetType2, assetId2, assetInfo2) {
        return Promise(function (resolve, reject) {
            _predix.createAsset(assetType1, assetId1, assetInfo1, function(status, errMessage, response) {
                if (status != PREDIX_STATUS.SUCCESS) {
                    return reject("createAsset1 failed:" + errMessage);
                }
                _predix.createAsset(assetType2, assetId2, assetInfo2, function(status, errMessage, response) {
                    if (status != PREDIX_STATUS.SUCCESS) {
                        return reject("createAsset2 failed:" + errMessage);
                    }
                    _predix.deleteAsset(assetType1, assetId1, function(status, errMessage, response) {
                        if (status != PREDIX_STATUS.SUCCESS) {
                            return reject("deleteAsset1 failed:" + errMessage);
                        }
                        _predix.queryAsset(assetType2, assetId2, function(status, errMessage, response) {
                            if (status != PREDIX_STATUS.SUCCESS) {
                                return reject("queryAsset2 failed:" + errMessage);
                            }
                            _predix.deleteAsset(assetType2, assetId2, function(status, errMessage, response) {
                                if (status != PREDIX_STATUS.SUCCESS) {
                                    return reject("deleteAsset2 failed:" + errMessage);
                                }
                                return resolve("");
                            }.bindenv(this));
                        }.bindenv(this));
                    }.bindenv(this));
                }.bindenv(this));
            }.bindenv(this));
        }.bindenv(this));
    }
}

