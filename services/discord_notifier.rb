# frozen_string_literal: true
# encoding: UTF-8

require "net/http"
require "uri"
require "json"

module Services
  class DiscordNotifier
    def initialize(webhook_url:, logger: nil)
      @webhook_url = webhook_url
      @logger = logger
    end

    def notify(message)
      uri = URI(@webhook_url)

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"

      request.body = JSON.generate({
        content: message
      })

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        @logger&.error("Discord webhook error: #{response.code} #{response.body}")
        raise "Discord webhook error: #{response.code} #{response.body}"
      end

      true
    end
  end
end
