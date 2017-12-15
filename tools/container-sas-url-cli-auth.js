/**
 * Terraform external data source for generating a storage SAS url
 *
 * Expects the following structure as JSON via stdin:
 * {
 *   "subscription_id": "<subscription id>",
 *   "tenant_id": "<tenant id>",
 *   "resource_group": "<resource group name>",
 *   "storage_account": "<storage account name>",
 *   "container": "<container name>",
 *   "permissions": "<permissions string, see azure docs>",
 *   "start_date": "<start date in ISO8601 format>",
 *   "end_date": "<start date in ISO8601 format>"
 * }
 *
 * And produces the following structure as JSON via stdout:
 * {
 *   "url": "<SAS url>",
 *   "token": "<SAS token only>"
 * }
 */

const fs = require('fs');

const azure = require('azure');

main();

function main() {
  const input = loadInput();

  const resourceGroup = input.resource_group;
  const accountName = input.storage_account;
  const container = input.container;
  const permissions = input.permissions;
  const startDate = new Date(input.start_date);
  const endDate = new Date(input.end_date);

  let client;

  createStorageClient()
    .then((_client) => {
      client = _client;
      return client.listServiceSAS(
        resourceGroup,
        accountName,
        {
          canonicalizedResource: `/blob/${accountName}/${container}`,
          resource: "c",
          permissions: permissions,
          sharedAccessStartTime: startDate,
          sharedAccessExpiryTime: endDate
        }
      );
    })
    .then((response) => promisedProperties({
      sasToken: response.serviceSasToken,
      properties: client.getProperties(resourceGroup, accountName)
    }))
    .then(({sasToken, properties}) => {
      const url = properties.primaryEndpoints.blob + container + "?" + sasToken;
      console.log("%j", {url, token: sasToken});
    })
    .catch((err) => {
      console.error(err.stack);
      process.exit(1);
    });
    function createStorageClient() {
      return Promise.resolve()
        .then(() => {
          const creds = loadLocalCredentials(input.subscription_id);
          return azure
            .createStorageManagementClient(creds, input.subscription_id)
            .storageAccounts;
        });
    }

}

const exec = require('child_process').execSync;
function loadLocalCredentials(subscriptionId) {
  try {
    const tokenData = exec(`az account get-access-token -s '${subscriptionId}'`);
    const data = JSON.parse(tokenData);
    const authorization = `${data.tokenType} ${data.accessToken}`;

    return {
      signRequest(webResource, callback) {
        webResource.headers.authorization = authorization;
        return callback(null);
      }
    };
  } catch (ex) {
    throw new Error(`
      Couldn't get valid azure token for ${subscriptionId}.
      Use \`az login\` to populate local credential file first.
      Error: ${ex.message}
    `);
  }
}

function loadInput() {
  const data = JSON.parse(fs.readFileSync(0, 'utf8'));
  return data;
}

function promisedProperties(object) {
  const keys = Object.keys(object);
  const values = keys.map((key) => object[key]);

  return Promise.all(values)
    .then((resolvedValues) => {
      const resolvedObject = {};
      resolvedValues.forEach((value, index) => {
        resolvedObject[keys[index]] = value;
      });
      return resolvedObject;
    });
}
