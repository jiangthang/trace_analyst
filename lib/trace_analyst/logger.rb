# frozen_string_literal: true

require 'json'
require 'socket'

module TraceAnalyst
  class Logger
    def initialize(subject_id:, investigation:)
      @subject_id = subject_id
      @investigation = investigation
      @subject_key = TraceAnalyst.configuration.subject_key.to_s
    end

    # Returns Redis stream entry id (or nil when gated off).
    def log(label:, data: {}, allow_pii: [])
      return nil unless capture_enabled?

      redacted, redactions = TraceAnalyst::Redactor.redact(data, allow_pii: allow_pii)
      record_redactions(redactions) if redactions.any?

      payload = build_payload(
        label: label,
        data: redacted,
        redactions: redactions,
        allow_pii: allow_pii.map(&:to_s)
      )

      TraceAnalyst::Stream.xadd(subject_id: @subject_id, payload: JSON.generate(payload))
    end

    private

    def capture_enabled?
      TraceAnalyst.configuration.activation.enabled?(@subject_id)
    end

    def build_payload(label:, data:, redactions:, allow_pii:)
      sk = @subject_key
      {
        'schema_version' => 1,
        sk => @subject_id,
        'investigation' => @investigation,
        'label' => label,
        'request_id' => Thread.current[:request_id],
        'host' => Socket.gethostname,
        'data' => data,
        'redactions' => redactions,
        'allow_pii' => allow_pii
      }
    end

    def record_redactions(redactions)
      cb = TraceAnalyst.configuration.on_redactions
      if cb
        cb.call(subject_id: @subject_id, investigation: @investigation, redactions: redactions)
      elsif defined?(Bugsnag)
        Bugsnag.leave_breadcrumb(
          'TraceAnalyst::Redactor',
          {
            @subject_key.to_sym => @subject_id,
            investigation: @investigation,
            redacted_keys: redactions,
            count: redactions.length
          }
        )
      end
    end
  end
end
