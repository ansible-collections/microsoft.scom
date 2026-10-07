===============================================
Microsoft SCOM Ansible Collection Release Notes
===============================================

.. contents:: Topics

v2.0.0
======

Release Summary
---------------

11 New modules for the Microsoft SCOM Ansible Collection

Major Changes
-------------

- Introduce the Microsoft SCOM Ansible Collection — a centralised automation framework for Microsoft System Center Operations Manager. All modules share a unified connection and credential validation layer, ensuring consistent behaviour and a predictable experience across every SCOM operation.

New Modules
-----------

- microsoft.scom.alert - Manage the state of a SCOM alert.
- microsoft.scom.alert_info - Retrieve information about SCOM alerts.
- microsoft.scom.group - Manage SCOM groups with explicit membership.
- microsoft.scom.group_info - Retrieve information about SCOM groups.
- microsoft.scom.maintenance_schedule - Manage SCOM maintenance schedules.
- microsoft.scom.maintenance_schedule_info - Retrieve information about SCOM maintenance schedules.
- microsoft.scom.management_pack - Import or remove SCOM management packs.
- microsoft.scom.management_pack_info - Retrieve information about installed SCOM management packs.
- microsoft.scom.monitor_override - Manage SCOM monitor overrides.
- microsoft.scom.monitor_override_info - Retrieve SCOM monitors and their overrides by Monitor ID, Display Name, or Target Class.
- microsoft.scom.notification_channel - Manage SCOM notification channels.
- microsoft.scom.notification_channel_info - Retrieve information about SCOM notification channels.
- microsoft.scom.notification_subscriber - Manage SCOM notification subscribers.
- microsoft.scom.notification_subscriber_info - Retrieve information about SCOM notification subscribers.
- microsoft.scom.notification_subscription - Manage SCOM notification subscriptions.
- microsoft.scom.notification_subscription_info - Retrieve information about SCOM notification subscriptions.
- microsoft.scom.pending_agent_request - Approve or Reject SCOM manual agent management requests.
- microsoft.scom.pending_agent_request_info - Retrieve information about SCOM pending agent management requests.
- microsoft.scom.run_as_account - Manage SCOM Run As Accounts.
- microsoft.scom.run_as_account_info - Retrieve information about SCOM RunAs accounts.
- microsoft.scom.run_as_distribution - Manage the credential distribution policy of SCOM RunAs account.
- microsoft.scom.run_as_distribution_info - Retrieve the credential distribution policy of SCOM RunAs accounts.

v1.0.1
======

Minor Changes
-------------

- prepare_release.yml - added proper task names, FQCN usage, and pipefail safety for shell commands.
- scom_plugin - added HTTP status code constants for better code maintainability.
- scom_plugin - improved code quality and linting compliance with type annotations, proper error handling, and modern Python syntax.
- scom_plugin - improved logging configuration for CLI testing.

v1.0.0
======

Release Summary
---------------

First release of the microsoft.scom collection
