require 'net/http'
require 'uri'

require 'puppet/network/http_pool'
require 'puppet/network/http/api/v1'
require 'puppet/network/http/compression'

# Access objects via REST
class Puppet::Indirector::REST < Puppet::Indirector::Terminus
  include Puppet::Network::HTTP::API::V1
  include Puppet::Network::HTTP::Compression.module

  class << self
    attr_reader :server_setting, :port_setting
  end

  # Specify the setting that we should use to get the server name.
  def self.use_server_setting(setting)
    @server_setting = setting
  end

  def self.server
    Puppet.settings[server_setting || :server]
  end

  # Specify the setting that we should use to get the port.
  def self.use_port_setting(setting)
    @port_setting = setting
  end

  def self.port
    Puppet.settings[port_setting || :masterport].to_i
  end

  # Provide appropriate headers.
  def headers
    add_accept_encoding({"Accept" => model.supported_formats.join(", ")})
  end

  def network(request)
    Puppet::Network::HttpPool.http_instance(request.server || self.class.server, request.port || self.class.port)
  end

  def find(request)
    response = network(request).get(indirection2uri(request), headers)

    if is_http_200?(response)
      content_type, body = parse_response(response)
      result = deserialize_find(content_type, body)
      result.name = request.key if result.respond_to?(:name=)
      result
    else
      nil
    end
  end

  def head(request)
    response = network(request).head(indirection2uri(request), headers)

    !!is_http_200?(response)
  end

  def search(request)
    response = network(request).get(indirection2uri(request), headers)

    if is_http_200?(response)
      content_type, body = parse_response(response)
      deserialize_search(content_type, body) || []
    else
      []
    end
  end

  def destroy(request)
    raise ArgumentError, "DELETE does not accept options" unless request.options.empty?

    response = network(request).delete(indirection2uri(request), headers)

    if is_http_200?(response)
      content_type, body = parse_response(response)
      deserialize_destroy(content_type, body)
    else
      nil
    end
  end

  def save(request)
    raise ArgumentError, "PUT does not accept options" unless request.options.empty?

    response = network(request).put(indirection2uri(request), request.instance.render, headers.merge({ "Content-Type" => request.instance.mime }))

    if is_http_200?(response)
      content_type, body = parse_response(response)
      deserialize_save(content_type, body)
    else
      nil
    end
  end

  def validate_key(request)
    # Validation happens on the remote end
  end

  private

  def is_http_200?(response)
    case response.code
    when "404"
      false
    when /^2/
      true
    else
      # Raise the http error if we didn't get a 'success' of some kind.
      raise convert_to_http_error(response)
    end
  end

  def convert_to_http_error(response)
    message = "Error #{response.code} on SERVER: #{(response.body||'').empty? ? response.message : uncompress_body(response)}"
    Net::HTTPError.new(message, response)
  end

  # Returns the content_type, stripping any appended charset, and the
  # body, decompressed if necessary (content-encoding is checked inside
  # uncompress_body)
  def parse_response(response)
    if response['content-type']
      [ response['content-type'].gsub(/\s*;.*$/,''),
        body = uncompress_body(response) ]
    else
      raise "No content type in http response; cannot parse"
    end
  end

  def deserialize_find(content_type, body)
    model.convert_from(content_type, body)
  end

  def deserialize_search(content_type, body)
    model.convert_from_multiple(content_type, body)
  end

  def deserialize_destroy(content_type, body)
    model.convert_from(content_type, body)
  end

  def deserialize_save(content_type, body)
    nil
  end

  def environment
    Puppet::Node::Environment.new
  end
end
