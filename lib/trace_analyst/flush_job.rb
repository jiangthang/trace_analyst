# frozen_string_literal: true

require 'active_job'

module TraceAnalyst
  class FlushJob < ActiveJob::Base
    queue_as :default

    def perform
      Flush.run!
    end
  end
end
