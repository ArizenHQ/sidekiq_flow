# SidekiqFlow

Workflow runner, inspired by [gush](https://github.com/chaps-io/gush) gem.


## Description

Parallel runner for DAG (directed acyclic graph) defined workflows.
It uses Sidekiq for scheduling and executing jobs and Redis as workflows storage.


## Workflow definition

Each workflow's class needs to implement `initial_tasks` method, which defines tasks and their relations.
Example:
```ruby
class TestWorkflow < SidekiqFlow::Workflow
  def self.initial_tasks
    [
      TestTask1.new(children: ['TestTask2', 'TestTask3']),
      TestTask2.new(children: ['TestTask4']),
      TestTask3.new(children: ['TestTask4']),
      TestTask4.new
    ]
  end
end
```
The graphical presentation of this workflow is:
![Workflow](/images/workflow_example.png)

## Mechanism

The above workflow can be started by:
```ruby
SidekiqFlow::Client.start_workflow(TestWorkflow.new(id: 123)) # pass identifier
```
By starting the workflow, we understand starting all tasks having no parents (`TestTask1` in this case). There is an exception of this rule, but it will be described later. Executing of the children tasks depends on parents execution result. By default a child is executed, when all of his parents succeeded (other rules will be described later). So in our example workflow `TestTask2` and `TestTask3` are executed just after `TestTask1` success.

## Task states

* `pending` - the initial state, task is not yet executed
* `enqueued` - task is scheduled for execution (is pushed to redis queue) or Sidekiq worker is currently processing the job
* `succeeded` - task finished successfully
* `failed` - task failed
* `skipped` - 'soft fail', it's indented to handle 'controlled' failures
* `awaiting_retry` - task is awaiting for retrying after failure


## Task attributes
`Task` instance could be intiatialized with following attributes:

* `start_date`
  * determines the start time of the task
  * if nothing passed -  a task starts immediately
  * if `nil` is explicity passed - the task won't be started (see 'Externally triggered tasks' section)

* `end_date`
  * task won't be executed after this time
  * by default there is no limit

* `loop_interval`
  * this option is related with recurring tasks (see 'Recurring tasks' section)

* `retries`
  * how many times task will be retried after unexpected failure
  * this is handled by Sidekiq's retries mechanism under the hood
  * by default is 0

* `queue`
  * determines the redis queque used by given task
  * `default` queue is used when not specified

* `trigger_rule`
  * defines parents conditions that need to be met to trigger the child
  * default is `['all_succeeded', {}]` - which means that all parents have to finish with success
  * other available rule: `['number_succeeded', {number: 2}]` - at least 2 parents succedeed


## Externally triggered tasks
When a task is defined with `start_date` equals `nil` (`TestTask.new(start_date: nil`), this means the task needs to be triggered from outside the workflow. Even `trigger_rule` condition is met, this task won't be started. To start this task we need to do this explicity:
```ruby
SidekiqFlow::Client.start_task(123, 'TestTask') # where 123 is the workflow id

```


## Recurring tasks

'Recurring' task can be repeated many times. It has `loop_interval` attribute which tells us how often it's performed.
We can also pass `end_date` attribute to specify the time when repeating is stopped.
E.g.
```ruby
TestTask.new(loop_interval: 10, end_date: (Time.now + 1.day).to_i) # 10s interval, 1 day duration
```


## Task return values

* when task completes without any error raised -  it becomes 'succeeded'
* when task raises `SidekiqFlow::SkipTask` - it becomes 'skipped'
* when task raises `SidekiqFlow::RepeatTask` - it becomes 'enqueued' for performing after specified `loop_interval` attr ('recurrring' tasks)
* when task raises `SidekiqFlow::TryLater` with `delay_time` param - it becomes 'enqueued' for performing again (one time repeat)
E.g.
```ruby
SidekiqFlow::TryLater.new(delay_time: 15.minutes) # task will be repeated once after 15 minutes
```

## Task implementation

As tasks are Sidekiq jobs, all you need to implement is `perform` method. E.g.
```ruby
class TestTask < SidekiqFlow::Task
  def perform
    # implement me!
  end
end
```
You have access to all task attributes inside `SidekiqFlow::Task` instance.


## Client

There are couple of helpful CLI commands:

* `SidekiqFlow::Client.start_workflow(TestWorkflow.new(id: 123))`
  * starting workflow
* `SidekiqFlow::Client.start_task(123, 'TestTask')`
  * starting task
* `SidekiqFlow::Client.restart_task(123, 'TestTask')`
  * restarting task
  * the task and its children are 'cleared' (status is set to 'pending') and the task is started then
  * 'enqueued' and 'awaiting_retry' can't be restarted as they're in progress
* `SidekiqFlow::Client.restart_task(123, 'TestTask')`
* `SidekiqFlow::Client.clear_task(123, 'TestTask')`
  * set task's status to 'pending'


## workflow `succeeded?`
Workflow expose `succeeded?` method which can be implemented to determine whether workflow finished with success (`false` by default)


## task `auto_succeed?`
This method is intended to describe condition when task is already done.
It's helpful when task finished his job and we retry it. When met task won't be performed.


## Examples

### Example 1

Let's analyse example below:
```ruby
class TestWorkflow < SidekiqFlow::Workflow
  def self.initial_tasks
    [
      TestTask1.new(children: ['TestTask2', 'TestTask3']),
      TestTask2.new(children: ['TestTask4']),
      TestTask3.new(children: ['TestTask4'], loop_interval: 10, end_date: (Time.now + 1.minute).to_i),
      TestTask4.new(retries: 1)
    ]
  end
end
```
1. Workflow starts - `SidekiqFlow::Client.start_workflow(TestWorkflow.new(id: 123))`
2. `TestTask1` starts
3. `TestTask1` ends with success
4. `TestTask2` and `TestTask3` start in parralel (as their parent succeeded)
5. `TestTask2` ends with success
6. `TestTask3` throws `SidekiqFlow::RepeatTask` - it's scheduled for next try in 10s
7. `TestTask3` ends with success (2-nd try)
8. `TestTask4` starts as both its parent succeeded
9. `TestTask4` raises unexpected error - it's scheduled for retry
10. `TestTask4` raises unexpected error when retrying - no more retries, task failed

### Example 2

Let's analyse example below:
```ruby
class TestWorkflow < SidekiqFlow::Workflow
  def self.initial_tasks
    [
      TestTask1.new(children: ['TestTask2', 'TestTask3'], start_date: nil),
      TestTask2.new(children: ['TestTask4']),
      TestTask3.new(children: ['TestTask4'], loop_interval: 10, start_date: nil, end_date: (Time.now + 1.minute).to_i),
      TestTask4.new(retries: 1)
    ]
  end
end
```
1. Workflow starts - `SidekiqFlow::Client.start_workflow(TestWorkflow.new(id: 123))`
2. `TestTask1` can't be started, as it's externally triggered task (`start_date` is `nil`)
3. Whole workflow is 'on hold' - `TestTask1` is pending and we have no other tasks to start
4. `TestTask1` is started externally - `SidekiqFlow::Client.start_task(123, 'TestTask1')`
5. `TestTask1` ends with success
6. `TestTask2` starts
7. `TestTask2` ends with success
8. `TestTask3` can't be started, bc it's also externally triggered task
9. `TestTask3` is started externally - `SidekiqFlow::Client.start_task(123, 'TestTask3')`
10. `TestTask3` ends with success
11. `TestTask4` starts as both its parent succeeded
12. `TestTask4` raises `SidekiqFlow::SkipTask` - task is 'skipped' (no repeats, no retries)


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
