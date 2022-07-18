# frozen_string_literal: true

RSpec.describe Bullion::Services::Ping do
  def app
    described_class
  end

  let(:healthcheck_response) do
    { "status" => "up" }
  end

  let(:allowed_req_methods) do
    %w[GET]
  end

  it "allows access to the ping service" do
    get "/"
    expect(last_response).to be_ok
    expect(JSON.parse(last_response.body)).to eq(healthcheck_response)
  end

  it "provides reasonable OPTIONS for the ping service" do
    options "/"
    expect(last_response).to be_ok
    expect(last_response.headers["Access-Control-Allow-Methods"].sort).to eq(allowed_req_methods)
  end
end
