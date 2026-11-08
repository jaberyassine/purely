const fs = require('fs');
const config = JSON.parse(fs.readFileSync('/bootstrap/users.json', 'utf8'));
for (const account of config.services) {
    const connection = new Mongo('mongodb://' + encodeURIComponent(account.user) + ':' + encodeURIComponent(account.password)
        + '@localhost:27017/' + account.database + '?authSource=' + account.database
        + '&tls=true&tlsCAFile=/etc/mongodb/tls/ca.crt');
    const own = connection.getDB(account.database);
    const collection = own.getCollection('_deployment_verification');
    const marker = 'deployment-' + new Date().getTime();
    collection.insertOne({_id: marker, check: 'TLS, authentication and write access'});
    if (!collection.findOne({_id: marker})) throw new Error('Read-back failed');
    collection.deleteOne({_id: marker});
    const other = config.services.find(candidate => candidate.database !== account.database);
    let blocked = false;
    try { connection.getDB(other.database).getCollection('_deployment_verification').findOne({}); }
    catch (error) { if (error.code === 13) blocked = true; else throw error; }
    if (!blocked) throw new Error('Cross-database access was not rejected');
    print('PASS: ' + account.service + ' TLS/auth/read/write and foreign-database denial.');
}
