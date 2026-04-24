# PRD — ansible-aws-provisioning
## For Claude Code (terminal)

---

## Git Co-authorship — MANDATORY FIRST STEP

Before generating any file, configure the project to suppress Claude Code co-authorship from all commits:

```bash
# In the project root, after git init:
git config user.name "Marcos Sabatino"
git config user.email "your@email.com"

# Create Claude Code settings file to disable co-authorship
mkdir -p .claude
cat > .claude/settings.json << 'EOF'
{
  "includeCoAuthoredBy": false
}
EOF
```

This file must be committed first, before any other content. No commit in this repository should contain `Co-authored-by: Claude` in the message.

---

## Project Goal

Build an Ansible project that automates **EC2 instance provisioning on AWS** using the `amazon.aws` collection, configures a full application stack (nginx + app), and uses **dynamic inventory** to discover hosts automatically — without a static `hosts.ini` file.

This project is a public GitHub portfolio piece for a **Senior Ansible Automation Engineer** CV. It must demonstrate the ability to manage cloud infrastructure through Ansible, not just configure existing servers.

---

## CV Claims This Project Validates

| CV Statement | Demonstrated by |
|---|---|
| "infrastructure automation" | Ansible provisions EC2, SGs, and configures the full stack |
| "dynamic inventory" | AWS EC2 inventory plugin — hosts discovered at runtime, no static file |
| "integrate systems via APIs" | `amazon.aws` collection calls AWS API directly |
| "design reusable automation frameworks" | Roles with `defaults/`, Galaxy metadata, tag-based execution |
| "Ansible Tower / AAP" | Project structure mirrors AAP Job Templates + dynamic inventory in AAP |
| "provisioning" | EC2 lifecycle management: create, configure, verify, optionally terminate |

---

## Terraform Reuse — IMPORTANT

**Do NOT recreate Terraform from scratch.** This project must reuse the Terraform code from:

```
https://github.com/marcossabatino/ansible-linux-hardening
```

### Instructions for Claude Code:

```bash
# Clone the reference repo to extract Terraform
git clone https://github.com/marcossabatino/ansible-linux-hardening.git /tmp/hardening-ref

# Copy the terraform directory into the new project
cp -r /tmp/hardening-ref/terraform ./terraform

# Clean up
rm -rf /tmp/hardening-ref
```

### Required modifications to the copied Terraform:

1. **`terraform/variables.tf`** — Change defaults:
   - `project_name` default → `"aws-provisioning-lab"`
   - `managed_node_count` default → `2`
   - Add new variable `app_port` (number, default `8080`, description `"Application port exposed by nginx"`)
   - Add new variable `environment` (string, default `"sandbox"`)

2. **`terraform/main.tf`** — Change:
   - `control_node` user_data: also install `ansible-galaxy collection install amazon.aws community.aws` after ansible installation
   - Managed node `user_data`: keep as-is (python3 only)
   - `local.common_tags`: keep all 4 `fo:` tags exactly as-is, change `Project` value to `var.project_name`
   - Security group: add ingress rule for `var.app_port` from `0.0.0.0/0` (for nginx)

3. **`terraform/outputs.tf`** — Add:
   - `app_urls` output: `["http://${ip}:${var.app_port}" for ip in managed_nodes[*].public_ip]`

4. **`terraform/inventory.tftpl`** — Keep identical. No changes needed.

5. **Do NOT add or modify `.gitignore` of the Terraform directory** — the `.gitignore` from the root will cover it.

---

## Directory Structure to Generate

```
ansible-aws-provisioning/
├── .claude/
│   └── settings.json              # Claude Code: co-authorship disabled
├── .gitignore
├── README.md
├── ansible.cfg
├── terraform/                     # Copied + adapted from ansible-linux-hardening
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── inventory.tftpl
├── inventory/
│   ├── .gitkeep
│   └── aws_ec2.yml                # Dynamic inventory — AWS EC2 plugin config
├── group_vars/
│   ├── all.yml                    # Variables shared across all groups
│   └── webservers.yml             # Variables specific to the webservers group
├── playbooks/
│   ├── provision.yml              # Full provisioning: EC2 + stack installation
│   ├── deploy.yml                 # App deployment only (idempotent, no EC2 changes)
│   └── verify.yml                 # Connectivity and service verification
├── roles/
│   └── webserver/
│       ├── defaults/
│       │   └── main.yml
│       ├── handlers/
│       │   └── main.yml
│       ├── meta/
│       │   └── main.yml
│       ├── tasks/
│       │   ├── main.yml
│       │   ├── 1_packages.yml
│       │   ├── 2_nginx.yml
│       │   ├── 3_app.yml
│       │   └── 4_verify.yml
│       └── templates/
│           ├── nginx.conf.j2
│           └── index.html.j2
└── reports/
    └── .gitkeep
```

---

## File-by-File Specifications

---

### `.claude/settings.json`

```json
{
  "includeCoAuthoredBy": false
}
```

---

### `.gitignore`

Exclude:
- `*.pem`, `*.key`
- `*.tfstate`, `*.tfstate.backup`, `.terraform/`, `.terraform.lock.hcl`, `terraform.tfvars`
- `inventory/hosts.ini` — still gitignored even though not used (future compatibility)
- `reports/*.txt`, `reports/*.html`
- `__pycache__/`, `*.pyc`, `.venv/`
- `.DS_Store`
- `*.retry`

---

### `ansible.cfg`

```ini
[defaults]
inventory          = inventory/aws_ec2.yml
roles_path         = roles
host_key_checking  = False
stdout_callback    = yaml
retry_files_enabled = False
remote_user        = ubuntu
private_key_file   = ~/.ssh/id_rsa
enable_plugins     = aws_ec2

[inventory]
enable_plugins = aws_ec2, ini

[privilege_escalation]
become       = True
become_method = sudo
become_user  = root
become_ask_pass = False

[ssh_connection]
pipelining   = True
ssh_args     = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no
```

Key difference from the hardening project: `inventory` points to `aws_ec2.yml` (dynamic), not `hosts.ini`.

---

### `inventory/aws_ec2.yml`

This is the **centerpiece** of the project. It demonstrates dynamic inventory using the AWS EC2 plugin.

```yaml
---
# Dynamic inventory using the AWS EC2 plugin.
# Hosts are discovered at runtime by querying the AWS API — no static file needed.
#
# Usage:
#   ansible-inventory -i inventory/aws_ec2.yml --graph
#   ansible-inventory -i inventory/aws_ec2.yml --list
#
# Requirements:
#   pip3 install boto3 botocore
#   ansible-galaxy collection install amazon.aws

plugin: amazon.aws.aws_ec2

# Filter to only instances from this project (using the fo:owner tag)
filters:
  tag:fo:owner: sabatino
  tag:fo:environment: sandbox
  instance-state-name: running

# Group hosts by the Role tag (control vs managed)
groups:
  control_nodes: "'control' in tags.Role"
  webservers:    "'managed' in tags.Role"

# Additional dynamic groups using keyed_groups
keyed_groups:
  - prefix: az
    key: placement.availability_zone
  - prefix: instance_type
    key: instance_type

# Use public IP for connections
hostnames:
  - ip-address
  - dns-name

compose:
  ansible_host: public_ip_address
  ansible_user: "'ubuntu'"
  instance_name: "tags.Name"

# Refresh cache every 5 minutes
cache: true
cache_plugin: jsonfile
cache_connection: /tmp/.aws_ec2_cache
cache_timeout: 300
```

---

### `group_vars/all.yml`

Variables shared across all hosts:

```yaml
---
# SSH key path for all connections
ansible_ssh_private_key_file: "~/.ssh/id_rsa"
ansible_python_interpreter: /usr/bin/python3

# Project metadata (mirrors Terraform fo: tags)
project_owner: sabatino
project_platform: platform-engineering
project_environment: sandbox

# AWS region (must match Terraform var.aws_region)
aws_region: us-east-1
```

---

### `group_vars/webservers.yml`

Variables specific to the webserver group:

```yaml
---
# Application settings
app_name: demo-app
app_port: 8080
app_version: "1.0.0"
app_root: /var/www/demo-app

# Nginx settings
nginx_worker_processes: auto
nginx_worker_connections: 1024
nginx_keepalive_timeout: 65
nginx_server_name: "{{ inventory_hostname }}"

# Health check endpoint
health_check_path: /health
health_check_expected_status: 200
```

---

### `roles/webserver/meta/main.yml`

```yaml
galaxy_info:
  role_name: webserver
  author: sabatino
  description: Installs and configures nginx with a demo application on Ubuntu 22.04
  company: platform-engineering
  license: MIT
  min_ansible_version: "2.12"
  platforms:
    - name: Ubuntu
      versions: [jammy]
  galaxy_tags:
    - nginx
    - webserver
    - provisioning
    - aws
    - ec2

dependencies: []
```

---

### `roles/webserver/defaults/main.yml`

All default values for the role. Must have inline comments explaining each variable:

```yaml
---
# ── Package installation ───────────────────────────────────────────
packages_to_install:
  - nginx
  - curl
  - python3
  - python3-pip
  - git
  - htop
  - unzip

# ── Nginx configuration ────────────────────────────────────────────
nginx_user: www-data
nginx_worker_processes: auto
nginx_worker_connections: 1024
nginx_keepalive_timeout: 65
nginx_access_log: /var/log/nginx/access.log
nginx_error_log: /var/log/nginx/error.log
nginx_server_name: "{{ ansible_hostname }}"
nginx_root: /var/www/html
nginx_index: index.html

# ── Application settings ───────────────────────────────────────────
app_name: demo-app
app_port: 8080
app_root: /var/www/demo-app
app_version: "1.0.0"

# ── Health check ───────────────────────────────────────────────────
health_check_path: /health
health_check_expected_status: 200
health_check_retries: 5
health_check_delay: 5

# ── Verification report ────────────────────────────────────────────
report_output_dir: /tmp/provision_reports
report_timestamp: "{{ ansible_date_time.iso8601_basic_short }}"
```

---

### `roles/webserver/handlers/main.yml`

```yaml
---
- name: restart nginx
  ansible.builtin.service:
    name: nginx
    state: restarted

- name: reload nginx
  ansible.builtin.service:
    name: nginx
    state: reloaded

- name: validate nginx config
  ansible.builtin.command:
    cmd: nginx -t
  changed_when: false
```

---

### `roles/webserver/tasks/main.yml`

Orchestrator. Must use `ansible.builtin.import_tasks` for each section:

```yaml
---
# Imports in order. Tags allow selective execution:
#   ansible-playbook deploy.yml --tags nginx
#   ansible-playbook deploy.yml --tags app
```

Section imports with tags:

| Import file | Name prefix | Tags |
|---|---|---|
| `1_packages.yml` | `PACKAGES` | `packages`, `install` |
| `2_nginx.yml` | `NGINX` | `nginx`, `configure` |
| `3_app.yml` | `APP` | `app`, `deploy` |
| `4_verify.yml` | `VERIFY` | `verify`, `always` |

---

### `roles/webserver/tasks/1_packages.yml`

Title: `PACKAGES | Install required packages`

Tasks:
1. `PACKAGES | Update apt cache` — `ansible.builtin.apt`: `update_cache: true`, `cache_valid_time: 3600`
2. `PACKAGES | Install required packages` — `ansible.builtin.apt`: loop over `packages_to_install`, `state: present`
3. `PACKAGES | Ensure pip is up to date` — `ansible.builtin.pip`: `name: pip`, `state: latest`, `executable: pip3`

---

### `roles/webserver/tasks/2_nginx.yml`

Title prefix: `NGINX`

Tasks:
1. `NGINX | Ensure nginx is installed` — `ansible.builtin.apt`: `name: nginx`, `state: present`
2. `NGINX | Create application web root directory` — `ansible.builtin.file`: `path: "{{ app_root }}"`, `state: directory`, `owner: "{{ nginx_user }}"`, `mode: '0755'`
3. `NGINX | Deploy nginx virtual host configuration` — `ansible.builtin.template`: `src: nginx.conf.j2`, `dest: /etc/nginx/sites-available/{{ app_name }}`, notify `validate nginx config` then `reload nginx`
4. `NGINX | Enable virtual host (symlink)` — `ansible.builtin.file`: `src: /etc/nginx/sites-available/{{ app_name }}`, `dest: /etc/nginx/sites-enabled/{{ app_name }}`, `state: link`, notify `reload nginx`
5. `NGINX | Disable default nginx site` — `ansible.builtin.file`: `path: /etc/nginx/sites-enabled/default`, `state: absent`, notify `reload nginx`
6. `NGINX | Ensure nginx is started and enabled` — `ansible.builtin.service`: `name: nginx`, `state: started`, `enabled: true`

---

### `roles/webserver/tasks/3_app.yml`

Title prefix: `APP`

Tasks:
1. `APP | Create application directory structure` — `ansible.builtin.file`: `path: "{{ app_root }}"`, state directory, owner `{{ nginx_user }}`
2. `APP | Deploy application index page` — `ansible.builtin.template`: `src: index.html.j2`, `dest: "{{ app_root }}/index.html"`, owner `{{ nginx_user }}`, mode `0644`
3. `APP | Deploy health check endpoint` — `ansible.builtin.copy`:
   ```yaml
   dest: "{{ app_root }}/health"
   content: |
     {"status": "ok", "app": "{{ app_name }}", "version": "{{ app_version }}"}
   owner: "{{ nginx_user }}"
   mode: '0644'
   ```
4. `APP | Set correct permissions on app root` — `ansible.builtin.file`: `path: "{{ app_root }}"`, `recurse: true`, `owner: "{{ nginx_user }}"`, `group: "{{ nginx_user }}"`

---

### `roles/webserver/tasks/4_verify.yml`

Title prefix: `VERIFY`

Tasks (all use `changed_when: false`):

1. `VERIFY | Wait for nginx to be ready` — `ansible.builtin.wait_for`: `port: 80`, `timeout: 30`
2. `VERIFY | Check nginx service status` — `ansible.builtin.service_facts`, then `assert` that nginx is running
3. `VERIFY | Check application HTTP response` — `ansible.builtin.uri`:
   - `url: "http://{{ ansible_host }}:80{{ health_check_path }}"`
   - `status_code: "{{ health_check_expected_status }}"`
   - `retries: "{{ health_check_retries }}"`, `delay: "{{ health_check_delay }}"`
   - Register `health_check_result`
4. `VERIFY | Print verification summary` — `ansible.builtin.debug` with message block:
   ```
   "Host         : {{ ansible_hostname }}"
   "IP           : {{ ansible_host }}"
   "nginx status : {{ ansible_facts.services['nginx.service'].state }}"
   "HTTP status  : {{ health_check_result.status }}"
   "App URL      : http://{{ ansible_host }}/{{ health_check_path }}"
   ```

---

### `roles/webserver/templates/nginx.conf.j2`

A complete nginx server block (not a full nginx.conf — this is a `sites-available` virtual host file):

```nginx
# Managed by Ansible — role: webserver
# Project: {{ app_name }} | Environment: {{ project_environment }}
# Do not edit manually.

server {
    listen 80;
    server_name {{ nginx_server_name }};
    root {{ app_root }};
    index {{ nginx_index }};

    access_log {{ nginx_access_log }};
    error_log  {{ nginx_error_log }};

    keepalive_timeout {{ nginx_keepalive_timeout }};

    location / {
        try_files $uri $uri/ =404;
    }

    location {{ health_check_path }} {
        default_type application/json;
        try_files $uri =404;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
}
```

---

### `roles/webserver/templates/index.html.j2`

A clean, informative HTML page that shows provisioning details — this is what makes the portfolio visually interesting when you share the project:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>{{ app_name }} — {{ project_environment }}</title>
  <style>
    /* dark terminal aesthetic */
    body { background: #0d1117; color: #e6edf3; font-family: 'JetBrains Mono', monospace;
           display: flex; justify-content: center; padding: 60px 20px; }
    .card { max-width: 600px; width: 100%; background: #161b22;
            border: 1px solid #30363d; border-radius: 8px; padding: 40px; }
    .badge { display: inline-block; background: #3fb950; color: #0d1117;
             font-size: 11px; font-weight: 700; padding: 2px 10px;
             border-radius: 20px; margin-bottom: 16px; }
    h1 { font-size: 22px; margin: 0 0 8px; }
    .meta { color: #8b949e; font-size: 13px; margin-top: 24px; }
    .meta div { padding: 6px 0; border-bottom: 1px solid #21262d; }
    .meta div:last-child { border: none; }
    .meta strong { color: #e6edf3; display: inline-block; width: 180px; }
  </style>
</head>
<body>
<div class="card">
  <span class="badge">PROVISIONED BY ANSIBLE</span>
  <h1>{{ app_name }}</h1>
  <p style="color:#8b949e">Version {{ app_version }} — {{ project_environment }}</p>
  <div class="meta">
    <div><strong>Hostname</strong>{{ ansible_hostname }}</div>
    <div><strong>IP Address</strong>{{ ansible_default_ipv4.address }}</div>
    <div><strong>OS</strong>{{ ansible_distribution }} {{ ansible_distribution_version }}</div>
    <div><strong>Kernel</strong>{{ ansible_kernel }}</div>
    <div><strong>fo:owner</strong>{{ project_owner }}</div>
    <div><strong>fo:platform</strong>{{ project_platform }}</div>
    <div><strong>fo:environment</strong>{{ project_environment }}</div>
    <div><strong>Provisioned at</strong>{{ ansible_date_time.iso8601 }}</div>
  </div>
</div>
</body>
</html>
```

---

### `playbooks/provision.yml`

Full provisioning: installs EC2 stack + runs the webserver role.

```yaml
# provision.yml — Full provisioning playbook
# Usage:
#   ansible-playbook -i inventory/aws_ec2.yml playbooks/provision.yml
#   ansible-playbook -i inventory/aws_ec2.yml playbooks/provision.yml --tags nginx
#   ansible-playbook -i inventory/aws_ec2.yml playbooks/provision.yml --check
```

Structure:
- `hosts: webservers`
- `become: true`
- `gather_facts: true`
- `pre_tasks`:
  - Assert Ubuntu >= 20.04
  - `ansible.builtin.raw: apt-get install -y python3` (bootstrap)
  - Update apt cache
- `roles`:
  - `role: webserver`
- `post_tasks`:
  - Print application URL for each host

---

### `playbooks/deploy.yml`

App-only deployment. Does NOT reinstall nginx or touch OS-level config. Safe to run frequently.

```yaml
# deploy.yml — Application-only deployment
# Requires the webserver role to have been provisioned first (provision.yml).
# Usage:
#   ansible-playbook -i inventory/aws_ec2.yml playbooks/deploy.yml
#   ansible-playbook -i inventory/aws_ec2.yml playbooks/deploy.yml -e "app_version=1.1.0"
```

Structure:
- `hosts: webservers`
- `become: true`
- `gather_facts: true`
- Only runs tasks tagged `app` and `verify` from the webserver role
- Use `tags: [app, verify]` on the role import

---

### `playbooks/verify.yml`

Read-only verification playbook. Tests connectivity and service health. No changes applied.

```yaml
# verify.yml — Read-only verification playbook
# Checks nginx and app health on all webservers without making any changes.
# Usage:
#   ansible-playbook -i inventory/aws_ec2.yml playbooks/verify.yml
```

Structure:
- `hosts: webservers`
- `become: false`
- `gather_facts: true`
- Tasks (`changed_when: false` on all):
  1. `ansible.builtin.wait_for`: port 80 reachable
  2. `ansible.builtin.uri`: GET `/health`, expect 200
  3. `ansible.builtin.debug`: print host, IP, status, URL

---

## README.md Specification

Language: **English**. Must be complete and professional.

### Required sections (in order):

1. **Title + Badges** — Ansible, amazon.aws collection, Platform: AWS EC2, OS: Ubuntu 22.04, fo:platform badge, Dynamic Inventory badge

2. **Overview** — Paragraph explaining the project. Include a table:

| Feature | Implementation |
|---|---|
| EC2 discovery | AWS EC2 dynamic inventory plugin (no static hosts.ini) |
| Application stack | nginx + custom HTML app via Ansible templates |
| Idempotent deployment | Full role with handlers, defaults, `--check` mode |
| Health verification | `ansible.builtin.uri` health check with retry |
| Tag-based execution | `--tags packages`, `nginx`, `app`, `verify` |

3. **Enterprise Context** — Explain how `aws_ec2.yml` replaces static inventory in AAP, and how `deploy.yml` maps to a separate AAP Job Template for app-only deployments without full reprovisioning.

4. **Dynamic Inventory — How It Works** — Dedicated section (this is the KEY differentiator). Include:
   - Diagram (ASCII) showing: AWS EC2 API → aws_ec2 plugin → Groups (webservers / control_nodes) → Playbook
   - Commands: `ansible-inventory --graph`, `ansible-inventory --list`
   - Explain the `filters`, `keyed_groups`, and `compose` keys in `aws_ec2.yml`

5. **Repository Structure** — Annotated tree

6. **Terraform Reuse** — Note that Terraform is adapted from `https://github.com/marcossabatino/ansible-linux-hardening` with the changes listed in this PRD

7. **Prerequisites** — Table: Terraform, AWS CLI, Ansible >= 2.12, amazon.aws collection, boto3/botocore

8. **Step-by-Step Execution** — Steps:
   - Step 1: Clone
   - Step 2: Install collections (`ansible-galaxy collection install amazon.aws community.aws`)
   - Step 3: Generate SSH key
   - Step 4: Terraform apply (with expected output)
   - Step 5: Verify dynamic inventory (`ansible-inventory --graph`)
   - Step 6: Run `provision.yml` (with expected output)
   - Step 7: Run `verify.yml`
   - Step 8: Access application in browser

9. **Validation Tests** — Explicit commands:
   - `ansible-inventory --graph` — must show `webservers` group with discovered hosts
   - `ansible-inventory --list | python3 -m json.tool | grep ansible_host` — must show public IPs
   - `ansible webservers -m ping` — SUCCESS on all hosts
   - `curl http://<ip>/health` — `{"status": "ok", ...}`
   - `ansible webservers -m shell -a "systemctl is-active nginx"` — `active`
   - `ansible-lint playbooks/provision.yml` — zero warnings
   - Idempotency: second run of `provision.yml` = `changed=0`

10. **Selective Execution** — Tag table + examples

11. **Customization** — `-e app_version=1.1.0`, `-e app_port=9090`, per-environment `group_vars/`

12. **AWS Resource Tags** — Same `fo:` tags table as the hardening project

13. **Teardown** — `terraform destroy` + note to clean up `.aws_ec2_cache`

14. **CV Alignment** — Table mapping each CV claim to this project

---

## Quality Checklist

Before finalizing each file, verify:

- [ ] `.claude/settings.json` exists with `"includeCoAuthoredBy": false`
- [ ] All YAML files start with `---`
- [ ] All task names follow `"SECTION | Description"` pattern
- [ ] All Ansible modules use FQCNs (`ansible.builtin.*`, `ansible.posix.*`, `amazon.aws.*`)
- [ ] `changed_when: false` on all `shell`/`command` tasks used for checks only
- [ ] No `shell:` or `command:` where a proper module exists
- [ ] `ignore_errors: true` only where explicitly needed
- [ ] `aws_ec2.yml` uses the correct plugin path `amazon.aws.aws_ec2`
- [ ] All templates use `| default('N/A')` for potentially undefined vars
- [ ] Handlers are notified by name string, never called directly
- [ ] `ansible-lint playbooks/provision.yml` would pass with zero warnings
- [ ] README dynamic inventory section has the ASCII diagram
- [ ] No `Co-authored-by` in any git commit message

---

## How to Run with Claude Code

```bash
# 1. Create the project directory
mkdir ansible-aws-provisioning && cd ansible-aws-provisioning
git init

# 2. Open Claude Code
claude

# 3. Paste this PRD and instruct:
# "Generate all files described in this PRD.
#  Start by creating .claude/settings.json to disable co-authorship.
#  Clone the Terraform from the reference repo as specified.
#  Create each file with complete, production-quality content.
#  No placeholders. Follow the quality checklist before finalizing each file."
```
