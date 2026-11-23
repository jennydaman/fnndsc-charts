- rename secret
- rename volume (in case where pfcon is disabled)
- replace bitnami/postgresql with Crunchy PGO
- substitute rabbitmq with dragonflydb
- SOLVED migrate job currently fails because it runs before the "chris" user + database are created.
       then it retries itself. (1) disable retries (2) delay after database migrations


- TODO create incluster CR
- TODO consider moving all config values to top-level
- TODO add hook for oc delete jobs -l app.kubernetes.io/instance=chris -l app.kubernetes.io/managed-by=Helm


