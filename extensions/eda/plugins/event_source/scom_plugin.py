# Copyright: (c), Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)


"""Event Driven Ansible source plugin for System Center Operations Manager (SCOM) Alerts.

This module allows for polling the SCOM Server API to retrieve new alert events
for use as sources in Event Driven Ansible automations.
"""


import asyncio
import base64
from datetime import datetime, timezone, timedelta
import logging
from typing import Any
import urllib
import httpx
from httpx_ntlm import HttpNtlmAuth


# HTTP Status Codes
HTTP_OK = 200
HTTP_UNAUTHORIZED = 401
HTTP_SESSION_TIMEOUT = 440

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


async def main(  # pylint: disable=R0914,R0915
    queue: asyncio.Queue[Any],
    args: dict[str, Any],
) -> None:
    """Poll SCOM server for alert events and queue them."""
    scom_server = args.get("scom_server")
    username = args.get("username")
    password = args.get("password")
    criteria = args.get("criteria")
    interval = int(args.get("interval", 5))  # fetch interval
    ntlm_token_refresh = int(args.get("ntlm_token_refresh", 21600))

    logger = logging.getLogger(__name__)
    logger.setLevel(logging.INFO)

    # start of execution
    exe_start = datetime.now(timezone.utc)
    root_url = f"https://{scom_server}/OperationsManager"
    login_url = root_url + "/authenticate"

    # verify=False is used for self-signed certificates
    async with httpx.AsyncClient(verify=False, timeout=120.0) as client:  # noqa: S501
        auth_body = base64.b64encode(
            (f"(Network):{username}:{password}").encode("utf-8")).decode("utf-8")  # noqa: UP012
        client.auth = HttpNtlmAuth(username, password)

        printed_alerts = set()

        # initial token is expired/invalid so it will grab a new one on first run.

        reauth = True
        auth_obj = {}
        token_exptime = datetime.now(timezone.utc)
        while True:
            # start of every fetch loop

            # authentication
            if reauth is True:

                client.headers = {"Content-Type": "application/json; charset=utf-8"}

                # login
                logger.info("Fetching for a brand new token")
                response = await client.post(login_url, data='"' + auth_body + '"')
                token_exptime = datetime.now(timezone.utc) + timedelta(seconds=ntlm_token_refresh)

                if response.status_code != HTTP_OK:
                    raise_message = (
                        f"Failure in Authenticating: {response.status_code} | "
                        f"Headers: {response.headers} | Error Response: {response.text}"
                    )
                    raise RuntimeError(raise_message)

                auth_obj = {
                    "csrf_token": urllib.parse.unquote(response.cookies["SCOM-CSRF-TOKEN"]),
                    "session_id": "SCOMSessionId=" + response.cookies["SCOMSessionId"],
                }

            body = {
                "classId": None,
                "objectIds": {},
                "criteria": criteria,
                "displayColumns": [
                    "id",
                    "severity",
                    "monitoringobjectdisplayname",
                    "monitoringobjectpath",
                    "name",
                    "age",
                    "description",
                    "owner",
                    "timeadded",
                ],
            }
            client.headers = {
                "SCOM-CSRF-TOKEN" : auth_obj["csrf_token"],
                "Cookie" : auth_obj["session_id"],
            }

            # get alert data
            logger.info("Fetching for new alerts")
            resp = await client.post(f"{root_url}/data/alert", data=body)
            if resp.status_code == HTTP_OK:
                reauth = False
                alerts = resp.json()
                for record in alerts["rows"]:

                    if ((datetime.fromisoformat(record["timeadded"][:-9] + "-00:00") > exe_start)
                            and (record["id"] not in printed_alerts)):
                        printed_alerts.add(record["id"])
                        await queue.put(record)

            elif resp.status_code in [HTTP_SESSION_TIMEOUT, HTTP_UNAUTHORIZED]:
                reauth = True
            else:
                logger.error("Error %s", resp.status_code)

            if reauth is False:
                logger.info("Sleeping for %d seconds until next fetching of alerts", interval)
                await asyncio.sleep(interval)

            if datetime.now(timezone.utc) > token_exptime:
                reauth = True

# this is only called when testing plugin directly, without ansible-rulebook
if __name__ == "__main__":
    test_logger = logging.getLogger(__name__)
    test_logger.setLevel(logging.INFO)

    class MockQueue:  # pylint: disable=too-few-public-methods
        """Mock queue for testing the plugin without ansible-rulebook."""

        test_logger.info("Waiting for events...")

        async def put(self, event: dict[str, Any]) -> None:
            """Mock method to print received events."""
            test_logger.info("New event received: %s", event)

    test_args = {
        "scom_server": "",
        "username": r"",
        "password": r"",
        "criteria": "(ResolutionState = '0')",
        "interval" : 5,
        "ntlm_token_refresh": 30,
    }
    asyncio.run(main(MockQueue(), test_args))
