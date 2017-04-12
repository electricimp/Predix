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

// Utility Libraries
#require "bullwinkle.class.nut:2.3.2"
#require "promise.class.nut:3.0.0"
// Web Integration Library
#require "Predix.class.nut:1.0.0"

// Class that receives and handles data sent from device SmartFridgeApp
/***************************************************************************************
 * SmartFrigDataManager Class:
 *      Handle incoming device readings and events
 *      Set callback handlers for events and streaming data
 *      Average temperature and humidity readings
 *
 * Dependencies
 *      Bullwinle (passed into the constructor)
 **************************************************************************************/
class SmartFrigDataManager {

    static DEBUG_LOGGING = true;

    // Event types (these should match device side event types in SmartFrigDataManager)
    static EVENT_TYPE_TEMP_ALERT = "temperaure alert";
    static EVENT_TYPE_HUMID_ALERT = "humidity alert";
    static EVENT_TYPE_DOOR_ALERT = "door alert";
    static EVENT_TYPE_DOOR_STATUS = "door status";

    static TEMP_SENSOR_NAME = "temperature";
    static HUMID_SENSOR_NAME = "humidity";
    static DOOR_SENSOR_NAME = "door";

    _streamReadingsHandler = null;
    _doorOpenAlertHandler = null;
    _tempAlertHandler = null;
    _humidAlertHandler = null;

    // Class instances
    _bull = null;

    /***************************************************************************************
     * Constructor
     * Returns: null
     * Parameters:
     *      bullwinkle : instance - of Bullwinkle class
     **************************************************************************************/
    constructor(bullwinkle) {
        _bull = bullwinkle;
        openListeners();
    }

     /***************************************************************************************
     * openListeners
     * Returns: null
     * Parameters: none
     **************************************************************************************/
    function openListeners() {
        _bull.on("update", _readingsHandler.bindenv(this));
    }

    /***************************************************************************************
     * setStreamReadingsHandler
     * Returns: null
     * Parameters:
     *      cb : function - called when new reading received
     **************************************************************************************/
    function setStreamReadingsHandler(cb) {
        _streamReadingsHandler = cb;
    }

    /***************************************************************************************
     * setDoorOpenAlertHandler
     * Returns: null
     * Parameters:
     *      cb : function - called when door open alert triggered
     **************************************************************************************/
    function setDoorOpenAlertHandler(cb) {
        _doorOpenAlertHandler = cb;
    }

    /***************************************************************************************
     * setTempAlertHandler
     * Returns: null
     * Parameters:
     *      cb : function - called when temperature alert triggerd
     **************************************************************************************/
    function setTempAlertHandler(cb) {
        _tempAlertHandler = cb;
    }

    /***************************************************************************************
     * setHumidAlertHandler
     * Returns: null
     * Parameters:
     *      cb : function - called when humidity alert triggerd
     **************************************************************************************/
    function setHumidAlertHandler(cb) {
        _humidAlertHandler = cb;
    }

    /***************************************************************************************
     * getSensors
     * Returns: sensors array
     * Parameters: none
     **************************************************************************************/
    function getSensors() {
        return [TEMP_SENSOR_NAME, HUMID_SENSOR_NAME, DOOR_SENSOR_NAME];
    }

    // ------------------------- PRIVATE FUNCTIONS ------------------------------------------

    /***************************************************************************************
     * _getAverage
     * Returns: null
     * Parameters:
     *      readings : table of readings
     *      type : key from the readings table for the readings to average
     *      numReadings: number of readings in the table
     **************************************************************************************/
    function _getAverage(readings, type, numReadings) {
        if (numReadings == 1) {
            return readings[0][type];
        } else {
            local total = readings.reduce(function(prev, current) {
                    return (!(type in prev)) ? prev + current[type] : prev[type] + current[type];
                })
            return total / numReadings;
        }
    }

    /***************************************************************************************
     * _readingsHandler
     * Returns: null
     * Parameters:
     *      message : table - message received from bullwinkle listener
     *      reply: function that sends a reply to bullwinkle message sender
     **************************************************************************************/
    function _readingsHandler(message, reply) {
        local data = message.data;
        local ts = time();
        local streamingData = {};
        local numReadings = data.readings.len();

        // send ack to device (device erases this set of readings/events when ack received)
        reply("OK");

        if (DEBUG_LOGGING) {
            server.log("in readings handler")
            server.log(http.jsonencode(data.readings));
            server.log(http.jsonencode(data.doorStatus));
            server.log(http.jsonencode(data.events));
            server.log("Current time: " + ts)
        }

        if ("readings" in data && numReadings > 0) {

            // Update streaming data table with temperature and humidity averages
            streamingData[TEMP_SENSOR_NAME] <- _getAverage(data.readings, TEMP_SENSOR_NAME, numReadings);
            streamingData[HUMID_SENSOR_NAME] <- _getAverage(data.readings, HUMID_SENSOR_NAME, numReadings);
        }

        if ("doorStatus" in data) {
            // Update streaming data table
            streamingData[DOOR_SENSOR_NAME] <- data.doorStatus.currentStatus;
        }

        // send streaming data to handler
        _streamReadingsHandler(ts, streamingData);

        if ("events" in data && data.events.len() > 0) {
            // handle events
            foreach (event in data.events) {
                switch (event.type) {
                    case EVENT_TYPE_TEMP_ALERT :
                        _tempAlertHandler(event);
                        break;
                    case EVENT_TYPE_HUMID_ALERT :
                        _humidAlertHandler(event);
                        break;
                    case EVENT_TYPE_DOOR_ALERT :
                        _doorOpenAlertHandler(event);
                        break;
                    case EVENT_TYPE_DOOR_STATUS :
                        break;
                }
            }
        }
    }

}

/***************************************************************************************
 * SmartFrigDeviceMngr Class:
 *      Requests/stores info from device
 *      Create/Update Device on Predix platform
 *      Creates a flag indicating if Device has been created in Predix
 *
 * Dependencies
 *      Bullwinkle Library
 **************************************************************************************/
class SmartFrigDeviceMngr {
    static DEVICE_TYPE_ID = "smart_fridge";
    static DEVICE_MANUFACTURER = "Electric Imp";

    // Class variables
    _bull = null;
    _predix = null;

    _deviceInfo = null;
    _meta = null;

    deviceID = null;
    deviceConfigured = false;

    /***************************************************************************************
     * Constructor
     * Returns: null
     * Parameters:
     *      bullwinkle : instance - of Bullwinkle class
     *      predix : instance - of Predix class
     *      sensors : array of sensors names
     *      alerts : array of alerts names
     **************************************************************************************/
    constructor(bullwinkle, predix, sensors, alerts) {
        _bull = bullwinkle;
        _predix = predix;

        setBasicDevInfo(sensors, alerts);

        // Get info from device and create device in Predix
        getDevInfo()
            .then(function(msg) {
                server.log(msg);
                createDev();
            }.bindenv(this),
            function(reject) {
                server.error(reject);
            }.bindenv(this));
    }

    /***************************************************************************************
     * getDevInfo
     * Returns: Promise that resolves with status message
     * Parameters: none
     **************************************************************************************/
    function getDevInfo() {
        return Promise(function(resolve, reject) {
            imp.wakeup(0.5, function() {
                _bull.send("getDevInfo", null)
                    .onReply(function(msg) {
                        if (msg.data != null) {
                            _updateDevInfo(msg.data);
                            return resolve("Received Device Info.")
                        } else {
                            return resolve("Device Info Error.")
                        }
                    }.bindenv(this))
                    .onFail(function(err, msg, retry) {
                        // TODO: add retry
                        return resolve("Device Info Error.")
                    }.bindenv(this))
            }.bindenv(this))
        }.bindenv(this))
    }

    /***************************************************************************************
     * setBasicDevInfo
     * Returns: this
     * Parameters: none
     **************************************************************************************/
    function setBasicDevInfo(sensors, alerts) {
        deviceID = imp.configparams.deviceid.tostring();
        _deviceInfo = {
            "manufacturer" : DEVICE_MANUFACTURER,
            "sensors" : sensors,
            "alerts" : alerts
        };
        _meta = {};
        return this;
    }

    /***************************************************************************************
     * createDev - creates or updates device on Predix platform
     * Returns: null
     * Parameters: none
     **************************************************************************************/
    function createDev() {
        local info = {"deviceId" : deviceID, "deviceInfo" : _deviceInfo, "metadata" : _meta};
        _predix.createAsset(DEVICE_TYPE_ID, deviceID, info, function(status, errMessage, response) {
            if (status != PREDIX_STATUS.SUCCESS) {
                if (errMessage != null) {
                    server.error(errMessage);
                }
                return;
            }
            deviceConfigured = true;
            server.log("Dev created");
        }.bindenv(this));
    }

    // ------------------------- PRIVATE FUNCTIONS ------------------------------------------

    /***************************************************************************************
     * _updateDevInfo
     * Returns: this
     * Parameters:
     *      info: table with new device info
     **************************************************************************************/
    function _updateDevInfo(info) {
        if ("devID" in info) {
            deviceID = info.devID.tostring();
            info.rawdelete("devID");
        }
        if ("location" in info) {
            _deviceInfo.descriptiveLocation <- info.location;
            info.rawdelete("location");
        }
        if ("swVersion" in info) {
            _deviceInfo.fwVersion <- info.swVersion;
            info.rawdelete("swVersion");
        }
        if ("mac" in info) {
            _meta.macAddress <- info.mac;
            info.rawdelete("mac");
        }
        foreach(key, value in info) {
            _meta[key] <- value;
        }
    }

}

/***************************************************************************************
 * Application Class:
 *      Sends data to Predix IoT platform
 *
 * Dependencies
 *      Bullwinkle Library
 *      Predix Library
 *      SmartFrigDeviceMngr Class
 *      SmartFrigDataManager Class
 **************************************************************************************/
class Application {
    // Event IDs
    static STREAMING_EVENT_ID = "RefrigeratorMonitor";
    static DOOR_OPEN_EVENT_ID = "DoorOpenAlert";
    static TEMP_ALERT_EVENT_ID = "TemperatureAlert";
    static HUMID_ALERT_EVENT_ID = "HumidityAlert";
    // Alert messages
    static DOOR_OPEN_ALERT = "Refrigerator Door Open";
    static TEMP_ALERT = "Temperature Over Threshold";
    static HUMID_ALERT = "Humidity Over Threshold";

    dataMngr = null;
    devMngr = null;
    predix = null;

    /***************************************************************************************
     * Constructor
     * Returns: null
     * Parameters:
     *      uaaUrl : string - Predix UAA service instance URL
     *      clientId : string - Id of a client registered in Predix UAA service
     *      clientSecret : string - Predix UAA client secret
     *      assetUrl : string - Predix Asset service instance URL
     *      assetZoneId : string - Predix Zone ID for Asset service
     *      timeSeriesIngestUrl : string - Predix Time Series service ingestion URL
     *      timeSeriesZoneId : string - Predix Zone ID for TimeSeries service
     **************************************************************************************/
    constructor(uaaUrl, clientId, clientSecret,
                assetUrl, assetZoneId, timeSeriesIngestUrl, timeSeriesZoneId) {
        initializeClasses(uaaUrl, clientId, clientSecret,
            assetUrl, assetZoneId, timeSeriesIngestUrl, timeSeriesZoneId);
        setDataMngrHandlers();
    }

    /***************************************************************************************
     * initializeClasses
     * Returns: null
     * Parameters:
     *      uaaUrl : string - Predix UAA service instance URL
     *      clientId : string - Id of a client registered in Predix UAA service
     *      clientSecret : string - Predix UAA client secret
     *      assetUrl : string - Predix Asset service instance URL
     *      assetZoneId : string - Predix Zone ID for Asset service
     *      timeSeriesIngestUrl : string - Predix Time Series service ingestion URL
     *      timeSeriesZoneId : string - Predix Zone ID for TimeSeries service
     **************************************************************************************/
    function initializeClasses(uaaUrl, clientId, clientSecret,
                               assetUrl, assetZoneId,
                               timeSeriesIngestUrl, timeSeriesZoneId) {
        // agent/device communication helper library
        local _bull = Bullwinkle();
        // Library for integration with Predix IoT platform
        predix = Predix(uaaUrl, clientId, clientSecret,
            assetUrl, assetZoneId, timeSeriesIngestUrl, timeSeriesZoneId);
        // Class to manage sensor data from device
        dataMngr = SmartFrigDataManager(_bull);
        local alerts = [DOOR_OPEN_EVENT_ID, TEMP_ALERT_EVENT_ID, HUMID_ALERT_EVENT_ID];
        // Class to manage device info and Predix device creation
        devMngr = SmartFrigDeviceMngr(_bull, predix, dataMngr.getSensors(), alerts);
    }

    /***************************************************************************************
     * setDataMngrHandlers
     * Returns: null
     * Parameters: none
     **************************************************************************************/
    function setDataMngrHandlers() {
        // set Data Manager handlers to the local handler functions
        dataMngr.setDoorOpenAlertHandler(doorOpenHandler.bindenv(this));
        dataMngr.setStreamReadingsHandler(streamReadingsHandler.bindenv(this));
        dataMngr.setTempAlertHandler(tempAlertHandler.bindenv(this));
        dataMngr.setHumidAlertHandler(humidAlertHandler.bindenv(this));
    }

    /***************************************************************************************
     * streamReadingsHandler
     * Returns: null
     * Parameters:
     *      ts : integer - data measurement timestamp in seconds since epoch
     *      reading : table - temperature, humidity and door status
     **************************************************************************************/
    function streamReadingsHandler(ts, reading) {
        // log the incoming reading
        server.log(http.jsonencode(reading));

        // Post data if Predix device configured
        if (devMngr.deviceConfigured) {
            predix.ingestData(devMngr.DEVICE_TYPE_ID, devMngr.deviceID, reading, ts, predixResponseHandler.bindenv(this));
        }
    }

    /***************************************************************************************
     * doorOpenHandler
     * Returns: null
     * Parameters:
     *      event: table with event details
     **************************************************************************************/
    function doorOpenHandler(event) {
        server.log(format("%s: %s", DOOR_OPEN_ALERT, event.description));
        sendAlert(DOOR_OPEN_EVENT_ID, DOOR_OPEN_ALERT, event.description, event.ts);
    }

    /***************************************************************************************
     * tempAlertHandler
     * Returns: null
     * Parameters:
     *      event: table with event details
     **************************************************************************************/
    function tempAlertHandler(event) {
        server.log(format("%s: %s", TEMP_ALERT, event.description));
        sendAlert(TEMP_ALERT_EVENT_ID, TEMP_ALERT, event.description, event.ts);
    }

    /***************************************************************************************
     * humidAlertHandler
     * Returns: null
     * Parameters:
     *      event: table with event details
     **************************************************************************************/
    function humidAlertHandler(event) {
        server.log(format("%s: %s", HUMID_ALERT, event.description));
        sendAlert(HUMID_ALERT_EVENT_ID, HUMID_ALERT, event.description, event.ts);
    }

    /***************************************************************************************
     * sendAlert
     * Returns: null
     * Parameters:
     *      eventID : string - event identifier
     *      alert : string - alert message
     *      description : string - description of alert
     *      ts (optional) : integer - epoch time stamp of alert
     **************************************************************************************/
    function sendAlert(eventId, alert, description, ts = null) {
        if (devMngr.deviceConfigured) {
            local data = {};
            data[eventId] <- format("%s: %s", alert, description);
            predix.ingestData(devMngr.DEVICE_TYPE_ID, devMngr.deviceID, data, ts, predixResponseHandler.bindenv(this));
        }
    }

    /***************************************************************************************
     * predixResponseHandler
     * Returns: null
     * Parameters:
     *      status : string/null - status of the Predix library method call
     *      errMessage : string/null - error details, if any
     *      resp : table - response table
     **************************************************************************************/
    function predixResponseHandler(status, errMessage, resp) {
        if (errMessage) server.error(errMessage);
        if (status == PREDIX_STATUS.SUCCESS) {
            server.log("Predix request successful.");
        }
    }
}


// RUNTIME
// ----------------------------------------------

// Predix account constants
const UAA_URL = "<YOUR UAA SERVICE INSTANCE URL>"; // usually "https://<YOUR UAA INSTANCE>.predix-uaa.run.aws-usw02-pr.ice.predix.io";
const CLIENT_ID = "<YOUR CLIENT ID>";
const CLIENT_SECRET = "<YOUR CLIENT SECRET>";
const ASSET_URL = "<YOUR ASSET SERVICE INSTANCE URL>"; // usually "https://predix-asset.run.aws-usw02-pr.ice.predix.io"
const ASSET_ZONE_ID = "<YOUR PREDIX-ZONE-ID FOR ASSET SERVICE>";
const TIME_SERIES_INGEST_URL = "<URL OF EXTERNAL HTTP TO WS PROXY>";
const TIME_SERIES_ZONE_ID = "<YOUR PREDIX-ZONE-ID FOR TIME SERIES SERVICE>";

// Start Application
app <- Application(UAA_URL, CLIENT_ID, CLIENT_SECRET,
                   ASSET_URL, ASSET_ZONE_ID,
                   TIME_SERIES_INGEST_URL, TIME_SERIES_ZONE_ID);
