# frozen_string_literal: true

require 'set'

module TraceAnalyst
  class TypeError < StandardError; end

  # Redacts PII from debug payloads. Type guard + field-name regex pass.
  class Redactor
    DEFAULT_PATTERNS = [
      [/email/i,             'email'],
      [/phone/i,             'phone'],
      [/address/i,           'address'],
      [/zip|postal/i,        'zip'],
      [/^name$/i,            'name'],
      [/ssn|tax_id/i,        'ssn'],
      [/account_number/i,    'account_number'],
      [/credit_card|cc_num/i, 'credit_card']
    ].freeze

    ALLOWED_VALUE_TYPES = [Numeric, String, Symbol, TrueClass, FalseClass, NilClass].freeze

    @custom_patterns = []

    class << self
      def register_pattern(pattern, label:)
        @custom_patterns << [pattern, label]
      end

      def reset_custom_patterns!
        @custom_patterns = []
      end

      def patterns
        DEFAULT_PATTERNS + @custom_patterns
      end

      # Returns [redacted_data, redactions].
      def redact(data, allow_pii: [])
        assert_value_allowed!(data, key_path: '<root>')

        redactions = []
        allow_set = allow_pii.map(&:to_s).to_set
        redacted = walk(data, key_path: '', allow_set: allow_set, redactions: redactions)

        [redacted, redactions]
      end

      private

      def walk(value, key_path:, allow_set:, redactions:)
        case value
        when Hash
          value.each_with_object({}) do |(k, v), acc|
            key_str = k.to_s
            child_path = key_path.empty? ? key_str : "#{key_path}.#{key_str}"

            if !allow_set.include?(key_str) && (label = match_pattern(key_str))
              redactions << child_path
              acc[k] = "[REDACTED:#{label}]"
            else
              acc[k] = walk(v, key_path: child_path, allow_set: allow_set, redactions: redactions)
            end
          end
        when Array
          value.each_with_index.map do |element, i|
            walk(element, key_path: "#{key_path}[#{i}]", allow_set: allow_set, redactions: redactions)
          end
        else
          value
        end
      end

      def match_pattern(key)
        patterns.each do |pattern, label|
          return label if pattern.match?(key)
        end
        nil
      end

      def assert_value_allowed!(value, key_path:)
        case value
        when Hash
          value.each do |k, v|
            child_path = key_path == '<root>' ? k.to_s : "#{key_path}.#{k}"
            unless k.is_a?(Symbol) || k.is_a?(String)
              raise TraceAnalyst::TypeError,
                    "TraceAnalyst.log key at #{child_path} must be Symbol or String (got #{k.class})"
            end
            assert_value_allowed!(v, key_path: child_path)
          end
        when Array
          value.each_with_index { |v, i| assert_value_allowed!(v, key_path: "#{key_path}[#{i}]") }
        else
          allowed = ALLOWED_VALUE_TYPES.any? { |type| value.is_a?(type) }
          unless allowed
            raise TraceAnalyst::TypeError,
                  "TraceAnalyst.log value at #{key_path} must be a scalar, Array, or Hash (got #{value.class}). " \
                  'Pluck explicit fields rather than passing whole records.'
          end
        end
      end
    end
  end
end
