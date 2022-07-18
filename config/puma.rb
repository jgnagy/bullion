# frozen_string_literal: true

threads 2, Integer(ENV.fetch("MAX_THREADS", 32))
