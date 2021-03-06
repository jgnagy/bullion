# frozen_string_literal: true

module Bullion
  module Helpers
    # SSL-related helper methods
    module Ssl
      # Converts the incoming key data to an OpenSSL public key usable to verify JWT signatures
      def openssl_compat(key_data)
        case key_data['kty']
        when 'RSA'
          key_data_to_rsa(key_data)
        when 'EC'
          key_data_to_ecdsa(key_data)
        end
      end

      def openssl_compat_csr(csrdata)
        "-----BEGIN CERTIFICATE REQUEST-----\n" \
        "#{csrdata}-----END CERTIFICATE REQUEST-----"
      end

      # @see https://tools.ietf.org/html/rfc7518#page-30
      def key_data_to_rsa(key_data)
        key = OpenSSL::PKey::RSA.new
        exponent = key_data['e']
        modulus = key_data['n']

        key.set_key(
          base64_to_long(modulus),
          base64_to_long(exponent),
          nil
        )
        key
      end

      def key_data_to_ecdsa(key_data)
        crv_mapping = {
          'P-256' => 'prime256v1',
          'P-384' => 'secp384r1',
          'P-521' => 'secp521r1'
        }

        key = OpenSSL::PKey::EC.new(crv_mapping[key_data['crv']])
        x = base64_to_octet(key_data['x'])
        y = base64_to_octet(key_data['y'])

        key_bn = OpenSSL::BN.new("\x04#{x}#{y}", 2)
        key.public_key = OpenSSL::PKey::EC::Point.new(key.group, key_bn)
        key
      end

      def base64_to_long(data)
        Base64.urlsafe_decode64(data).to_s.unpack('C*').map do |byte|
          to_hex(byte)
        end.join.to_i(16)
      end

      def base64_to_octet(data)
        Base64.urlsafe_decode64(data)
      end

      def digest_from_alg(alg)
        if alg.end_with?('256')
          OpenSSL::Digest.new('SHA256')
        elsif alg.end_with?('384')
          OpenSSL::Digest.new('SHA384')
        else
          OpenSSL::Digest.new('SHA512')
        end
      end

      # This is for ECDSA keys.
      # @see https://bit.ly/3b7yZFd
      def ecdsa_sig_to_der(incoming)
        # Base64 decode the signature
        joined_ints = Base64.urlsafe_decode64(incoming)
        # Break it apart into the two 32-byte words
        r = joined_ints[0..31]
        s = joined_ints[32..]
        # Unpack each word to a hex string
        hexnums = [r, s].map { |n| n.unpack1('H*') }
        # Convert each to an Integer
        ints = hexnums.map { |bn| bn.to_i(16) }
        # Convert each Integer to a BigNumber
        bns = ints.map { |int| OpenSSL::BN.new(int) }
        # Wrap each BigNum in a ASN1 encoding
        asn1_wrapped = bns.map { |bn| OpenSSL::ASN1::Integer.new(bn) }
        # Create an ASN1 sequence from the ASN1-wrapped Integers
        seq = OpenSSL::ASN1::Sequence.new(asn1_wrapped)
        # Return the DER-encoded sequence for verification
        seq.to_der
      end

      def to_hex(int)
        int < 16 ? "0#{int.to_s(16)}" : int.to_s(16)
      end

      def simple_subject(common_name)
        OpenSSL::X509::Name.new([['CN', common_name, OpenSSL::ASN1::UTF8STRING]])
      end

      def manage_csr_extensions(csr, new_cert)
        # Build extensions
        ef = OpenSSL::X509::ExtensionFactory.new
        ef.subject_certificate = new_cert
        ef.issuer_certificate = Bullion.ca_cert
        new_cert.add_extension(
          ef.create_extension('basicConstraints', 'CA:FALSE', true)
        )
        new_cert.add_extension(
          ef.create_extension('keyUsage', 'keyEncipherment,dataEncipherment,digitalSignature', true)
        )
        new_cert.add_extension(
          ef.create_extension('subjectKeyIdentifier', 'hash')
        )
        new_cert.add_extension(
          ef.create_extension('extendedKeyUsage', 'serverAuth')
        )

        # Alternate Names
        cn = cn_from_csr(csr)
        existing_sans = filter_sans(csr_sans(csr))
        valid_alts = (["DNS:#{cn}"] + [*existing_sans]).uniq

        new_cert.add_extension(ef.create_extension('subjectAltName', valid_alts.join(',')))

        # return the updated cert and any subject alternate names added
        [new_cert, valid_alts]
      end

      def csr_sans(csr)
        raw_attributes = csr.attributes
        return [] unless raw_attributes

        seq = extract_csr_seq(raw_attributes)
        return [] unless seq

        values = extract_san_values(seq)
        return [] unless values

        values = OpenSSL::ASN1.decode(values).value

        values.select { |v| v.tag == 2 }.map { |v| "DNS:#{v.value}" }
      end

      def extract_csr_attrs(attrs)
        attrs.select { |a| a.oid == 'extReq' }.map(&:value).first
      end

      def extract_san_values(sequence)
        seqvalues = nil
        sequence.value.each do |v|
          v.each do |innerv|
            if innerv.value[0].value == 'subjectAltName'
              seqvalues = innerv.value[1].value
              break
            end
            break if seqvalues
          end
        end
        seqvalues
      end

      def filter_sans(potential_sans)
        # Select only those that are part of the appropriate domain
        potential_sans.select { |alt| alt.match(/#{CA_DOMAIN}$/) }
      end

      def cn_from_csr(csr)
        if csr.subject.to_s
          cns = csr.subject.to_s.split('/').select { |name| name =~ /^CN=/ }

          return cns.first.split('=').last if cns && !cns.empty?
        end

        csr_sans(csr).first.split(':').last
      end

      # Signs an ACME CSR
      # rubocop:disable Metrics/AbcSize
      def sign_csr(csr, username)
        cert = Models::Certificate.from_csr(csr)
        # Create a OpenSSL cert using select info from the CSR
        csr_cert = OpenSSL::X509::Certificate.new
        csr_cert.serial = cert.serial
        csr_cert.version = 2
        csr_cert.not_before = Time.now
        # only 90 days for ACMEv2
        csr_cert.not_after = csr_cert.not_before + (3 * 30 * 24 * 60 * 60)

        # Force a subject if the cert doesn't have one
        cert.subject = simple_subject(cn_from_csr(csr)) unless cert.subject

        csr_cert.subject = cert.subject.to_s

        csr_cert.public_key = csr.public_key
        csr_cert.issuer = Bullion.ca_cert.issuer

        csr_cert, sans = manage_csr_extensions(csr, csr_cert)

        csr_cert.sign(Bullion.ca_key, OpenSSL::Digest.new('SHA256'))

        cert.data = csr_cert.to_pem
        cert.alternate_names = sans unless sans.empty?
        cert.requester = username
        cert.validated = true
        cert.save

        [csr_cert, cert.id]
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
