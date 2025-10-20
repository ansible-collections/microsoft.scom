# -*- coding: utf-8 -*-
#
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

DOCUMENTATION = r"""
module: scom_plugin
short_description: Event Driven Ansible source for System Center Operations Manager (SCOM) Alerts.
description:
  - Poll the Microsoft System Center Operations Manager Server API for any new alerts, using them as a source for Event Driven Ansible.
options:
  scom_server:
    description:
      - SCOM Server IP or FQDN.
    required: true
  username:
    description:
      - SCOM Server Login username.
    required: true
  password:
    description:
      - SCOM Server Login password.
    required: true
  criteria:
    description:
      - This is a property of an alert in SCOM that indicates its current state in the alert lifecycle.
      - The criteria (ResolutionState = '') is a filter that describes the alert state.
      - New (ResolutionState = '0') The alert has been generated and has not been acted upon.
      - Resolved (ResolutionState = '1') The underlying issue has been fixed and the alert is marked as resolved.
    required: true
  interval:
    description:
      - Time between http API queries to fetch SCOM Server alerts.
    required: false
    default: 5
  ntlm_token_refresh:
    description:
      - Time between requests for a brand new token for SCOM Server API.
    required: false
    default: 21600
author:
  - Microsoft SCOM Collection Contributors (@ansible-collections)
"""

EXAMPLES = r"""
---
- name: Listen for events on Microsoft SCOM Alerts
  hosts: localhost
  sources:
    - microsoft.scom.scom_plugin:
        scom_server: 10.55.55.100
        username: ECO\Administrator
        password: Password1!
        criteria: "(ResolutionState = '0')"
        interval: 10
        ntlm_token_refresh: 300
  rules:
    - name: New record created
      condition: event.id is defined
      action:
        debug:
          msg: "New SCOM Alert received! Alert Name: {{ event | default('N/A') }}"
"""
