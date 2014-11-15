
document.addEventListener('deviceReady', function () {
  var metaInfo = 'remote @ ' + new Date
    , metaInfoNode = document.createTextNode(metaInfo)
  document.getElementById('loading').className = 'hidden'
  document.getElementById('loaded').className = ''
  document.getElementById('meta').appendChild(metaInfoNode)
}, false)
