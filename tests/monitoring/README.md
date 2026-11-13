# Monitoring regression checks

Requires Python/PyYAML, Go, and promtool (validated with Prometheus 3.11.0).
Run from the repository root:

```sh
python3 tests/monitoring/check-rules.py /tmp/home-ops-alert-rules
go run tests/monitoring/check-pushover.go /tmp/home-ops-alert-rules/pushover-template.txt
cd /tmp/home-ops-alert-rules
promtool check rules rules.yaml
promtool test rules prometheus-rules.test.yaml
```

The rule tests cover recovered and newly failed CronJobs, a CronJob with no
successful history, standalone failed Jobs, recoverable retries, mount-doctor
recovery, and the current Supabase StatefulSet/backup presence checks. They
extract production expressions rather than testing copied expressions.

The notification test renders the production message with long Unicode labels
and summaries, including a group of 1,000 alerts, and enforces Pushover's 1,024
character limit. It does not send notifications.
