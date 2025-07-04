# frozen_string_literal: true

module Bullion
  module Models
    # Pseudo-model for ACMEv2 Order CSR
    class OrderCsr
      class << self
        def from_acme_request(order, raw_data)
          decoded_data = Base64.urlsafe_decode64(raw_data)
          reencoded_data = Base64.encode64(decoded_data)
          csr_string = openssl_compat_csr(reencoded_data)

          new(order, csr_string)
        end

        private

        def openssl_compat_csr(csrdata)
          "-----BEGIN CERTIFICATE REQUEST-----\n" \
            "#{csrdata}-----END CERTIFICATE REQUEST-----"
        end
      end

      attr_reader :csr, :order

      def initialize(order, csr)
        @order = order.is_a?(Order) ? order : Order.find(order)
        @csr = if csr.is_a?(String)
                 OpenSSL::X509::Request.new(csr)
               else
                 csr
               end
      end
    end
  end
end
