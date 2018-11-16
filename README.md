# SidekiqFlow

Workflow runner, inspired by [gush](https://github.com/chaps-io/gush) gem.


## Description

Parallel runner for DAG (directed acyclic graph) defined workflows.
It uses Sidekiq for scheduling and executing jobs and Redis as workflows storage.


## Storage overview and enhancements

Currently Redis is used as storage backend.
Writing and reading a single workflow is very fast, but it's slow when it comes to read multiple workflows with associated data.
E.g. if we want to read 1000 workflows with their data we need to perform:
* 1 operation to get all workflow keys,
* 1000 operations (1 per workflow) to get single workflow's data.

Above problem has an impact on 'index' page where we display workflows with associated 'start_date' and 'end_date'.
To avoid this performance problem we store some additional info on workflow's key itself.
So we have keys of `workflows.2_1541773257_1542384941` structure, where:
* `2` - workflow 'id'
* `1541773257` - workflow 'start_date'
* `1542384941` - workflow 'end_date'

This way we perform only 1 call to get all workflow keys.

It's reasonable to replace current Redis storage with sth different in the future.
