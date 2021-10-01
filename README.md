#  WatchCommunicator

A small framework that sits on top of WCSession and handles communication between Watch and App via "WatchCommunicatorMessage" values.

This framework aims to make it straightforward to get data from point A to point B, without having to concern oneself too much with _how_ data gets from A to B, as `WCSession` in the WatchConnectivity framework has multiple ways to get information between devices.


## Features

- Easy to use (says the Author...)
- Request / Response / Push approach has been realized. 
- Block-based API for handling responses, regardless of whether you've sent your message via the `WCSession` methods that will only work when the device is reachable.
- Prefers the fastest route of delivery (whether via messageData, applicationContext, userInfoTransfer, or complicationUserInfoTransfer)
- Straightforward File transfers
- Receive receipts are echoed back for any non-request.



## Principles

Application Context as you knew it is now different.  All data sent and received via a `WCSession` will now be wrapped in a `WatchCommunicatorMessage` type, so there's a standardized format to exchange data.  That said, if a `WatchCommunicatorMessage`'s `responseType` is `.applicationContext`, the typical assumptions about `WCSession` are valid; `WatchCommunicator` has the properties  `applicationContextMessage` and `receivedApplicationContextMessage` that are analogous to `applicationContext` and `receivedApplicationContext` on `WCSession` and work in the same way.



## Getting Started

Download this code project, run `pod install` to install the Logging dependency, then build and run on phone and device.  The demo app shows basic communication between the 2 apps, including transferring image files.



## Usage

### Configure WatchCommunicatorMessage for your application (via an extension)

The `WatchCommunicatorMessage` type has all you need to be able to configure for your own types, as it has the 'jsonData' property, and a userInfo dictionary, that can be wrapped to help provide context to the contents of the jsonData property.  This is your key task when making use of the `WatchCommunicator`.

Please refer to `WatchCommunicatorMessage+Application.swift` to see how you customize a `WatchCommunicatorMessage` to work with your application's data.

### Message Handler (Required)

A message handler is your one-stop location for handling message traffic between the two connected devices.  You can essentially do whatever you want here, but you should remember that if a message expects a response, you need to return a value in your `messageHandler` property.

Since a `WatchCommunicatorMessage` can essentially be 1 of 3 types (a request for data, a response to a request, or simply a one-way notification), your application code needs to provide a message handler in order to know how to respond to application-specific request / response messages. 

See both the `AppDelegate.swift` and the `ExtensionDelegate.swift` implementations in the demo project for how one sets up a `WatchCommunicator` instance.

Note, you are responsible for managing thread safety here.  (See suggestions for future work below)

### Context Accessor

Perhaps you need to refresh your watch's state.  Wouldn't it be nice to remain in a 'server-client' mindset (with completion blocks)?  This is where you could ask the counterpart device for its current context via a `WatchCommunicatorMessage` of `.responseType = .applicationContext`.  But what if you've never sent that before?  By configuring a `applicationContextAccessor` block, whenever the `WatchCommunicator` receives a request for the `applicationContext`, this information can always be sent back to the device requesting it.

### File Location Mapper

By default, whenever a file transfer completes, the file will be moved to a location in the user's caches folder.  You can modify this behaviour by providing an implementation for the `.fileLocationMapper` property.

### Reachability Monitoring

At times it is useful to know whether the counterpart device is reachable, so to interact with it, although `WatchCommunicator` handles the transfer of data appropriately, regardless of current reachability.

You can bind the `isReachable` property and only be notified when that state changes.

### Message History

If you are debugging, you may want to inspect the message history.  By default it is a FIFO buffer, where messages are sorted in descending order, given their timestamp.  i.e. the newest message is at the start of the array.



## Task examples

### Send Application Context
- configure `.applicationContextAccessor`

or, create a message:
```
// you'll see in WatchCommunicatorMessage+Application where I define contentType, and also the decodingType property.

let ctxData = try? self.communicator.encoder.encode(someCodableStruct)

let appCtxMessage = WatchCommunicatorMessage.response(toMessageId: nil,
                                                   responseType: .applicationContext,
                                                   contentType: .watchContextData,
                                                   userInfo: [:],
                                                   jsonData: ctxData)
```

### Request Current Context / Some Data

TODO:  Complete this section.



## Known Issues

- Was not designed for multiple watches.  The API documentation for WCSession provides a sequence diagram for how to support this.

- Testing watch apps is notoriously difficult.  This code, although working in a production app, might have edge cases that haven't been well tracked or tested.

- This represents an approach, but not yet a 'framework', per se, so for now it is as you see it.  Please contribute and turn your complaints into positivity!



## Suggestions for Future Work

- Make `WatchCommunicatorMessage` have associated type that is `Codable`, so you don't have to do the extra step of encoding your payload value, then decoding it while specifying what type to decode as.

- Unit Testing, specifically by creating a `WCSessionable` interface and being able to mock the session and really test this thing.

- Better considerations for the `completionQueue`.  Currently it is only used for any `sendRequestMessage(...)` completion block.  However, there are other accessors that could use it, such as when the `applicationContextAccessor` and the `messageHandler` closures are invoked.



## License

MIT.  Or whichever one that means "use it, abuse it, modify it, do whatever you want with it, don't even mention me if you don't want to, just don't send lawyers after me because I wrote this on my own time and it all originated in my brain."  I do not _oblige_ you to buy me a beer should we ever cross paths, but I do like the concept of the _Beerware_ license... :D 



## Author

Written by Stephen O'Connor, oconnor.freelance@googlemail.com




