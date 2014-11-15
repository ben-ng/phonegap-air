phonegap-air
============

Put your web app in the App Store and update it whenever you want.

![Demo App](https://cldup.com/M5ZzPZAiEA-3000x3000.jpeg)

## Features

* Update any asset you want. HTML, CSS, JS, Fonts, Images, etc.
* Keep your app up-to-date even if the user hasn't launched it in a while
* Download only the smallest changeset needed to update a client
* Switch between prod/staging/dev versions of your app by shaking your device
* Make your app feel faster with cleverly used launch images

## Advanced Features

* Load images from the web instantly by proxying them to a local cache
* Deep link into your application

## Demo

Included is a working Xcode project and sample node.js server.

1. Open the Xcode project
2. Run it in the iOS simulator (pick any device)
3. Observe that a blocking update is performed using the production manifest
4. Select Hardware -> Shake Gesture to open the branch switcher
5. Select "Staging"
6. Observe that a blocking update was performed using the staging manifest

## Usage

* Configure the Xcode project
  * Hard-code your production and staging URLs in `Constants.m`
  * Create and add your launch images and app icons
  * Modify the shake gesture handler to restrict access to the dev tools
  * Set your product name and other target preferences
* Add a manifest to your web server
  * See the sample node.js server for how to do this

## Documentation

* How does the app know what to update?

The app requests a `manifest.json` file from your server with this syntax:

```json
{
  "files":{
    "app.js": {
      "checksum":"d8138338a247ec7ec1eb69c40dc554c2",
      "destination":"app.js",
      "source":"/app.js"
    }
  },
  "assets":["http://cdn.com/image.jpg"],
  "message":"A description of this version",
  "version":"1.0.0"
}
```

* files

A dictionary of objects. The keys are for your own reference; the update system disregards them. `destination` refers to where in the `www` folder this file should be placed. `source` should be a path relative to your web server's root indicating where the

See `ota-server/server.js` for an example.

* How do I restrict access to the dev tools?

Implement the global function `window.shouldAllowOTADevTools`. This function should return a boolean indicating if the dev tools should be opened.

* When does the app update?

1. On initial launch, an update is attempted before the app is started
2. When the app enters the background (e.g. when the home button is pushed)
3. When the device is plugged in and on wifi
4. When a selection is made in the dev panel

If an update finishes downloading while the app is in the foreground, it will only be applied when the user reopens the app.

## Support

* Bugs

Let me know how to reproduce it and I'll fix it.

* Documentation Requests

Let me know what's confusing and I'll add to it.

* Enhancements
* Debugging Help
* Consultation

I'm a full-time student with a near full-time job, so these will be a very low priority for me. If you *really* need something @mention me on [twitter](https://twitter.com/_benng) or email me at `me [at] benng.me` and we'll work something out.

## License

The MIT License (MIT)

Copyright (c) 2014 Ben Ng

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
