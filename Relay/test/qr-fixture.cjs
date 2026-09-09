// Synthetic QR for desktop rendering tests only. Not a real pairing credential.
const QRCode = require('qrcode-terminal/vendor/QRCode');
const level = require('qrcode-terminal/vendor/QRCode/QRErrorCorrectLevel');
const qr = new QRCode(-1, level.M);
qr.addData(JSON.stringify({endpoint:'https://demo.example.test/',token:'synthetic-fixture-not-a-real-token'}));
qr.make();
process.stdout.write(JSON.stringify({type:'pairing',endpoint:'https://demo.example.test/',modules:qr.modules}));
