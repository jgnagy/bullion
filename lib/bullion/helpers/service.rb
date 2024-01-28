# frozen_string_literal: true

module Bullion
  module Helpers
    # Sinatra service helper methods
    module Service
      def add_acme_headers(nonce, additional: {})
        headers["Replay-Nonce"] = nonce
        add_link_relation("index", uri("/directory"))

        additional.each do |name, value|
          headers[name.to_s] = value.to_s
        end
      end

      def add_link_relation(type, value)
        cur = link_headers_to_hash(headers["Link"])
        cur[type] = value
        headers["Link"] = hashed_links_to_link_headers(cur)
      end

      private

      def link_headers_to_hash(values_string)
        return {} unless values_string&.length&.positive?

        values_string.split(",").to_h do |relation|
          raw_value, raw_name = relation.split(";")
          value = /^<(.+)>$/.match(raw_value)[1]
          name = /^rel="(.+)"$/.match(raw_name)[1]
          [name, value]
        end
      end

      def hashed_links_to_link_headers(hash)
        hash.reduce([]) do |acc, data|
          name = "rel=\"#{data[0]}\""
          value = "<#{data[1]}>"
          acc << [value, name].join(";")
        end.join(",")
      end
    end
  end
end
