# frozen_string_literal: true

module Bullion
  # Superclass for executing ACMEv2 Challenges
  class ChallengeClient
    ChallengeClientMetric = Prometheus::Client::Histogram.new(
      :challenge_execution_seconds,
      docstring: "Challenge execution histogram in seconds",
      labels: %i[acme_type status]
    )
    MetricsRegistry.register(ChallengeClientMetric)

    attr_accessor :challenge

    def initialize(challenge)
      @challenge = challenge
    end

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def attempt(retries: 4)
      tries = 0
      success = false

      benchtime = Benchmark.realtime do
        until success || tries >= retries
          tries += 1
          success = perform
          if success
            LOGGER.info "Validated #{type} #{identifier}"
            challenge.status = "valid"
            challenge.validated = Time.now
          else
            sleep rand(2..4)
          end
        end
      end

      unless success
        LOGGER.info "Failed to validate #{type} #{identifier}"
        challenge.status = "invalid"
      end

      challenge.save

      ChallengeClientMetric.observe(
        benchtime, labels: { acme_type: type, status: challenge.status }
      )

      success
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength

    def identifier
      challenge.authorization.identifier["value"]
    end
  end
end
