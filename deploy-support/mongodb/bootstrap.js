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
    let expected = {role: 'readWrite', db: account.database};
    if (account.accessMode === 'identity-readonly') {
        const identity = db.getSiblingDB(account.dataDatabase);
        const roleName = 'purelyUserDirectoryRead';
        let role = identity.getRole(roleName, {showPrivileges: true});
        if (!role) {
            identity.createRole({role: roleName, privileges: [{resource: {db: account.dataDatabase, collection: 'Users'}, actions: ['find']}], roles: []});
            role = identity.getRole(roleName, {showPrivileges: true});
        }
        if (role.roles.length !== 0 || role.privileges.length !== 1 || role.privileges[0].resource.db !== account.dataDatabase
            || role.privileges[0].resource.collection !== 'Users' || role.privileges[0].actions.length !== 1 || role.privileges[0].actions[0] !== 'find') {
            throw new Error('Unexpected identity reader privileges');
        }
        expected = {role: roleName, db: account.dataDatabase};
    }
    const existing = database.getUser(account.user);
    if (!existing) database.createUser({user: account.user, pwd: account.password, roles: [expected]});
    else if (existing.roles.length !== 1 || existing.roles[0].role !== expected.role || existing.roles[0].db !== expected.db) {
        throw new Error('Unexpected existing database permissions for ' + account.service);
    }
}
print('PASS: administrator and six scoped application accounts are ready.');
