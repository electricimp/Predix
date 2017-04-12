# Predix

The library lets your agent code to connect to [GE’s Predix IoT platform](https://www.predix.io). It makes use of the Predix User Account and Authentication (UAA), Asset, and Time Series services [REST API](https://www.predix.io/api).

This library depends on the Promise library, so you must include the latest version of [Electric Imp Promise library](https://github.com/electricimp/Promise) at the top of your agent code as well.

Before using this library you need to:
- Register an account at the Predix platform.
- Add UAA, Assets, Time Series services to your account.
- Create and configure a client using UAA service instance.
- Obtain URLs of UAA, Assets and Time Series service instances.
- Obtain Zone-ID identifiers of Assets and Time Series service instances.

If you want to manage your connected device(s) and see the data from them in Predix, you may:
- Create a web application.
- Deploy the web application to the Predix platform.
- Bind UAA, Assets and Time Series services (and any other Predix services that your application uses) to the web application.

For more information about Predix platform setup and usage, please see [the Predix Documentation](https://www.predix.io/docs).

**To add this library to your project, add** `#require "Predix.class.nut:1.0.0"` **and** `#require "Promise.class.nut:3.0.1"` **to the top of your agent code.**

## Library Usage

The library API is detailed in the source file, [here](./Predix.class.nut).

### Constructor: Predix(*uaaUrl, clientId, clientSecret, assetUrl, assetZoneId, timeSeriesIngestUrl, timeSeriesZoneId*)

To instantiate this library you need to have:
- UAA service instance URL.
- UAA service client ID.
- UAA service client secret.
- Asset service instance URL.
- Asset service Zone-ID.
- Time Series service ingestion URL.
- Time Series service Zone-ID.

and pass each of the these initialization data into the constructor:

```squirrel
#require "promise.class.nut:3.0.1"
#require "Predix.class.nut:1.0.0"

predix <- Predix(<"YOUR_UUA_URL">, <"YOUR_CLIENT_ID">, <"YOUR_CLIENT_SECRET">, <"YOUR_ASSET_URL">, 
                 <"YOUR_ASSET_ZONE_ID">, <"YOUR_TIME_SERIES_INGEST_URL">, <"YOUR_TIME_SERIES_ZONE_ID">);
```

The constructor does not return any error. If any or all of the initialization data is not correct, you receive an appropriate error when the library method cannot be executed

**Note** The current version of the library accepts only *http* or *https* Time Series service ingestion URL. Please check if the latest version of the Predix platform supports data ingestion over *http* or *https* protocols. If not (eg. Time Series service uses only WebSocket protocol for data ingestion), you will need an external http-to-websocket proxy that receives *http/https* requests from the library and resends them to the Predix Time Series service through WebSocket. An example of such a http-to-websocket proxy can be found in the [Examples folder](Examples).

## Library Methods

### Callbacks

All requests that are made to the Predix platform are asynchronous. Every method that sends a request can take an optional callback function which will be called when the operation is completed, successfully or not. The callback has three parameters of its own:

- *status* &mdash; The status of the operation (success or one of the error types)
- *errMessage* &mdash; Error details, in case of error
- *response* &mdash; The response from the Predix platform, if it has been received

Any of the following error constants may be passed into *status*:

- *PREDIX_STATUS.LIBRARY_ERROR* &mdash; This is reported if the library has been wrongly initialized or invalid arguments are passed into the method. Usually it indicates an issue during an application development which should be fixed during debugging and therefore should not occur after the application has been deployed. The actual error details are provided in *errMessage*.

- *PREDIX_STATUS.PREDIX_REQUEST_FAILED* &mdash; This error may occur during the normal execution of an application. The application logic should process this error. The error details are provided in *errMessage* and in *response*.

- *PREDIX_STATUS.PREDIX_UNEXPECTED_RESPONSE* &mdash; This indicates an unexpected behavior of the Predix platform, such as a response which does not correspond to the Predix REST API specification. The error details are provided in *errMessage* and in *response*.

### Assets identification and management

Your device is represented in the Predix platform as an asset. Every asset is uniquely identified in the scope of your Predix account by a pair of values: *assetType* and *assetId*. 

*assetType* can be the type of device, such as "sensor" or "actuator", your application, your use case name, or anything else you want.

*assetId* must be a unique identifier in the scope of a particular *assetType*. It may be a hierarchical naming structure, or just a plain (but unique) number, eg. the device ID.

All library methods which operate with assets and send data have *assetType* / *assetId* pair as parameters.

The library provides methods to create, update, delete or query assets in the Predix platform using Predix Asset service. To update or delete an asset or to send data it is not mandatory to create this asset using the library method. Your application may receive the identifier of an already created asset by some other means.

### createAsset(*assetType, assetId, assetInfo[, callback]*)

This method creates or updates a specified asset.

If the specified asset does not exist, it is created and initialized by the provided information (*assetInfo*). If the specified asset already exists, it is updated with the new information. All old properties are deleted.

```squirrel
local info = { "description" : "My test sensor",
               "location" : "My home" };

predix.createAsset("my_sensor", "unique_id_1234", info, function(status, errMessage, response) {
    if (status == PREDIX_STATUS.SUCCESS) {
        // The asset is created/updated - continue application logic
    } else {
        // log errMessage and response, if any
        server.error(errMessage);
    }
}.bindenv(this));
```

### queryAsset(*assetType, assetId[, callback]*)

This method checks if the specified asset exists. If it does (ie. *PREDIX_STATUS.SUCCESS* is passed into the callback’s *status* parameter), the asset properties can be found in the *response.body* callback parameter.

If the asset doesn’t exist, *status* will take the value *PREDIX_STATUS.PREDIX_REQUEST_FAILED*.

```squirrel
predix.queryAsset("my_sensor", "unique_id_1234", function(status, errMessage, response) {
    if (status == PREDIX_STATUS.SUCCESS) {
        // The asset exists
    } else if (status == PREDIX_STATUS.PREDIX_REQUEST_FAILED) {
        // The asset does not exist
    } else {
        // unexpected/library error - log errMessage and response, if any
        server.error(errMessage + " (" + response.body + ")");
    }
}.bindenv(this));
```

### deleteAsset(*assetType, assetId[, callback]*)

This method deletes the specified asset. If the specified asset does not exist, the method does nothing, and *PREDIX_STATUS.SUCCESS* will be passed into in the callback’s *status* parameter, just as it would be if the asset did exist but has now been deleted.

```squirrel
predix.deleteAsset("my_sensor", "unique_id_1234", function(status, errMessage, response) {
    if (status == PREDIX_STATUS.SUCCESS) {
        // The asset does not exist anymore - continue application logic
    } else {
        // Log errMessage and response, if any
        server.error(errMessage);
    }
}.bindenv(this));
```

### Sending Data

### ingestData(*assetType, assetId, data, timestamp[, callback]*)

This method is used to send data to the Predix platform using the Predix Time Series service.

If you do not provide a value for the *timestamp* parameter &mdash; pass `null` in this case &mdash; the library inserts the current date and time.

```squirrel
local data = { "my_data" : "value_100" };

predix.ingestData("my_sensor", "unique_id_1234", data, null, function(status, errMessage, response) {
    if (status == PREDIX_STATUS.SUCCESS) {
        // the data has been sent - continue application logic
    }
    else {
        // Log errMessage and response, if any
        server.error(errMessage);
    }
}.bindenv(this));
```

## Examples

- The is a complete application example, Smart Fridge, in the [Examples folder](./Examples)

## License

The Predix library is licensed under the [MIT License](./LICENSE).
