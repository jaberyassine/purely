// Migrate only the demo user-service account. No application documents are modified.
const config = JSON.parse(require('fs').readFileSync('/bootstrap/users.json', 'utf8'));
const auth = config.services.find(account => account.service === 'auth-service');
const reader = config.services.find(account => account.service === 'user-service');
if (!auth || !reader || auth.database !== 'purely_auth' || reader.database !== 'purely_user') throw new Error('Unexpected demo identity database mapping');
const admin = db.getSiblingDB('admin');
if (!admin.auth(config.admin.user, config.admin.password)) throw new Error('Administrator authentication failed');
const identity = db.getSiblingDB(auth.database);
const roleName = 'purelyUserDirectoryRead';
let role = identity.getRole(roleName, {showPrivileges: true});
if (!role) {
    identity.createRole({role: roleName, privileges: [{resource: {db: auth.database, collection: 'Users'}, actions: ['find']}], roles: []});
    role = identity.getRole(roleName, {showPrivileges: true});
}
if (role.roles.length !== 0 || role.privileges.length !== 1 || role.privileges[0].resource.db !== auth.database
    || role.privileges[0].resource.collection !== 'Users' || role.privileges[0].actions.length !== 1 || role.privileges[0].actions[0] !== 'find') {
    throw new Error('Unexpected existing identity reader privileges');
}
const accounts = db.getSiblingDB(reader.database);
const existing = accounts.getUser(reader.user);
if (!existing || existing.roles.length !== 1) throw new Error('Unexpected existing user-service account');
const oldRole = existing.roles[0];
if (!((oldRole.role === 'readWrite' && oldRole.db === reader.database) || (oldRole.role === roleName && oldRole.db === auth.database))) {
    throw new Error('Unexpected user-service privileges; stop before replacement');
}
accounts.updateUser(reader.user, {roles: [{role: roleName, db: auth.database}]});
const connection = new Mongo('mongodb://' + encodeURIComponent(reader.user) + ':' + encodeURIComponent(reader.password)
    + '@localhost:27017/' + auth.database + '?authSource=' + reader.database + '&tls=true&tlsCAFile=/etc/mongodb/tls/ca.crt');
connection.getDB(auth.database).getCollection('Users').findOne({}, {_id: 1});
const marker = '__readonly_check_' + config.persistenceToken;
let denied = false;
try { connection.getDB(auth.database).getCollection('Users').insertOne({_id: marker}); }
catch (error) { if (error.code === 13) denied = true; else throw error; }
if (!denied) { identity.getCollection('Users').deleteOne({_id: marker}); throw new Error('User-directory writes were not denied'); }
denied = false;
try { connection.getDB(auth.database).getCollection('Roles').findOne({}); }
catch (error) { if (error.code === 13) denied = true; else throw error; }
if (!denied) throw new Error('The identity reader can read an unintended collection');
print('PASS: user-service can read identity Users only; writes and Roles reads are denied.');
