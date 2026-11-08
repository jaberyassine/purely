const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../../deploy-support/mongodb/repair-user-directory.js'), 'utf8');
function run({migrated = false, extraPrivilege = false, wrongOwner = false, writeAllowed = false, rolesAllowed = false} = {}) {
    const config = {admin: {user: 'root', password: 'private-fixture'}, persistenceToken: 'fixture', services: [
        {service: 'auth-service', database: 'purely_auth', user: 'auth'},
        {service: 'user-service', database: 'purely_user', user: 'reader', password: 'private-fixture'}
    ]};
    let role = migrated ? {roles: [], privileges: [{resource: {db: 'purely_auth', collection: 'Users'}, actions: ['find']}]} : null;
    if (extraPrivilege) role.privileges[0].actions.push('insert');
    const mutations = [], output = [];
    const denied = () => { throw Object.assign(new Error('Unauthorized'), {code: 13}); };
    vm.runInNewContext(source, {
        require: () => ({readFileSync: () => JSON.stringify(config)}),
        print: text => output.push(text),
        db: {getSiblingDB: name => {
            if (name === 'admin') return {auth: () => true};
            if (name === 'purely_auth') return {
                getRole: () => role,
                createRole: value => {role = value; mutations.push('create-role');},
                getCollection: () => ({deleteOne: () => mutations.push('cleanup-unexpected-write')})
            };
            assert.equal(name, 'purely_user');
            return {
                getUser: () => ({roles: [{role: wrongOwner ? 'root' : migrated ? 'purelyUserDirectoryRead' : 'readWrite', db: migrated ? 'purely_auth' : 'purely_user'}]}),
                updateUser: (user, value) => {assert.equal(user, 'reader'); assert.equal(value.roles.length, 1); assert.equal(value.roles[0].role, 'purelyUserDirectoryRead'); mutations.push('update-reader');}
            };
        }},
        Mongo: function(uri) {
            assert(uri.includes('/purely_auth?authSource=purely_user&tls=true'));
            return {getDB: name => {assert.equal(name, 'purely_auth'); return {getCollection: collection => ({
                findOne: () => collection === 'Users' || rolesAllowed ? null : denied(),
                insertOne: () => writeAllowed ? {} : denied()
            })};}};
        }
    });
    assert.equal(role.privileges.length, 1);
    assert.equal(role.privileges[0].resource.collection, 'Users');
    assert.equal(role.privileges[0].actions.join(','), 'find');
    assert(output.some(text => text.startsWith('PASS:')));
    assert(output.every(text => !text.includes('private-fixture')));
    return mutations;
}
assert.deepEqual(run(), ['create-role', 'update-reader']);
assert.deepEqual(run({migrated: true}), ['update-reader']);
assert.throws(() => run({migrated: true, extraPrivilege: true}), /Unexpected existing identity reader privileges/);
assert.throws(() => run({wrongOwner: true}), /Unexpected user-service privileges/);
assert.throws(() => run({writeAllowed: true}), /writes were not denied/);
assert.throws(() => run({rolesAllowed: true}), /unintended collection/);
console.log('PASS: identity migration, rerun, strict collection scope, unexpected privileges and denial checks (6 cases).');
