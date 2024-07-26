#!/bin/bash

# MODIFY - Define the directory structure
BASE_DIR="elasticsearch-setup"
ES_VERSION="8.14.2"
ES_TAR="elasticsearch-${ES_VERSION}-darwin-x86_64.tar.gz"
KIBANA_TAR="kibana-${ES_VERSION}-darwin-x86_64.tar.gz"
CLUSTER_NAME="test-cluster"

# Download Elastic tar.gz if it doesn't exist
if [ ! -f "$ES_TAR" ]; then
  curl -O "https://artifacts.elastic.co/downloads/elasticsearch/${ES_TAR}"
  curl "https://artifacts.elastic.co/downloads/elasticsearch/${ES_TAR}.sha512" | shasum -a 512 -c -
fi

# Download Kibana tar.gz if it doesn't exist
if [ ! -f "$KIBANA_TAR" ]; then
  curl -O "https://artifacts.elastic.co/downloads/kibana/${KIBANA_TAR}"
  curl "https://artifacts.elastic.co/downloads/kibana/${KIBANA_TAR}.sha512" | shasum -a 512 -c -
fi

# Create playbook directory
mkdir -p $BASE_DIR/roles/{common,elasticsearch,kibana}/tasks
mkdir -p $BASE_DIR/roles/{elasticsearch,kibana}/files
mkdir -p $BASE_DIR/roles/elasticsearch/templates/node1
mkdir -p $BASE_DIR/roles/elasticsearch/templates/other-nodes
mkdir -p $BASE_DIR/roles/kibana/templates
mkdir -p $BASE_DIR/elasticsearch/node1
mkdir -p $BASE_DIR/elasticsearch/node2
mkdir -p $BASE_DIR/elasticsearch/node3
mkdir -p $BASE_DIR/kibana

# Create ansible.cfg
cat <<EOL > $BASE_DIR/ansible.cfg
[defaults]
inventory = inventory
host_key_checking = false
roles_path = ./roles
remote_user = $(whoami)
ask_become_pass = true
EOL

# MODIFY Create inventory file - modify node roles as required
cat <<EOL > $BASE_DIR/inventory
[elasticsearch_nodes]
node1 ansible_connection=local network_host=127.0.0.1 http_port=9200
node2 ansible_connection=local network_host=127.0.0.1 http_port=9201 node_roles='["data_hot"]'
node3 ansible_connection=local network_host=127.0.0.1 http_port=9202 node_roles='["data", "data_warm"]'

[kibana]
kibana ansible_connection=local
EOL

# Create playbook.yml
cat <<EOL > $BASE_DIR/playbook.yml
---
- hosts: node1
  become: yes
  roles:
    - elasticsearch

- hosts: node2,node3
  become: yes
  roles:
    - elasticsearch

- hosts: kibana
  become: yes
  roles:
    - kibana
EOL

# Create roles/elasticsearch/tasks/main.yml
cat <<EOL > $BASE_DIR/roles/elasticsearch/tasks/main.yml
---
- name: Ensure Elasticsearch directories exist
  file:
    path: "./elasticsearch/{{ inventory_hostname }}"
    state: directory

- name: Extract Elasticsearch
  command: "tar -xf roles/elasticsearch/files/$ES_TAR -C ./elasticsearch/{{ inventory_hostname }}"
  args:
    creates: ./elasticsearch/{{ inventory_hostname }}/elasticsearch-${ES_VERSION}

- name: Copy Elasticsearch config files for node1
  template:
    src: roles/elasticsearch/templates/node1/elasticsearch.yml.j2
    dest: "./elasticsearch/node1/elasticsearch-${ES_VERSION}/config/elasticsearch.yml"
  when: inventory_hostname == 'node1'

- name: Copy Elasticsearch config files for other nodes
  template:
    src: roles/elasticsearch/templates/other-nodes/elasticsearch.yml.j2
    dest: "./elasticsearch/{{ inventory_hostname }}/elasticsearch-${ES_VERSION}/config/elasticsearch.yml"
  when: inventory_hostname != 'node1'

- name: Start Elasticsearch node 1
  command: >
    osascript -e 'tell app "Terminal"
      do script "cd {{ playbook_dir }}/elasticsearch/node1/elasticsearch-${ES_VERSION} && ./bin/elasticsearch"
    end tell'
  when: inventory_hostname == 'node1'
  async: 1
  delay: 10
  poll: 0

- name: Ensure xpack.security.enrollment.enabled is true
  shell: "grep -q 'xpack.security.enrollment.enabled: true' ./elasticsearch/node1/elasticsearch-${ES_VERSION}/config/elasticsearch.yml"
  register: enrollment_setting
  retries: 20
  delay: 10
  until: enrollment_setting.rc == 0
  when: inventory_hostname == 'node1'

- name: Generate enrollment token
  command: "./elasticsearch/node1/elasticsearch-${ES_VERSION}/bin/elasticsearch-create-enrollment-token -s node"
  register: enrollment_token
  when: inventory_hostname == 'node1'
  until: enrollment_token.rc == 0
  retries: 10

- name: Debug enrollment token
  debug:
    var: enrollment_token.stdout
  when: inventory_hostname == 'node1'

- name: Start Elasticsearch node 2
  command: >
    osascript -e 'tell app "Terminal"
      do script "cd {{ playbook_dir }}/elasticsearch/node2/elasticsearch-${ES_VERSION} && ./bin/elasticsearch --enrollment-token {{ hostvars['node1'].enrollment_token.stdout }}"
    end tell'
  when: inventory_hostname == 'node2'
  async: 1
  poll: 0

- name: Start Elasticsearch node 3
  command: >
    osascript -e 'tell app "Terminal"
      do script "cd {{ playbook_dir }}/elasticsearch/node3/elasticsearch-${ES_VERSION} && ./bin/elasticsearch --enrollment-token {{ hostvars['node1'].enrollment_token.stdout }}"
    end tell'
  when: inventory_hostname == 'node3'
  async: 1
  poll: 0

EOL

# Create roles/kibana/tasks/main.yml
cat <<EOL > $BASE_DIR/roles/kibana/tasks/main.yml
---
- name: Ensure Kibana directory exists
  file:
    path: ./kibana
    state: directory

- name: Extract Kibana
  command: "tar -xf roles/kibana/files/$KIBANA_TAR -C ./kibana"
  args:
    creates: ./kibana/kibana-${ES_VERSION}

- name: Generate Kibana enrollment token
  command: "./elasticsearch/node1/elasticsearch-${ES_VERSION}/bin/elasticsearch-create-enrollment-token -s kibana"
  register: kibana_enrollment_token

- name: Debug Kibana enrollment token
  debug:
    var: kibana_enrollment_token

- name: Start Kibana
  command: >
    osascript -e 'tell app "Terminal"
      do script "cd {{ playbook_dir }}/kibana/kibana-${ES_VERSION} && ./bin/kibana"
    end tell'
  async: 1
  poll: 0
EOL

# Create templates/node1/elasticsearch.yml.j2
cat <<EOL > $BASE_DIR/roles/elasticsearch/templates/node1/elasticsearch.yml.j2
cluster.name: ${CLUSTER_NAME}
node.name: {{ inventory_hostname }}
network.host: {{ network_host }}
http.port: {{ http_port }}
EOL

# Create templates/other-nodes/elasticsearch.yml.j2
cat <<EOL > $BASE_DIR/roles/elasticsearch/templates/other-nodes/elasticsearch.yml.j2
cluster.name: ${CLUSTER_NAME}
node.name: {{ inventory_hostname }}
network.host: {{ network_host }}
http.port: {{ http_port }}
node.roles: {{ node_roles }}
EOL

# Create templates/kibana.yml.j2 - modify as required
cat <<EOL > $BASE_DIR/roles/kibana/templates/kibana.yml.j2
server.port: 5601
server.host: "127.0.0.1"
elasticsearch.hosts: ["https://{{ hostvars['node1'].network_host }}:{{ hostvars['node1'].http_port }}"]
EOL

# Place Elasticsearch and Kibana tar files into the appropriate directories
cp $ES_TAR $BASE_DIR/roles/elasticsearch/files/
cp $KIBANA_TAR $BASE_DIR/roles/kibana/files/

echo "Directory structure and configuration files created."