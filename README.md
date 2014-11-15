phonegap-air
============

Put your web app in the App Store and update it whenever you want.

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

1. Run the Xcode project
2. Shake to switch app versions or download a fresh app

## Usage

* Configure the Xcode project
  * Hard-code your production and staging URLs
  * Create and add launch images
  * Modify the shake gesture handler to restrict access to the dev tools.
  * Set your product name and other target preferences
* Add a manifest to your web server
  * See the sample node.js server for how to do this

## Documentation

* When does the app update?

1. On initial launch, an update is attempted before the app is started
2. When the app enters the background (e.g. when the home button is pushed)
3. When the device is plugged in and on wifi
4. When a selection is made in the dev panel

If an update finishes downloading while the app is in the foreground, it will only be applied when the user reopens the app.
