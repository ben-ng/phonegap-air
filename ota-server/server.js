/**
* A simple server that serves the contents of the www folder
*/

var finalhandler = require('finalhandler')
  , serveStatic = require('serve-static')
  , http = require('http')
  , path = require('path')
  , fs = require('fs')
  , wwwDir = path.join(__dirname, 'www')
  , stratosphere = require('stratosphere')
  , appPath = path.join(wwwDir, 'app.js')
  , port = process.env.PORT || 8080
  , instance
  , serve = serveStatic(wwwDir)
  , server
  , manifestOpts = {}


manifestOpts.message = 'The version updates every second when not in production'

// Pin the production version so that we can test the redundant update logic
if(process.env.NODE_ENV == 'production') {
  manifestOpts.version = '1.1.0'
}
else {
  manifestOpts.version = '1.1.' + Math.round(Date.now()/1000)
}


// Replace app.js placeholder so the apps know where they pulled from
fs.readFile(appPath, function (err, data) {
  if (err) throw err

  var replaced = data.toString().replace(/{{environment}}/, process.env.NODE_ENV)

  fs.writeFile(appPath, replaced, function (err) {
    if(err) throw err
  })
})

server = http.createServer(function(req, res) {
  serve(req, res, finalhandler(req, res))
})

instance = stratosphere(server, {
  assets: path.join(__dirname, 'assets.json')
, root: path.join(__dirname, 'tmp')
, manifestOpts: manifestOpts
})

instance.intercept().listen(port)

instance.preload(function () {
  console.log('preloading complete, listening on ' + port)
})
