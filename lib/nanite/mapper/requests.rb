require "nanite/helpers/state_helper"
require "nanite/cluster"

module Nanite
  class Mapper
    class Requests
      include Nanite::AMQPHelper
      include Nanite::Cluster

      attr_reader :options, :amqp, :serializer, :mapper, :security, :running

      def initialize(options = {})
        @options = options
        @serializer = Serializer.new(@options[:format])
        @security = SecurityProvider.get
        @mapper = options[:mapper]
      end

      def run
        @amqp = options[:amqp] || start_amqp(@options)
        setup_request_queue
        @running = true
      end

      def setup_request_queue
        handler = lambda do |msg|
          begin
            handle_request(serializer.load(msg))
          rescue Exception => e
            Nanite::Log.error("RECV [request] #{e.message}")
          end
        end

        requests_fanout = amqp.fanout('request', :durable => true)
        if shared_state?
          amqp.queue("request", :durable => true).bind(requests_fanout).subscribe(&handler)
        else
          amqp.queue("request-#{options[:identity]}", :exclusive => true, :durable => true).bind(requests_fanout).subscribe(&handler)
        end
      end

      # forward request coming from agent
      def handle_request(request)
        if @security.authorize_request(request)
          Nanite::Log.debug("RECV #{request.to_s}")
          case request
          when Push
            mapper.send_push(request)
          when Request
            mapper.send_request(request)
          end
        else
          Nanite::Log.warn("RECV NOT AUTHORIZED #{request.to_s}")
        end
      end
    end
  end
end
