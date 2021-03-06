module Services
  class LiveEventsSubscriptionService
    class << self
      def available?
        settings.present?
      end

      def tool_proxy_subscriptions(tool_proxy)
        options = {
          headers: headers({
            sub: "ltiToolProxy:#{tool_proxy.guid}",
            developerKey: tool_proxy.product_family.developer_key
          })
        }
        request(:get, '/api/subscriptions', options)
      end

      private
      def request(method, endpoint, options = {})
        Canvas.timeout_protection("live-events-subscription-service-session", raise_on_timeout: true) do
          HTTParty.send(method, "#{settings['app-host']}#{endpoint}", options.merge(timeout: 10))
        end
      end

      def headers(jwt_body, headers = {})
        token = Canvas::Security::ServicesJwt.generate(jwt_body)
        headers['Authorization'] = "Bearer #{token}"
        headers
      end

      def settings
        Canvas::DynamicSettings.from_cache("live-events-subscription-service", expires_in: 5.minutes)
      rescue Faraday::ConnectionFailed,
             Faraday::ClientError,
             Canvas::DynamicSettings::ConsulError,
             Diplomat::KeyNotFound => e
        Canvas::Errors.capture_exception(:live_events_subscription, e)
        nil
      end
    end
  end
end
