# frozen_string_literal: true

module Bullion
  module Models
    # Pseudo-model for ACMEv2 Order CSR
    class OrderCsr
      class << self
        def from_acme_request(order, raw_data)
          decoded_data = Base64.urlsafe_decode64(raw_data.to_s)
          reencoded_data = Base64.encode64(decoded_data)
          csr_string = openssl_compat_csr(reencoded_data)

          new(order, csr_string)
        rescue ArgumentError, OpenSSL::X509::RequestError
          # A payload that is not valid base64url or does not parse as a
          # PKCS#10 request is an unacceptable CSR, not a server fault.
          raise Bullion::Acme::Errors::BadCsr, "Unable to parse CSR from the request payload"
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
