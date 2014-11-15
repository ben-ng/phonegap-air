/**
* A simple server that serves the contents of the www folder
*/

var finalhandler = require('finalhandler')
  , serveStatic = require('serve-static')
  , http = require('http')
  , path = require('path')
  , fs = require('fs')
  , async = require('async')
  , crypto = require('crypto')
  , wwwDir = path.join(__dirname, 'www')
  , appPath = path.join(wwwDir, 'app.js')
  , serve = serveStatic(wwwDir)
  , server
  , buildManifest
  , sendManifest
  , cachedManifest

// Replace app.js placeholder so the apps know where they pulled from
fs.readFile(appPath, function (err, data) {
  if (err) throw err

  var replaced = data.toString().replace(/{{environment}}/, process.env.NODE_ENV)

  fs.writeFile(appPath, replaced, function (err) {
    if(err) throw err
  })
})

sendManifest = function _sendManifest(res) {
  var manifest = JSON.parse(cachedManifest)

  manifest.message = 'The version updates every second'
  manifest.version = '1.0.' + (Date.now()/1000)

  manifest = JSON.stringify(manifest)

  res.writeHead(200, {
    'content-length': manifest.length
  , 'content-type': 'application/json'
  })

  res.end(manifest)
}

buildManifest = function _buildManifest (req, res, done) {
  if(cachedManifest) {
    sendManifest(res)
  }
  else {
    fs.readdir(wwwDir, function (err, files) {
      if(err) return done(err)

      cachedManifest = {files: {}, assets: []}

      async.map(files, function (filename, next) {
        var filepath = path.join(wwwDir, filename)

        fs.readFile(filepath, function (err, data) {
          if(err) return next(err)

          cachedManifest.files[filename] = {
            checksum: crypto.createHash('md5').update(data).digest("hex")
          , destination: filename
          , source: '/' + filename
          }

          next()
        })
      }, function (err) {
        if(err) return done(err)

        cachedManifest = JSON.stringify(cachedManifest)

        sendManifest(res)
      })
    })
  }
}

server = http.createServer(function(req, res) {
  var done = finalhandler(req, res)

  if(require('url').parse(req.url).pathname == '/manifest.json') {
    buildManifest(req, res, done)
  }
  else {
    serve(req, res, done)
  }
})

server.listen(process.env.PORT || 8080)
