// Executed through kubectl exec on the database pod, over verified loopback TLS.
// This file contains no credentials; the bootstrap Secret is generated on the operator's machine.
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('/bootstrap/users.json', 'utf8'));
const admin = db.getSiblingDB('admin');
let authenticated = false;
try { authenticated = !!admin.auth(config.admin.user, config.admin.password); } catch (_) {}
if (!authenticated) {
    // MongoDB's localhost exception allows only initial administrator creation.
    admin.createUser({user: config.admin.user, pwd: config.admin.password, roles: [{role: 'root', db: 'admin'}]});
    if (!admin.auth(config.admin.user, config.admin.password)) throw new Error('Administrator authentication failed');
}
for (const account of config.services) {
    const database = db.getSiblingDB(account.database);
    const existing = database.getUser(account.user);
    if (!existing) database.createUser({user: account.user, pwd: account.password, roles: [{role: 'readWrite', db: account.database}]});
    else if (existing.roles.length !== 1 || existing.roles[0].role !== 'readWrite' || existing.roles[0].db !== account.database) {
        throw new Error('Unexpected existing database permissions for ' + account.service);
    }
}
print('PASS: administrator and six database-scoped application accounts are ready.');
