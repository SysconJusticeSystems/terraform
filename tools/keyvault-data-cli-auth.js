/**
 * Terraform external data source for reading data from an azure key vault
 *
 * Requires environment variables for azure auth:
 *   ARM_CLIENT_ID
 *   ARM_CLIENT_SECRET
 *
 * Expects the following structure as JSON via stdin:
 * {
 *   "vault": "<name of vault>",
 *   "<secret output name 1>": "<secret vault name 1>",
 *   "<secret output name 2>": "<secret vault name 2>",
 *   "<secret output name 3>": "<secret vault name 3>",
 *   "<secret output name 4>": "<secret vault name 4>",
 *   ...
 * }
 *
 * And produces the following structure as JSON via stdout:
 * {
 *   "<secret output name 1>": "<secret value 1>",
 *   "<secret output name 2>": "<secret value 2>",
 *   "<secret output name 3>": "<secret value 3>",
 *   "<secret output name 4>": "<secret value 4>",
 *   ...
 * }
 */

const fs = require('fs');
const url = require('url');

const KeyVault = require('azure-keyvault');

main();

function main() {
  const input = loadInput();

  const clientId = process.env.ARM_CLIENT_ID;
  const clientSecret = process.env.ARM_CLIENT_SECRET;

  const client = createVaultClient(clientId, clientSecret);

  const vaultUri = buildVaultUri(input.vault)

  const secretsP = input.secrets
    .map((secret) => getSecret(
      client,
      secret.name,
      buildSecretId(vaultUri, secret.id)
    ));

  Promise.all(secretsP)
    .then(
      (secrets) => {
        const output = {};
        secrets.forEach((secret) => {
          output[secret.name] = secret.value;
        });
        console.log("%j", output);
      }
    )
    .catch((err) => {
      console.error(err.stack);
      process.exit(1);
    });
}

function loadInput() {
  const data = JSON.parse(fs.readFileSync(0, 'utf8'));
  input = {
    vault: "",
    secrets: []
  };
  Object.keys(data).forEach((key) => {
    if (key == "vault") {
      input.vault = data[key];
    } else {
      input.secrets.push({
        name: key,
        id: data[key]
      });
    }
  });
  return input;
}

function getSecret(client, name, secretId) {
  return client.getSecret(secretId)
    .then((secret) => ({
      name, value: secret.value
    }))
}

function buildSecretId(vaultUri, name) {
  return `${vaultUri}/secrets/${name}`;
}

function buildVaultUri(vaultName) {
  return `https://${vaultName}.vault.azure.net`;
}

const AuthenticationContext = require('adal-node').AuthenticationContext;

function createVaultClient(clientId, clientSecret) {

  const credentials = new KeyVault.KeyVaultCredentials(authenticator);

  return new KeyVault.KeyVaultClient(credentials);

  function authenticator(challenge, callback) {
    getAzureAuthorizationFromCli(challenge.resource, function(err, auth) {
      if (err) return callback(err);
      return callback(null, auth.tokenType + ' ' + auth.accessToken);
    });
  }

}

function getAzureAuthorizationFromCli(resource, callback) {
  const exec = require('child_process').exec;
  exec(
    'az account get-access-token --resource "' + resource  + '"', 
    function(err, result) {
      if (err) return callback(err);
      try {
        return callback(null, JSON.parse(result));
      } catch (ex) {
        return callback(ex);
      }
    }
  );
}
