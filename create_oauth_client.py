#!/usr/bin/env python3

import synapseclient
import json

syn = synapseclient.login()

client_meta_data = {
    "client_name": "imCORE Data Curator",
    "redirect_uris": [
        "https://shinypro.synapse.org/users/bgrande/imcore_data_curator",
        "https://shinypro.synapse.org/users/bgrande/imcore_data_curator_staging",
        "https://curator.imcore.io",
        "http://127.0.0.1:8787",
    ],
    "sector_identifier_uri": "https://raw.githubusercontent.com/imCORE-DCC/data_curator/production/redirect_uris.json",
    "userinfo_signed_response_alg": "RS256",
}

# ----------------------------------------------------------------------------------- #

# This is commented out because it only needs to be run once when
# creating the client. Once you have a client ID, you should be
# updating the existing client using a different PUT endpoint.

# Create the client:
# client_meta_data = syn.restPOST(
#     uri="/oauth2/client",
#     endpoint=syn.authEndpoint,
#     body=json.dumps(client_meta_data)
# )

# Generate and retrieve the client secret:
# client_id_and_secret = syn.restPOST(
#     uri="/oauth2/client/secret/" + client_id, endpoint=syn.authEndpoint, body=""
# )
# print(client_id_and_secret)

# ----------------------------------------------------------------------------------- #

# Get existing client
client_id = "100103"
client = syn.restGET(uri=f"/oauth2/client/{client_id}", endpoint=syn.authEndpoint)

# Update the client metadata with above values:
for field in client_meta_data.keys():
    client[field] = client_meta_data[field]

# Update the client:
client = syn.restPUT(
    uri=f"/oauth2/client/{client_id}",
    endpoint=syn.authEndpoint,
    body=json.dumps(client),
)
