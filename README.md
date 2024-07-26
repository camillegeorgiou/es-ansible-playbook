## Elasticsearch Ansible Playbook

This repo contains a plabook to spin up a 3 cluster Elastic cluster with Kibana and security enabled.
It has been testeed on Mac and will need adjusting to account for other OS's.

The repo contains a script to download Elastic and Kibana and set up the playbook directory.

### Pre-reqs

1. macOS or a Unix-like Operating System - the script uses 'osascript' (specific to Mac) to open new terminal windows. For other operating systems, you would need to adjust the command for starting new terminals.

2. Python

3. Ansible. If not installed, you can use pip or brew:
```
pip install ansible
```
or
```
brew install ansible
```

4. Curl - to download the tar.gz files.

### To Run

1. Clone the repository down and navigate to the set-up.sh script. Modify the following variables in the script to ensure the Elastic Cluster meets your requirements.

```
# MODIFY - Define the directory structure
BASE_DIR="elasticsearch-setup"
ES_VERSION="8.14.2"
ES_TAR="elasticsearch-${ES_VERSION}-darwin-x86_64.tar.gz"
KIBANA_TAR="kibana-${ES_VERSION}-darwin-x86_64.tar.gz"
CLUSTER_NAME="test-cluster"
```

```
# MODIFY Create inventory file - modify node roles as required
cat <<EOL > $BASE_DIR/inventory
[elasticsearch_nodes]
node1 ansible_connection=local network_host=127.0.0.1 http_port=9200
node2 ansible_connection=local network_host=127.0.0.1 http_port=9201 node_roles='["data_hot"]'
node3 ansible_connection=local network_host=127.0.0.1 http_port=9202 node_roles='["data", "data_warm"]'

[kibana]
kibana ansible_connection=local
EOL
```

2. Modify perms to run the setup script:

```
chmod +x set-up.sh
```

2. Run set-up.sh to create the playbook structure. If set up has been succesful, you should see the following message in the console:

"Directory structure and configuration files created."

3. Navigate to the root of the folder and run:

```
ansible-playbook playbook.yml --ask-become
```

The password asked for is that of the user running the playbook.

4. The Kibana enrollment token is printed in the console. Paste this into the broswer when prompted.

5. The Elastic user password will have been printed in the terminal running Node1, however to generate a new password, open a new terminal, navigate to the node1 dir and run:

```
bin/elasticsearch-reset-password -u elastic
```
