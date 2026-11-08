const fs = require('fs');
const config = JSON.parse(fs.readFileSync('/bootstrap/users.json', 'utf8'));
for (const account of config.services) {
    const dataDatabase = account.dataDatabase || account.database;
    const connection = new Mongo('mongodb://' + encodeURIComponent(account.user) + ':' + encodeURIComponent(account.password)
        + '@localhost:27017/' + dataDatabase + '?authSource=' + account.database
        + '&tls=true&tlsCAFile=/etc/mongodb/tls/ca.crt');
    const own = connection.getDB(dataDatabase);
    if (account.accessMode === 'identity-readonly') {
        own.getCollection('Users').findOne({}, {_id: 1});
        let denied = false;
        try { own.getCollection('Roles').findOne({}); }
        catch (error) { if (error.code === 13) denied = true; else throw error; }
        if (!denied) throw new Error('Unintended identity collection was readable');
        print('PASS: user-service TLS/auth and collection-scoped identity read access.');
        continue;
    }
    const collection = own.getCollection('_deployment_verification');
    const marker = 'deployment-' + new Date().getTime();
    collection.insertOne({_id: marker, check: 'TLS, authentication and write access'});
    if (!collection.findOne({_id: marker})) throw new Error('Read-back failed');
    collection.deleteOne({_id: marker});
    const other = config.services.find(candidate => (candidate.dataDatabase || candidate.database) !== dataDatabase);
    let blocked = false;
    try { connection.getDB(other.dataDatabase || other.database).getCollection('_deployment_verification').findOne({}); }
    catch (error) { if (error.code === 13) blocked = true; else throw error; }
    if (!blocked) throw new Error('Cross-database access was not rejected');
    print('PASS: ' + account.service + ' TLS/auth/read/write and foreign-database denial.');
}
