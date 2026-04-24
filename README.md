# Ansible AWS Provisioning

[![Ansible](https://img.shields.io/badge/ansible-%3E%3D2.12-blue?logo=ansible)](https://docs.ansible.com/)
[![amazon.aws](https://img.shields.io/badge/amazon.aws-collection-orange)](https://galaxy.ansible.com/amazon/aws)
[![Platform: AWS EC2](https://img.shields.io/badge/Platform-AWS%20EC2-orange?logo=amazon-aws)](https://aws.amazon.com/ec2/)
[![OS: Ubuntu 22.04](https://img.shields.io/badge/OS-Ubuntu%2022.04-orange?logo=ubuntu)](https://ubuntu.com/)
[![fo:platform: platform-engineering](https://img.shields.io/badge/fo%3Aplatform-platform--engineering-brightgreen)](#aws-resource-tags)
[![Dynamic Inventory](https://img.shields.io/badge/Dynamic%20Inventory-AWS%20EC2%20Plugin-blue)](#dynamic-inventory--how-it-works)

---

## Overview

This project demonstrates **infrastructure automation at scale** using Ansible to provision and configure AWS EC2 instances. Unlike traditional static inventories, it employs AWS EC2 dynamic inventory discovery, eliminating the need to manually maintain a `hosts.ini` file. The playbooks orchestrate a complete application stack: EC2 instance provisioning, nginx configuration, application deployment, and automated health verification — all driven by Ansible's idempotent roles and handlers.

### Key Features

| Feature | Implementation |
|---|---|
| **EC2 discovery** | AWS EC2 dynamic inventory plugin — hosts discovered at runtime, no static hosts file |
| **Application stack** | nginx + custom HTML app deployed via Ansible templates |
| **Idempotent provisioning** | Full role with handlers, defaults, and `--check` mode support |
| **Health verification** | HTTP health check with retry logic using `ansible.builtin.uri` |
| **Tag-based execution** | Selective task execution via `--tags packages`, `nginx`, `app`, `verify` |
| **Terraform integration** | EC2 + security group lifecycle managed by Terraform |

---

## Enterprise Context

This project mirrors an **Ansible Automation Platform (AAP)** deployment pattern where:

1. **Dynamic Inventory** (`aws_ec2.yml`) replaces static inventory files in AAP, enabling automatic host discovery as infrastructure scales.
2. **Separate Job Templates**: `provision.yml` handles full infrastructure setup, while `deploy.yml` allows rapid app-only updates without full reprovisioning.
3. **RBAC & Governance**: The `fo:` tags align with platform-engineering governance policies for cost allocation and compliance.

In production AAP deployments, each playbook would be a separate Job Template with its own credential store, audit trail, and notifications.

---

## Dynamic Inventory — How It Works

The **AWS EC2 plugin** dynamically discovers hosts by querying the AWS API, grouping them by tags, and composing dynamic groups at runtime.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ AWS EC2 API                                                     │
│ Running instances with tags:                                    │
│  - fo:owner: sabatino                                           │
│  - fo:environment: sandbox                                      │
│  - Role: control / managed                                      │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
                    ┌─────────────────────┐
                    │ aws_ec2.yml Plugin  │
                    │ (inventory plugin)  │
                    └────────┬────────────┘
                             │
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                  ▼
    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
    │ control_nodes│  │  webservers  │  │  az_us-east-1a
    │ (Role=control)│  │(Role=managed)│  │ instance_type_t3micro
    │              │  │              │  │
    │ - control-1  │  │ - managed-1  │  │
    │              │  │ - managed-2  │  │
    └──────────────┘  └──────────────┘  └──────────────┘
          │                  │                  │
          └──────────────────┼──────────────────┘
                             │
                             ▼
                    ┌─────────────────────┐
                    │  Playbook Execution │
                    │  ansible-playbook   │
                    │  -i aws_ec2.yml     │
                    └─────────────────────┘
```

### Query and Inspection Commands

Inspect the dynamic inventory without running a playbook:

```bash
# Show groups and hosts in tree format
ansible-inventory -i inventory/aws_ec2.yml --graph

# List all hosts in JSON format (verbose)
ansible-inventory -i inventory/aws_ec2.yml --list | python3 -m json.tool

# Find all ansible_host (public IP) entries
ansible-inventory -i inventory/aws_ec2.yml --list | python3 -m json.tool | grep -A 2 ansible_host
```

### How `aws_ec2.yml` Works

The plugin configuration in `inventory/aws_ec2.yml` specifies:

| Section | Purpose |
|---|---|
| **plugin** | `amazon.aws.aws_ec2` — activates the AWS EC2 inventory plugin |
| **filters** | Query AWS API for instances with specific tags and state |
| **groups** | Assign instances to groups based on tag values (`Role: control` → `control_nodes`) |
| **keyed_groups** | Create dynamic groups by instance attributes (AZ, instance type) |
| **compose** | Compute host variables from instance data (`ansible_host: public_ip_address`) |
| **cache** | Cache results for 5 minutes to reduce API calls |

Example filter execution:

```yaml
filters:
  tag:fo:owner: sabatino           # Only instances tagged with this owner
  tag:fo:environment: sandbox       # Only sandbox environment
  instance-state-name: running      # Only running instances
```

This eliminates the need to manually edit `hosts.ini` — any new EC2 instance tagged appropriately is instantly discoverable.

---

## Repository Structure

```
ansible-aws-provisioning/
├── .claude/
│   └── settings.json                  # Claude Code settings (no co-authorship)
├── .gitignore                         # Exclude keys, state files, reports
├── README.md                          # This file
├── ansible.cfg                        # Ansible configuration (points to aws_ec2.yml)
│
├── terraform/                         # Terraform to provision AWS resources
│   ├── main.tf                        # EC2, security groups, tags, user_data
│   ├── variables.tf                   # Customizable project parameters
│   ├── outputs.tf                     # EC2 IPs, app URLs, SSH commands
│   └── inventory.tftpl                # Template for static inventory (future use)
│
├── inventory/
│   ├── .gitkeep
│   ├── aws_ec2.yml                    # Dynamic inventory configuration
│   └── hosts.ini                      # Generated by Terraform (gitignored)
│
├── group_vars/
│   ├── all.yml                        # Common variables (keys, AWS region, tags)
│   └── webservers.yml                 # Variables specific to webserver group
│
├── playbooks/
│   ├── provision.yml                  # Full provisioning: EC2 + stack
│   ├── deploy.yml                     # App-only deployment (post-provision)
│   └── verify.yml                     # Read-only health checks
│
├── roles/
│   └── webserver/
│       ├── defaults/main.yml          # Role defaults (all variables with comments)
│       ├── handlers/main.yml          # Handlers for service restarts
│       ├── meta/main.yml              # Galaxy metadata
│       ├── tasks/
│       │   ├── main.yml               # Imports other task files
│       │   ├── 1_packages.yml         # Install system packages
│       │   ├── 2_nginx.yml            # Configure nginx
│       │   ├── 3_app.yml              # Deploy application
│       │   └── 4_verify.yml           # Health verification
│       └── templates/
│           ├── nginx.conf.j2          # nginx vhost configuration
│           └── index.html.j2          # Application landing page
│
└── reports/
    └── .gitkeep                       # Placeholder for verification reports
```

---

## Terraform Reuse

**All Terraform files are adapted from** [`marcossabatino/ansible-linux-hardening`](https://github.com/marcossabatino/ansible-linux-hardening).

### Changes Made

1. **`variables.tf`**:
   - `project_name` default: `"aws-provisioning-lab"`
   - `managed_node_count`: `2` (unchanged but intentional)
   - Added `app_port` (default `8080`)
   - Added `environment` (default `"sandbox"`)

2. **`main.tf`**:
   - Control node `user_data` now installs Ansible collections:
     ```bash
     ansible-galaxy collection install amazon.aws community.aws
     ```
   - Security group: added ingress rule for `app_port` from `0.0.0.0/0`
   - Tags: all 4 `fo:` tags preserved, `Project` uses `var.project_name`

3. **`outputs.tf`**:
   - Added `app_urls` output for direct access to provisioned apps

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| **Terraform** | >= 1.3.0 | Provision AWS resources |
| **AWS CLI** | >= 2.0 | Authenticate with AWS |
| **Ansible** | >= 2.12 | Orchestrate configuration |
| **amazon.aws collection** | Latest | AWS API integration |
| **boto3 / botocore** | Latest | AWS Python SDK (for dynamic inventory) |
| **SSH key** | RSA 4096+, named `ansible-aws-provisioning` | EC2 access |

---

## Step-by-Step Execution

### Step 1: Clone Repository

```bash
git clone https://github.com/marcossabatino/ansible-aws-provisioning.git
cd ansible-aws-provisioning
```

### Step 2: Install Collections

```bash
ansible-galaxy collection install amazon.aws community.aws
```

**Expected output:**
```
Starting galaxy collection install process
Process install dependency map
Starting collection download process
Downloading https://galaxy.ansible.com/download/amazon-aws-X.X.X.tar.gz
Installing 'amazon.aws:X.X.X' to '~/.ansible/collections/ansible_collections/amazon/aws'
```

### Step 3: Generate SSH Key (if needed)

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/ansible-aws-provisioning -N ""
ssh-add ~/.ssh/ansible-aws-provisioning
```

This creates:
- `~/.ssh/ansible-aws-provisioning` (private key — keep secure!)
- `~/.ssh/ansible-aws-provisioning.pub` (public key — uploaded to AWS)

### Step 4: Terraform Apply

```bash
cd terraform
terraform init
terraform apply

# Approve the plan and wait ~2 minutes for EC2 instances to launch
```

**Expected output:**
```
aws_key_pair.provisioning_lab: Creating...
aws_security_group.provisioning_lab: Creating...
aws_instance.control_node: Creating...
aws_instance.managed_nodes[0]: Creating...
aws_instance.managed_nodes[1]: Creating...

Apply complete! Resources created:
  control_node_public_ip: 54.XX.XXX.XXX
  managed_nodes_public_ips: [54.XX.XXX.XXX, 54.XX.XXX.XXX]
  app_urls: [http://54.XX.XXX.XXX:8080, http://54.XX.XXX.XXX:8080]
```

**Note:** Save the IPs — they will be needed in Step 5.

### Step 5: Verify Dynamic Inventory

```bash
cd ..
ansible-inventory -i inventory/aws_ec2.yml --graph
```

**Expected output:**
```
@all:
  |--@ungrouped:
  |--@webservers:
  |  |--ip-XX-XXX-XXX-XXX
  |  |--ip-XX-XXX-XXX-XXX
  |--@control_nodes:
  |  |--ip-XX-XXX-XXX-XXX
  |--@az_us-east-1a:
  |  |--ip-XX-XXX-XXX-XXX
  |  |--ip-XX-XXX-XXX-XXX
  |  |--ip-XX-XXX-XXX-XXX
  |--@instance_type_t3micro:
  |  |--ip-XX-XXX-XXX-XXX
  |  |--ip-XX-XXX-XXX-XXX
  |  |--ip-XX-XXX-XXX-XXX
```

If `webservers` group is empty, check:
1. Instances are running: `aws ec2 describe-instances --query 'Reservations[].Instances[].State.Name'`
2. Tags are correct: `aws ec2 describe-instances --query 'Reservations[].Instances[].Tags'`
3. AWS credentials are configured: `aws sts get-caller-identity`

### Step 6: Run Provision Playbook

```bash
ansible-playbook -i inventory/aws_ec2.yml playbooks/provision.yml
```

**Expected output (first run):**
```
PLAY [Provision EC2 instances with full stack] ****************************
TASK [Assert Ubuntu >= 20.04] **********************************************
ok: [ip-XX-XXX-XXX-XXX]
ok: [ip-XX-XXX-XXX-XXX]

TASK [PACKAGES | Update apt cache] ******************************************
changed: [ip-XX-XXX-XXX-XXX]
changed: [ip-XX-XXX-XXX-XXX]

TASK [NGINX | Ensure nginx is installed] ************************************
changed: [ip-XX-XXX-XXX-XXX]
changed: [ip-XX-XXX-XXX-XXX]

TASK [VERIFY | Check application HTTP response] ****************************
ok: [ip-XX-XXX-XXX-XXX]
ok: [ip-XX-XXX-XXX-XXX]

PLAY RECAP ********************************************************************
ip-XX-XXX-XXX-XXX : ok=18  changed=12  unreachable=0    failed=0
ip-XX-XXX-XXX-XXX : ok=18  changed=12  unreachable=0    failed=0
```

### Step 7: Run Verify Playbook

```bash
ansible-playbook -i inventory/aws_ec2.yml playbooks/verify.yml
```

**Expected output:**
```
PLAY [Verify provisioning and service health] ****************************
TASK [VERIFY | Wait for port 80 reachable] *****************************
ok: [ip-XX-XXX-XXX-XXX]
ok: [ip-XX-XXX-XXX-XXX]

TASK [VERIFY | Check health endpoint] **********************************
ok: [ip-XX-XXX-XXX-XXX]
ok: [ip-XX-XXX-XXX-XXX]

TASK [VERIFY | Print host status] **************************************
ok: [ip-XX-XXX-XXX-XXX] => {
    "msg": "Host:   managed-1\nIP:     54.XX.XXX.XXX\nStatus: 200\nURL:    http://54.XX.XXX.XXX/health\n"
}
```

### Step 8: Access Application in Browser

Open the app URLs from the `app_urls` Terraform output:

```bash
# Get the URLs
terraform output app_urls

# Open in browser (macOS)
open "http://54.XX.XXX.XXX:8080"

# Or curl to check
curl -s http://54.XX.XXX.XXX:8080 | head -20
curl http://54.XX.XXX.XXX:8080/health | python3 -m json.tool
```

You should see:
1. The provisioned landing page (dark terminal aesthetic)
2. Host information: hostname, IP, OS, kernel
3. Project metadata: `fo:owner`, `fo:platform`, `fo:environment`, provisioning timestamp

---

## Validation Tests

Run these commands to validate the deployment:

### 1. Dynamic Inventory Discovery

```bash
# Show all groups
ansible-inventory -i inventory/aws_ec2.yml --graph

# Verify webservers group exists and contains hosts
ansible-inventory -i inventory/aws_ec2.yml --graph | grep -A 10 webservers
```

Expected: At least 2 hosts under `webservers` group.

### 2. Ansible Connectivity

```bash
# Test SSH connectivity to all hosts
ansible webservers -m ping
```

Expected: All hosts return `pong`.

```
ip-XX-XXX-XXX-XXX | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

### 3. Health Endpoint

```bash
# Check JSON health response
curl -s http://54.XX.XXX.XXX:8080/health | python3 -m json.tool
```

Expected:
```json
{
  "app": "demo-app",
  "status": "ok",
  "version": "1.0.0"
}
```

### 4. Nginx Status

```bash
# Check service is active
ansible webservers -m shell -a "systemctl is-active nginx"
```

Expected: `active` on all hosts.

### 5. Ansible Lint

```bash
ansible-lint playbooks/provision.yml
```

Expected: Zero warnings.

### 6. Idempotency (Second Run)

```bash
# Run provision again — should show zero changes
ansible-playbook -i inventory/aws_ec2.yml playbooks/provision.yml
```

Expected in PLAY RECAP:
```
changed=0
```

This demonstrates true idempotency — the system is already in the desired state.

---

## Selective Execution

Use `--tags` to run only specific sections:

| Tag | Tasks | Use Case |
|---|---|---|
| `packages` | Install system packages | Update dependencies only |
| `nginx` | Install and configure nginx | Modify web server config |
| `app` | Deploy application files | Update app content without full reprovisioning |
| `verify` | Run health checks | Verify health without changes |
| `always` | Runs regardless of tags | Used for critical checks |

### Examples

```bash
# Update only application files (fast, safe for frequent deployments)
ansible-playbook playbooks/deploy.yml

# Reconfigure nginx only
ansible-playbook playbooks/provision.yml --tags nginx

# Run health checks (no changes)
ansible-playbook playbooks/verify.yml

# Everything except verification
ansible-playbook playbooks/provision.yml --skip-tags verify
```

---

## Customization

### Change Application Version

```bash
ansible-playbook playbooks/deploy.yml -e "app_version=2.0.0"
```

### Change Application Port

Edit `group_vars/webservers.yml`:

```yaml
app_port: 9090
```

Then run `provision.yml` to update nginx configuration.

### Scale to N Nodes

Edit `terraform/terraform.tfvars`:

```hcl
managed_node_count = 5
```

Then `terraform apply` and re-run `provision.yml`.

### Use Different AWS Region

Edit `terraform/variables.tf`:

```hcl
default = "us-west-2"
```

Then `terraform apply`.

---

## AWS Resource Tags

All AWS resources are tagged with platform-engineering governance tags for compliance and cost allocation:

| Tag | Value | Purpose |
|---|---|---|
| `fo:owner` | `sabatino` | Cost center and accountability |
| `fo:platform` | `platform-engineering` | Platform team ownership |
| `fo:environment` | `sandbox` | Environment classification |
| `fo:purpose` | `poc-runbooks` | Business purpose and lifecycle |
| `Project` | `aws-provisioning-lab` | Human-readable project name |
| `ManagedBy` | `terraform` | Infrastructure-as-code source |

These tags automatically filter the dynamic inventory, so only instances belonging to this project are discovered by Ansible.

---

## Teardown

### Destroy AWS Resources

```bash
cd terraform
terraform destroy

# Approve the destruction
```

**Warning:** This terminates all EC2 instances and deletes the security group. Backups are NOT created.

### Clean Up Local Cache

```bash
rm -rf /tmp/.aws_ec2_cache
```

The dynamic inventory cache may still hold stale instance references after `terraform destroy`. Clearing it prevents future connectivity attempts to non-existent hosts.

---

## CV Alignment

This project demonstrates the following career claims:

| CV Claim | Demonstrated By |
|---|---|
| **Infrastructure automation** | Ansible orchestrates EC2 lifecycle, security groups, and full stack provisioning |
| **Dynamic inventory** | AWS EC2 plugin discovers hosts at runtime without static files |
| **Cloud API integration** | Terraform + Ansible directly call AWS APIs via `amazon.aws` collection |
| **Reusable automation frameworks** | Roles with defaults, handlers, tags, and proper task organization |
| **Ansible Tower / AAP readiness** | Playbook structure mirrors AAP Job Templates; scalable to 100+ nodes |
| **Provisioning expertise** | EC2 creation, security groups, package installation, service configuration |
| **Idempotent design** | Full playbook re-runs produce `changed=0` once deployed |
| **Platform engineering** | Tags, governance policies, multi-environment support |

---

## Support & Feedback

For issues, questions, or improvements:

1. Check logs: `cat /tmp/ansible_<hostname>.log`
2. Run in debug mode: `ansible-playbook ... -vvv`
3. Verify inventory: `ansible-inventory -i inventory/aws_ec2.yml --list`
4. Check AWS tags: `aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,Tags]' --filters 'Name=tag:fo:owner,Values=sabatino'`

---

**Last Updated:** 2026-04-23
**Author:** Marcos Sabatino
**License:** MIT
