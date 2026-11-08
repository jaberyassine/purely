const fs = require('fs');
const config = JSON.parse(fs.readFileSync('/bootstrap/users.json', 'utf8'));
const account = config.services[0];
const connection = new Mongo('mongodb://' + encodeURIComponent(account.user) + ':' + encodeURIComponent(account.password)
    + '@localhost:27017/' + account.database + '?authSource=' + account.database
    + '&tls=true&tlsCAFile=/etc/mongodb/tls/ca.crt');
const collection = connection.getDB(account.database).getCollection('_deployment_verification');
if (process.env.PURELY_PERSISTENCE_MODE === 'write') {
    collection.replaceOne({_id: 'volume-check'}, {_id: 'volume-check', token: config.persistenceToken}, {upsert: true});
    print('PASS: persistence marker written.');
} else {
    const saved = collection.findOne({_id: 'volume-check'});
    if (!saved || saved.token !== config.persistenceToken) throw new Error('Data did not survive the database pod restart');
    collection.deleteOne({_id: 'volume-check'});
    print('PASS: data survived the database pod restart.');
}
