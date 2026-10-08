# Microsoft SCOM Collection for Ansible

[![CI](https://github.com/ansible-collections/microsoft.scom/workflows/CI/badge.svg?event=push)](https://github.com/ansible-collections/microsoft.scom/actions)
[![Codecov](https://img.shields.io/codecov/c/github/ansible-collections/microsoft.scom)](https://codecov.io/gh/ansible-collections/microsoft.scom)

This collection provides Ansible modules and plugins to manage Microsoft System Center Operations Manager (SCOM) infrastructure through automation.

## Description

The `microsoft.scom` collection provides a comprehensive set of Ansible modules for automating Microsoft System Center Operations Manager (SCOM) environments on Windows.
It is designed for IT operations teams and infrastructure engineers who need to manage SCOM objects — such as alerts, maintenance schedules, monitor overrides, management packs, notification pipelines, and Run As accounts — through repeatable, idempotent Ansible playbooks.

The collection also includes an Event Driven Ansible (EDA) source plugin that streams real-time SCOM alerts into EDA rulebooks, enabling automated remediation workflows triggered by live monitoring events.

By leveraging this collection, teams can eliminate manual SCOM console workflows, enforce consistent monitoring configuration across their management groups, and integrate SCOM operations into broader infrastructure-as-code pipelines.

## Requirements

- **Ansible**: `>= 2.16.0`
- **Python**: `>= 3.12`
- **Target OS**: Windows with Microsoft SCOM installed and the SCOM PowerShell module available
- **WinRM**: Windows Remote Management (WinRM) must be configured and reachable on the target host
- **Python package** (control node): `pywinrm` — required for WinRM connectivity

## Installation

### Installing the collection

Install this collection with the Ansible Galaxy command-line tool:

```bash
ansible-galaxy collection install microsoft.scom
```

### Installing from a requirements file

You can include this collection in a `requirements.yml` file and install it with `ansible-galaxy collection install -r requirements.yml`:

```yaml
collections:
  - name: microsoft.scom
```

### Installing a specific version

Use the following syntax to install version `2.0.0`:

```bash
ansible-galaxy collection install microsoft.scom:==2.0.0
```

See [using Ansible collections](https://docs.ansible.com/ansible/devel/user_guide/collections_using.html) for more details.

### Upgrading the collection

To upgrade the collection to the latest available version, run the following command:

```bash
ansible-galaxy collection install microsoft.scom --upgrade
```

### Using the EDA source plugin on AAP/EDA

To use the `scom_plugin` EDA source plugin in an Ansible Automation Platform Event-Driven Ansible environment, the plugin must be available inside the EDA Decision Environment.

Build a custom EDA Decision Environment using the provided `Containerfile`:

```bash
podman build -t scom-eda-de:2.0.0 .
```

Push the image to your container registry, then create a Decision Environment in EDA using that image.
In EDA Rulebook Activations, create a rulebook activation with the created Decision Environment and use the rulebook at `extensions/eda/rulebooks/scom-rulebook.yml`.

## Use Cases

The `microsoft.scom` collection is designed to automate the most common day-to-day operational tasks performed by SCOM administrators — from resolving alerts and scheduling maintenance windows to managing notification pipelines and reacting to live monitoring events with EDA.

### 1. Alert Management

Acknowledge and resolve SCOM alerts programmatically to integrate with incident management workflows.

```yaml
- name: Resolve a SCOM alert
  hosts: scom_management_server
  tasks:
    - name: Resolve all critical alerts for a specific source
      microsoft.scom.alert:
        resolution_state: resolved
        criteria: "Name = 'Heartbeat Failure' AND ResolutionState = 0"
```

---

### 2. Maintenance Schedule Management

Place SCOM-monitored resources into maintenance mode during scheduled downtime to suppress false alerts during patching or planned outages.

```yaml
- name: Schedule maintenance for a server group
  hosts: scom_management_server
  tasks:
    - name: Create a recurring nightly maintenance schedule
      microsoft.scom.maintenance_schedule:
        name: "NightlyPatchWindow"
        display_name: "Nightly Patch Window"
        monitored_object: "web-server-01.contoso.com"
        duration_minutes: 120
        recurring: true
        recurrence_type: daily
        start_time: "2026-01-01T02:00:00"
        state: present
```

---

### 3. Monitor Override Management

Suppress noisy monitors or tune thresholds for specific objects without modifying the management pack directly.

```yaml
- name: Suppress a flapping monitor for a known issue
  hosts: scom_management_server
  tasks:
    - name: Disable CPU utilisation monitor for the DB server during migration
      microsoft.scom.monitor_override:
        monitor_name: "Microsoft.Windows.Server.2019.LogicalDisk.FreeSpaceMonitor"
        context: "db-server-01.contoso.com"
        parameter: Enabled
        value: "false"
        management_pack_name: "Overrides.Migration"
        state: present
```

---

### 4. Notification Pipeline Configuration

Set up the full SCOM notification pipeline — channels, subscribers, and subscriptions — as code so it can be version-controlled, reviewed, and reproduced across management groups.

```yaml
- name: Configure SCOM notification pipeline
  hosts: scom_management_server
  tasks:
    - name: Create an SMTP notification channel
      microsoft.scom.notification_channel:
        name: "OpsEmailChannel"
        display_name: "Operations Email Channel"
        channel_type: email
        smtp_server: "smtp.contoso.com"
        from_address: "scom-alerts@contoso.com"
        state: present

    - name: Create a notification subscriber
      microsoft.scom.notification_subscriber:
        name: "OpsTeam"
        addresses:
          - address: "ops-team@contoso.com"
            channel: "OpsEmailChannel"
        state: present

    - name: Create a notification subscription for critical alerts
      microsoft.scom.notification_subscription:
        name: "CriticalAlertsToOps"
        display_name: "Critical Alerts to Operations"
        channels:
          - "OpsEmailChannel"
        subscribers:
          - "OpsTeam"
        enabled: true
        criteria:
          filters:
            - property: severity
              operator: equal
              value: critical
        state: present
```

---

### 5. Event-Driven Remediation with EDA

Stream live SCOM alerts into Event-Driven Ansible rulebooks to trigger automated remediation playbooks the moment an alert fires, without polling.

```yaml
# extensions/eda/rulebooks/scom-rulebook.yml
- name: React to SCOM critical alerts
  hosts: all
  sources:
    - microsoft.scom.scom_plugin:
        host: "scom-server.contoso.com"
        username: "{{ scom_user }}"
        password: "{{ scom_password }}"
        severity_filter:
          - critical

  rules:
    - name: Restart service on heartbeat failure
      condition: event.alert.name == "Heartbeat Failure"
      action:
        run_playbook:
          name: remediate_heartbeat.yml
```

---

## Testing

All modules in this collection are validated through automated integration tests that run against a live Microsoft SCOM environment.

### Ansible Versions Tested

| Ansible Version | Python Version |
|---|---|
| `stable-2.16` | 3.12 |
| `stable-2.17` | 3.12 |
| `stable-2.18` | 3.12 |
| `stable-2.19` | 3.12 |
| `devel` | 3.13 |

### Integration Test Coverage

Each module has a dedicated integration test target under `tests/integration/targets/`.

### Static Analysis

All playbooks and module documentation are linted with `ansible-lint`.

### Known Limitations and Workarounds

- **Criteria updates**: The `notification_subscription` module does not support updating `criteria` or `channels` on an existing subscription in place. Remove the subscription with `state=absent` and recreate it to change these fields.
- **Management pack sealing**: The `management_pack` module can import and delete management packs but cannot seal them. Sealed management packs must be created through the SCOM authoring tools.
- **Maintenance schedule context**: The `maintenance_schedule` module requires the monitored object to already exist and be discovered in SCOM before it can be placed into maintenance mode.

## Contributing

The content of this collection is made by people like you — a community of individuals collaborating on making the world better through developing automation software.

We are actively accepting new contributors and all types of contributions are very welcome.

Don't know how to start? Refer to the [Ansible community guide](https://docs.ansible.com/ansible/devel/community/index.html)!

Want to submit code changes? Take a look at the [Quick-start development guide](https://docs.ansible.com/ansible/devel/community/create_pr_quick_start.html).

We also use the following guidelines:

- [Collection review checklist](https://docs.ansible.com/ansible/devel/community/collection_contributors/collection_reviewing.html)
- [Ansible development guide](https://docs.ansible.com/ansible/devel/dev_guide/index.html)
- [Ansible collection development guide](https://docs.ansible.com/ansible/devel/dev_guide/developing_collections.html#contributing-to-collections)

### Communication

- Join the Ansible forum:
  - [Get Help](https://forum.ansible.com/c/help/6): get help or help others. Please add the `microsoft` and `scom` tags when starting new discussions.
  - [Posts tagged with 'scom'](https://forum.ansible.com/tag/scom): subscribe to participate in SCOM-related conversations.
  - [Social Spaces](https://forum.ansible.com/c/chat/4): gather and interact with fellow enthusiasts.
  - [News & Announcements](https://forum.ansible.com/c/news/5): track project-wide announcements including social events. The [Bullhorn newsletter](https://docs.ansible.com/ansible/devel/community/communication.html#the-bullhorn), which is used to announce releases and important changes, can also be found here.

For more information about communication, see the [Ansible communication guide](https://docs.ansible.com/ansible/devel/community/communication.html).

### Code of Conduct

We follow the [Ansible Code of Conduct](https://docs.ansible.com/ansible/devel/community/code_of_conduct.html) in all our interactions within this project.

If you encounter abusive behavior, please refer to the [policy violations](https://docs.ansible.com/ansible/devel/community/code_of_conduct.html#policy-violations) section of the Code for information on how to raise a complaint.

### Governance

The process of decision making in this collection is based on discussing and finding consensus among participants.
Every voice is important. If you have something on your mind, create an issue or dedicated discussion and let's discuss it!

## Support

As Red Hat Ansible [Certified Content](https://catalog.redhat.com/software/search?target_platforms=Red%20Hat%20Ansible%20Automation%20Platform), this collection is entitled to support through [Ansible Automation Platform (AAP)](https://www.redhat.com/en/technologies/management/ansible) using the **Create issue** button on the top right corner of the collection page on Automation Hub.

### Red Hat-managed collections

This collection is maintained by the Red Hat Ansible Ecosystem Engineering team [@eco-ansible-content](https://github.com/eco-ansible-content). 
You can reach the team at [eco-ansible-content@redhat.com](mailto:eco-ansible-content@redhat.com)

### Third-party vendor collections

If a support case cannot be opened with Red Hat and the collection has been obtained either from [Galaxy](https://galaxy.ansible.com/ui/) or [GitHub](https://github.com/ansible-collections/microsoft.scom), there may be community help available on the [Ansible Forum](https://forum.ansible.com/).

## Release Notes and Roadmap

See the [changelog](https://github.com/ansible-collections/microsoft.scom/tree/main/CHANGELOG.rst) for the full release history.

For information on the support timeline for Ansible Automation Platform, see the [Red Hat Ansible Automation Platform Life Cycle](https://access.redhat.com/support/policy/updates/ansible-automation-platform) page.

## Related Information

- [Microsoft SCOM documentation](https://learn.microsoft.com/en-us/system-center/scom/)
- [Ansible user guide](https://docs.ansible.com/ansible/devel/user_guide/index.html)
- [Ansible collections requirements](https://docs.ansible.com/ansible/devel/community/collection_contributors/collection_requirements.html)
- [Important announcements for maintainers](https://github.com/ansible-collections/news-for-maintainers)

## License Information

GNU General Public License v3.0 or later.

See [LICENSE](https://www.gnu.org/licenses/gpl-3.0.txt) to see the full text.
