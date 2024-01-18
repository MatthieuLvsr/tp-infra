// index.js
exports.curlNginxIndex = (pubSubEvent, context, callback) => {
    const http = require('http');
  
    // Replace with the internal or external IP of your Nginx server
    const options = {
      host: 'http://34.30.190.188',
      port: 80,
      path: '/'
    };
  
    http.get(options, (resp) => {
      let data = '';
  
      // A chunk of data has been received.
      resp.on('data', (chunk) => {
        data += chunk;
      });
  
      // The whole response has been received. Print out the result.
      resp.on('end', () => {
        console.log(data);
        callback(null, 'Curl to Nginx index page performed successfully.');
      });
  
    }).on("error", (err) => {
      console.log("Error: " + err.message);
      callback(err);
    });
  };
  