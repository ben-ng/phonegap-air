#!/usr/bin/env node
var fs = require('fs')
  , url = require('url')
  , path = require('path')
  , async = require('async')
  , request = require('request')
  , crypto = require('crypto')
  , rootDir = process.argv[2]
  , wwwDir = path.join(rootDir, 'www')
  , constantsFile = path.join(rootDir, 'platforms', 'ios', 'OTAApplication', 'Classes', 'Constants.m')
  , cacheDirectory = path.join(rootDir, 'platforms', 'ios', 'OTAApplication', 'Resources', 'cache')

/**
* These helper functions are direct ports of their objective-c counterparts
*/
function fixPrefix(input, prefix) {
  var needle = '/' + prefix + '/'
    , replacement = prefix + '/'

  input.replace('\'' + needle, '\'' + replacement)
  input.replace('\"' + needle, '\"' + replacement)
  input.replace('(' + needle, '(' + replacement)

  return input
}

function shouldFixPrefix(fileName) {
  return /\.(js|css)$/.test(fileName) || fileName.indexOf('/js/') > -1 || fileName.indexOf('/css/') > -1
}

async.auto({
  /**
  * This step reads the constants so that we know what URL to download files from
  */
  constants: function (next) {
    fs.readFile(constantsFile, function (err, data) {
      if(err) {
        console.error('Could not read Constants.m: ' + err)
        console.error(err.stack)
        process.exit(1)
      }

      var prodURL = data.toString().match(/NSString\s+\*const\s+ProductionURL\s+=\s+@"(.*)";/)
        , manifestPath = data.toString().match(/NSString\s+\*const\s+ManifestPath\s+=\s+@"(.*)";/)
        , absPathReplacements = data.toString().match(/NSString\s+\*const\s+AbsolutePathsToReplace\s+=\s+@"(.*)";/)

      if(!prodURL) {
        console.error('Could not read ProductionURL from Constants.m')
        process.exit(1)
      }

      if(!manifestPath) {
        console.error('Could not read ManifestPath from Constants.m')
        process.exit(1)
      }

      if(!absPathReplacements) {
        absPathReplacements = []
      }
      else {
        absPathReplacements = absPathReplacements[1].split(',')
      }

      next(null
      , {
        prodURL: prodURL[1]
      , manifestPath: manifestPath[1]
      , absPathReplacements: absPathReplacements
      })
    })
  }
, manifest: ['constants', function (next, results) {
    request({
      url: url.resolve(results.constants.prodURL, results.constants.manifestPath)
    , json: true
    }, function (err, resp, body) {
      if(!err && resp.statusCode !== 200) {
        err = new Error('Expected 200, got ' + resp.statusCode)
      }

      next(err, body)
    })
  }]
, files: ['manifest', function (next, results) {
    var tasks = []

    for(var k in results.manifest.files) {
      tasks.push(results.manifest.files[k])
    }

    for(var i=0, ii=results.manifest.assets.length; i<ii; ++i) {
      var url = results.manifest.assets[i]
        , cacheURL = url.replace(/^.*:\/\//, '')
        , cacheKey = crypto.createHash('md5')
                            .update(cacheURL, 'utf8')
                            .digest('hex').toUpperCase()

      tasks.push({
        source: url
      , destination: path.join(cacheDirectory, cacheKey + '.persist')
      , checksum: null // Skip the check
      , isAsset: true
      })
    }

    function downloadEachFile (file, next) {
      request({
        url: file.isAsset ? file.source : url.resolve(results.constants.prodURL, file.source)
      , encoding: null // Force data to be a buffer, otherwise checksums won't match up
      }, function (err, resp, data) {
        if(!err && resp.statusCode !== 200) {
          err = new Error('Expected 200, got ' + resp.statusCode)
        }

        if(!err && file.checksum != null && crypto.createHash('md5').update(data).digest('hex') !== file.checksum) {
          err = new Error('File corruption: ' + file.source)
        }

        // Absolute to relative path replacement logic
        if(!err && shouldFixPrefix(file.source)) {
          data = data.toString()

          for(var i=0, ii=results.constants.absPathReplacements.length; i<ii; ++i) {
            data = fixPrefix(data, results.constants.absPathReplacements[i])
          }

          data = new Buffer(data)
        }

        next(err, {destination: path.join(wwwDir, file.destination), data: data})
      })
    }

    async.mapLimit(tasks, 5, downloadEachFile, next)
  }]
}, function (err, results) {
  if(err) {
    console.error(err)
    console.error(err.stack)
    process.exit(1)
  }

  // Copy the downloaded files into their rightful places
  async.eachSeries(results.files, function (file, next) {
    fs.writeFile(file.destination, file.data, next)
  })
})
