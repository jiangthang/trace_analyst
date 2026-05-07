# trace_analyst

Structured production debug capture for Rails apps: explicit `TraceAnalyst.for(...).log(...)` breadcrumbs, Redis streams, batched gzipped NDJSON uploads to S3, and a local CLI for investigation workflows (aligned with Cursor skills).

## Installation

Add to your Gemfile:

```ruby
gem 'trace_analyst'
```

Then:

```bash
bundle install
bin/rails generate trace_analyst:install --subject-key shop_id
```

Configure AWS and Redis in `config/initializers/trace_analyst.rb`. Schedule `TraceAnalyst::FlushJob` (e.g. Sidekiq cron every minute).

## Usage

```ruby
TraceAnalyst.configure do |c|
  c.subject_key = :shop_id
  c.redis = proc { |&blk| Sidekiq.redis(&blk) }
  c.storage = TraceAnalyst::Storage::S3Adapter.new(bucket: '...', region: '...', credentials: Aws::Credentials.new(...))
  c.activation = TraceAnalyst::Activation::RedisTtl.new(ttl: 86_400)
end

TraceAnalyst.for(shop_id: 1138, investigation: 'inv_2026_05_07_rates')
             .log(label: 'rate_calc.input', data: { sku: 'AB-12', qty: 3 })
```

CLI:

```bash
bundle exec trace-analyst open inv_2026_05_07_rates --shop 1138 --topic "rates"
bundle exec trace-analyst index tmp/trace-investigations/<slug>/round-1.ndjson
```

See generated docs under `docs/trace-investigations/README.md` after install.

## License

MIT
