const argv = require('yargs')
  .option('hostname', {
    alias: 'h',
    describe: 'hostname to get a certificate for'
  })
  .option('certbot', {
    alias: 'c',
    describe: 'location of certbot config directory'
  })
  .option('vault', {
    alias: 'v',
    describe: 'keyvault name in which to store resulting cerificate'
  })
  .options('zone', {
    alias: 'z',
    describe: 'Azure DNS zone the hostname lives in'
  })
  .options('subscription', {
    alias: 's',
    describe: 'Azure subscription ID'
  })
  .options('tenant', {
    alias: 't',
    describe: 'Azure AD tenant ID'
  })
  .demandOption([
    'hostname', 'certbot', 'vault', 'zone',
    'subscription', 'tenant'
  ])
  .argv;

const azure = require('azure');
const KeyVault = require('azure-keyvault');
const LE = require('greenlock');
const pify = require('pify');
const pem = require('pem');
const util = require('util');
const crypto = require('crypto');
const base64url = require('base64-url');

const createPkcs12 = pify(pem.createPkcs12);

function main() {
  let dnsClient, certDetails, secretName;
  const keyVaultClient = createKeyVaultClient();
  createDNSClient()
    .then((_dnsClient) => { dnsClient = _dnsClient; })
    .then(() => {
      return lookupZoneDetails(dnsClient);
    })
    .then((zoneDetails) => {
      return createCertificate(dnsClient, zoneDetails);
    })
    .then((result) => {
      console.log("Got certificates from letsencrypt");
      certDetails = result;

      if (argv.vault == '-') {
        console.log("Skipping vault upload");
        return null;
      }

      return createPkcs12(
        certDetails.privkey,
        certDetails.cert,
        "", // password
        {certFiles: [certDetails.chain]}
      );
    })
    .then((pkcs12file) => {
      if (!pkcs12file) {
        return;
      }

      secretName = buildCertSecretName(certDetails.subject);
      console.log("storing to %s as %s", argv.vault, secretName);
      return keyVaultClient.setSecret(
        buildVaultUri(argv.vault),
        secretName,
        pkcs12file.pkcs12.toString('base64'),
        {
          contentType: 'application/x-pkcs12',
          secretAttributes: {
            enabled: true,
            notBefore: certDetails._issuedAt,
            expires: certDetails._expiresAt
          }
        }
      )
    })
    .catch((err) => {
      console.error(err.stack);
      process.exit(1);
    });
}

function getenv(name) {
  if (name in process.env) {
    return process.env[name];
  }
  throw new Error(`Missing ${name} environment variable`)
}

function createDNSClient() {
  const clientId = getenv('ARM_CLIENT_ID');
  const clientSecret = getenv('ARM_CLIENT_SECRET');

  return azure.loginWithServicePrincipalSecret(
    clientId, clientSecret, argv.tenant
  )
    .then((creds) => azure.createDnsManagementClient(creds, argv.subscription));
}
function createKeyVaultClient() {
  const clientId = getenv('ARM_CLIENT_ID');
  const clientSecret = getenv('ARM_CLIENT_SECRET');

  const credentials = new KeyVault.KeyVaultCredentials(authenticator);
  return new KeyVault.KeyVaultClient(credentials);

  function authenticator(challenge, callback) {
    const AuthenticationContext = require('adal-node').AuthenticationContext;
    var context = new AuthenticationContext(challenge.authorization);
    return context.acquireTokenWithClientCredentials(
      challenge.resource, clientId, clientSecret,
      function(err, response) {
        if (err) return callback(err);
        callback(null, response.tokenType + ' ' + response.accessToken);
      }
    );
  }
}

function buildVaultUri(vaultName) {
  return `https://${vaultName}.vault.azure.net`;
}
function buildCertSecretName(name) {
  return name.replace(/\./g, 'DOT');
}

function lookupZoneDetails(dnsClient) {
  return dnsClient.zones.list()
    .then((zones) => matchZone(zones, argv.zone));
}

function matchZone(zones, zoneName) {
  const zone = zones.filter((z) => z.name === zoneName)[0];
  if (!zone) {
    throw new Error(`Failed to find existing zone ${zoneName}`);
  }
  return {
    name: zone.name,
    resourceGroup: extractResourceGroup(zone.id)
  };
}

function extractResourceGroup(resourceId) {
  const bits = resourceId.split('/');
  const rgIndex = bits.indexOf('resourceGroups');
  if (rgIndex === -1) {
    throw new Error(`Failed to decipher resource group from ${resourceId}`);
  }
  return bits[rgIndex + 1];
}

function buildChallengeDomain(hostname, zone) {
  if (hostname.endsWith(zone)) {
    return '_acme-challenge.' + hostname.replace('.' + zone, '');
  }
  throw new Error(`${hostname} doesn't seem to be inside ${zone}`);
}

function buildKeyAuthorization(key) {
  return base64url.encode(
    crypto.createHash('sha256')
      .update(key)
      .digest()
    );
}

function createCertificate(dnsClient, zoneDetails) {
  const challenge = {
    getOptions: () => ({}),
    set(opts, domain, key, value, callback) {
      const keyAuthorization = buildKeyAuthorization(value);
      console.log('Creating %s %s', domain, keyAuthorization);
      dnsClient.recordSets.createOrUpdate(
        zoneDetails.resourceGroup,
        zoneDetails.name,
        buildChallengeDomain(domain, zoneDetails.name),
        'TXT',
        {
          tTL: 60,
          txtRecords: [{value: [keyAuthorization]}]
        }
      ).then((r) => callback(), callback);
    },
    get(opts, domain, key, callback) {
      console.log('domain get', domain, key);
    },
    remove(opts, domain, key, callback) {
      console.log('Deleting %s', domain);
      dnsClient.recordSets.deleteMethod(
        zoneDetails.resourceGroup,
        zoneDetails.name,
        buildChallengeDomain(domain, zoneDetails.name),
        'TXT'
      ).then((r) => callback(), callback);
    }
  }
  return LE.create({
    server: 'production',
    store: require('le-store-certbot').create({
      configDir: argv.certbot,
    }),
    challenges: {
      'dns-01': challenge,
    },
    debug: true,
  }).register({
    domains: [argv.hostname],
    email: 'noms-studio-webops@digital.justice.gov.uk',
    challengeType: 'dns-01',
    agreeTos: true,
  });
}

main();
