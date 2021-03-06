# Forklift

An application for reading data off kafka topics, batching it up and sending it to Presto. To improve both write and read performance data is written to a temporary table as raw JSON and then migrated to the main table in ORC format.  The process of [compaction](#compaction) is done on a configurable cadence.


## To run the tests

  * Run `mix test` to run the tests a single time
  * Run `mix test.watch` to re-run the tests when a file changes
  * Run `mix test.watch --stale` to only rerun the tests for modules that have changes
  * Run `mix test.integration` to run the integration tests

## To run inside a container(from the root directory):
  * `docker build . -t <image_name:tag>`

## Running Locally

You can use [Divo](https://hexdocs.pm/divo/) to stand up the external dependencies locally using docker and docker-compose.

```bash
MIX_ENV=integration mix docker.start
MIX_ENV=integration iex -S mix
```

## Jobs
### Compaction
Compaction is a process that runs that consolidates the data that is being stored in Presto.  This process greatly improves read performance.
```elixir
# Deactive Compaction
Forklift.Quantum.Scheduler.deactivate_job(:compactor)

# Active Compaction
Forklift.Quantum.Scheduler.activate_job(:compactor)
```


## License

Released under [Apache 2 license](https://github.com/smartcitiesdata/smartcitiesdata/blob/master/LICENSE).
